import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/record_signing.dart' show RecordKind;
import '../../core/l10n/l10n.dart';
import '../../models/expense_date.dart';
import '../../models/expense_model.dart';
import '../expenses/expenses_provider.dart';
import '../expenses/group_currencies.dart';
import '../expenses/record_attribution.dart';
import '../expenses/record_actions.dart';
import '../../core/widgets/action_error.dart';
import '../groups/group_provider.dart';
import '../payment/payment_details_provider.dart';
import '../payment/payment_request_sheet.dart';
import 'balance_calculator.dart';
import 'record_payment_dialog.dart';

/// Opens the payment dialog (G28) — prefilled from [debt] (debtor →
/// creditor, the owed amount) or, without one, with [myId] as the payer —
/// and records the confirmed payment as a settlement. Shared by the balance
/// page (tapped debt rows, the app-bar action) and the group summary card's
/// *Settle up* (G17).
///
/// The caller keeps `groupMembersProvider(roomId)`, `ledgerGroupsProvider`
/// and `expenseAdderProvider` watched, so they are alive here.
Future<void> recordPaymentFlow(
  BuildContext context,
  WidgetRef ref,
  String roomId, {
  required String myId,
  DebtEntry? debt,
}) async {
  final snack = UndoSnack.of(context, ref);
  final errors = ActionErrors.of(context);
  final l = context.l10n;
  final members = ref.read(groupMembersProvider(roomId)).value ?? const [];
  final names = ref.read(participantNamesProvider(roomId));
  final group = (ref.read(ledgerGroupsProvider).value ?? const [])
      .where((g) => g.roomId == roomId)
      .firstOrNull;
  // Active participants (claimed and local); a tapped debt may involve a
  // former member, who stays selectable for that payment.
  final participants = <String, String>{
    for (final m in members)
      if (m.isActive) m.userId: names[m.userId] ?? m.label,
    if (debt != null) debt.from: names[debt.from] ?? debt.from,
    if (debt != null) debt.to: names[debt.to] ?? debt.to,
  };
  final ids = participants.keys.toList();
  final defaultFrom = participants.containsKey(myId)
      ? myId
      : (ids.isNotEmpty ? ids.first : null);
  final defaultTo = ids.where((id) => id != defaultFrom).firstOrNull;
  final currency = debt?.currency ?? group?.currency ?? 'EUR';
  final payeeDetails = creditorPaymentDetails(
    members,
    myId: myId,
    mine: ref.read(myPaymentDetailsProvider).value,
  );
  // G66: the group's currencies first in the picker.
  final suggested = await groupCurrencySuggestions(
    ref,
    roomId,
    selected: currency,
    groupCurrency: group?.currency,
  );
  if (!context.mounted) return;

  final draft = await showDialog<PaymentDraft>(
    context: context,
    builder: (_) => RecordPaymentDialog(
      participants: participants,
      initialFrom: debt?.from ?? defaultFrom,
      initialTo: debt?.to ?? defaultTo,
      initialCents: debt?.cents,
      debtCents: debt?.cents,
      currency: currency,
      suggestedCurrencies: suggested,
      // G74: the recipient's payment details (IBAN / PayPal.me / GiroCode).
      payeeDetails: payeeDetails,
      onShowPaymentDetails: (dialogContext, p) => showPaymentRequestSheet(
        dialogContext,
        details: payeeDetails[p.to]!,
        debt: p,
        payerName: participants[p.from] ?? p.from,
        payeeName: participants[p.to] ?? p.to,
        groupName: group?.name ?? '',
        mine: p.to == myId,
        payerIsMe: p.from == myId,
      ),
    ),
  );
  if (draft == null || !context.mounted) return;

  final write = await ref
      .read(expenseAdderProvider.notifier)
      .addSettlement(
        roomId: roomId,
        amountCents: draft.cents,
        currency: draft.currency,
        fromUser: draft.from,
        toUser: draft.to,
        day: draft.day,
      );

  if (write != null) {
    // G67 (U13): "Payment recorded" · Undo.
    snack.show(l.paymentRecorded, write);
    return;
  }
  final error = context.mounted ? ref.read(expenseAdderProvider).error : null;
  if (error != null) errors.show(error);
}

