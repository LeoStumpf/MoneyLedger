import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../expenses/expenses_provider.dart';
import '../groups/group_provider.dart';
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
  final messenger = ScaffoldMessenger.of(context);
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

  final draft = await showDialog<PaymentDraft>(
    context: context,
    builder: (_) => RecordPaymentDialog(
      participants: participants,
      initialFrom: debt?.from ?? defaultFrom,
      initialTo: debt?.to ?? defaultTo,
      initialCents: debt?.cents,
      debtCents: debt?.cents,
      currency: debt?.currency ?? group?.currency ?? 'EUR',
    ),
  );
  if (draft == null || !context.mounted) return;

  await ref
      .read(expenseAdderProvider.notifier)
      .addSettlement(
        roomId: roomId,
        amountCents: draft.cents,
        currency: draft.currency,
        fromUser: draft.from,
        toUser: draft.to,
        day: draft.day,
      );

  if (!context.mounted) return;
  final error = ref.read(expenseAdderProvider).error;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        error != null ? l.failedWithError(error.toString()) : l.paymentRecorded,
      ),
    ),
  );
}

/// The debt *Settle up* proposes for [myId] (G17): the first suggested
/// payment I make, else the first one I receive, else none (blank dialog).
DebtEntry? settleUpSuggestion(List<DebtEntry> debts, String myId) =>
    debts.where((d) => d.from == myId).firstOrNull ??
    debts.where((d) => d.to == myId).firstOrNull;