/// G60: edits the recorded payment [settlement] — the payment dialog in edit
/// mode, prefilled (from, to, amount, currency, day) with the G6
/// attribution under the fields; *Save* writes a new version
/// ([ExpenseAdder.updateSettlement]: next LWW clock, signed by this device,
/// origin kept, relayed). The caller only offers it in groups that aren't
/// read-only; it keeps the same providers alive as [recordPaymentFlow].
Future<void> editPaymentFlow(
  BuildContext context,
  WidgetRef ref,
  String roomId,
  SettlementModel settlement,
) async {
  final snack = UndoSnack.of(context, ref);
  final errors = ActionErrors.of(context);
  final l = context.l10n;
  final members = ref.read(groupMembersProvider(roomId)).value ?? const [];
  final names = ref.read(participantNamesProvider(roomId));
  // Active participants, plus the payment's own two sides (a former member
  // stays selectable for the payment they took part in).
  final participants = <String, String>{
    for (final m in members)
      if (m.isActive) m.userId: names[m.userId] ?? m.label,
    settlement.fromUser: names[settlement.fromUser] ?? settlement.fromUser,
    settlement.toUser: names[settlement.toUser] ?? settlement.toUser,
  };
  final initialDay = settlement.displayDay;
  final group = (ref.read(ledgerGroupsProvider).value ?? const [])
      .where((g) => g.roomId == roomId)
      .firstOrNull;
  final suggested = await groupCurrencySuggestions(
    ref,
    roomId,
    selected: settlement.currency,
    groupCurrency: group?.currency,
  );
  if (!context.mounted) return;
  final result = await showDialog<Object>(
    context: context,
    builder: (_) => RecordPaymentDialog(
      editing: true,
      canDelete: true,
      participants: participants,
      initialFrom: settlement.fromUser,
      initialTo: settlement.toUser,
      initialCents: settlement.amountCents,
      currency: settlement.currency,
      suggestedCurrencies: suggested,
      initialDay: initialDay,
      footer: RecordAttribution(
        groupId: roomId,
        kind: RecordKind.settlement,
        recordId: settlement.id,
        origin: settlement.origin,
        sig: settlement.sig,
        linkAuthor: settlement.linkAuthor,
        createdAt: settlement.createdAt,
        updatedAt: settlement.updatedAt,
        members: members,
      ),
    ),
  );
  if (result == null || !context.mounted) return;
  if (result is PaymentDeleteRequest) {
    // G67 (U13): delete from the edit dialog — same confirm + undo.
    await deleteSettlementFlow(
      context,
      ref,
      settlement,
      fromName: participants[settlement.fromUser] ?? settlement.fromUser,
      toName: participants[settlement.toUser] ?? settlement.toUser,
    );
    return;
  }
  final draft = result as PaymentDraft;

  final write = await ref
      .read(expenseAdderProvider.notifier)
      .updateSettlement(
        id: settlement.id,
        roomId: roomId,
        amountCents: draft.cents,
        currency: draft.currency,
        fromUser: draft.from,
        toUser: draft.to,
        // Same day as before → the stored date unchanged (as for expenses).
        date: draft.day == initialDay
            ? settlement.date
            : storedExpenseDate(draft.day, settlement.createdAt),
      );

  if (write != null) {
    snack.show(l.paymentUpdated, write);
    return;
  }
  final error = context.mounted ? ref.read(expenseAdderProvider).error : null;
  if (error is RecordDeletedException) {
    snack.show(l.paymentGone, null);
  } else if (error != null) {
    errors.show(error);
  }
}

/// The debt *Settle up* proposes for [myId] (G17): the first suggested
/// payment I make, else the first one I receive, else none (blank dialog).
DebtEntry? settleUpSuggestion(List<DebtEntry> debts, String myId) =>
    debts.where((d) => d.from == myId).firstOrNull ??
    debts.where((d) => d.to == myId).firstOrNull;
