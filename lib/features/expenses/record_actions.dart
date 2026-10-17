import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/sync/record_signing.dart' show RecordKind;
import '../../core/theme/app_theme.dart';
import '../../core/widgets/action_error.dart';
import '../../models/expense_model.dart';
import 'expenses_provider.dart';
import 'record_attribution.dart';
import 'record_undo.dart';

/// How long the "Deleted · Undo" snackbar stays (U13: 6–8 s).
const kUndoSnackDuration = Duration(seconds: 8);

/// G67 (U13): a confirmation snackbar for a write the user just made, with
/// *Undo* when [write] is given. Everything it needs is captured now (the
/// page that made the write may be gone when *Undo* is tapped): the
/// messenger, the strings, the account's [RecordUndoer].
void showUndoSnackBar(
  BuildContext context,
  WidgetRef ref,
  String message,
  UndoableWrite? write,
) => UndoSnack.of(context, ref).show(message, write);

/// [showUndoSnackBar] with its dependencies captured up front — for flows
/// that show the snackbar after an await.
class UndoSnack {
  UndoSnack.of(BuildContext context, WidgetRef ref)
    : _messenger = ScaffoldMessenger.of(context),
      _errors = ActionErrors.of(context),
      _l = context.l10n,
      _undoer = ref.read(recordUndoerProvider);

  final ScaffoldMessengerState _messenger;
  final ActionErrors _errors;
  final AppLocalizations _l;
  final RecordUndoer _undoer;

  /// Shows [message]; with [write], an *Undo* action.
  void show(String message, UndoableWrite? write) {
    if (!_messenger.mounted) return;
    _messenger.hideCurrentSnackBar();
    _messenger.showSnackBar(
      SnackBar(
        key: const Key('undoSnack'),
        duration: write == null
            ? const Duration(seconds: 4)
            : kUndoSnackDuration,
        // An undo snackbar must not hang around forever under TalkBack
        // (accessible navigation keeps snackbars open until dismissed).
        persist: false,
        content: Text(message),
        action: write == null
            ? null
            : SnackBarAction(
                key: const Key('undoAction'),
                label: _l.undo,
                onPressed: () => _undo(write),
              ),
      ),
    );
  }

  Future<void> _undo(UndoableWrite write) async {
    try {
      final outcome = await _undoer.undo(write);
      if (!_messenger.mounted) return;
      _messenger.hideCurrentSnackBar();
      _messenger.showSnackBar(
        SnackBar(
          key: const Key('undoResultSnack'),
          content: Text(
            outcome == UndoOutcome.undone
                ? _l.undoDone
                : _l.undoChangedMeanwhile,
          ),
        ),
      );
    } catch (e) {
      _errors.show(e);
    }
  }
}

/// "Delete expense?" — true = confirmed.
Future<bool> confirmDeleteExpense(
  BuildContext context,
  ExpenseModel expense,
) async {
  final l = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.deleteExpenseTitle),
      content: Text(l.deleteExpenseBody(expense.description)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('confirmDelete'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.delete),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// "Delete payment?" with who / how much and the G6 attribution — true =
/// confirmed.
Future<bool> confirmDeleteSettlement(
  BuildContext context,
  SettlementModel settlement, {
  required String fromName,
  required String toName,
}) async {
  final l = context.l10n;
  final amount = context.money(settlement.amountCents, settlement.currency);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.deleteSettlementTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.deleteSettlementBody(fromName, toName, amount)),
          // G6: who recorded (and last changed) this payment.
          const SizedBox(height: Insets.m),
          RecordAttribution(
            groupId: settlement.roomId,
            kind: RecordKind.settlement,
            recordId: settlement.id,
            origin: settlement.origin,
            sig: settlement.sig,
            createdAt: settlement.createdAt,
            updatedAt: settlement.updatedAt,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('confirmDelete'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.delete),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// G67: confirm → delete [expense] (a tombstone, G6-signed) → "Deleted …"
/// with *Undo*, or a friendly error. [skipConfirm]: the caller already
/// asked. Returns whether it was deleted. The caller keeps
/// `expenseAdderProvider` watched.
Future<bool> deleteExpenseFlow(
  BuildContext context,
  WidgetRef ref,
  ExpenseModel expense, {
  bool skipConfirm = false,
}) async {
  if (!skipConfirm && !await confirmDeleteExpense(context, expense)) {
    return false;
  }
  if (!context.mounted) return false;
  final snack = UndoSnack.of(context, ref);
  final errors = ActionErrors.of(context);
  final l = context.l10n;
  final write = await ref
      .read(expenseAdderProvider.notifier)
      .deleteExpense(expense.id, expense.roomId);
  if (write == null) {
    final error = context.mounted ? ref.read(expenseAdderProvider).error : null;
    if (error != null) errors.show(error);
    return false;
  }
  snack.show(l.expenseDeletedSnack(expense.description), write);
  return true;
}

/// G67: like [deleteExpenseFlow] for a payment ("Payment deleted" · Undo).
Future<bool> deleteSettlementFlow(
  BuildContext context,
  WidgetRef ref,
  SettlementModel settlement, {
  required String fromName,
  required String toName,
  bool skipConfirm = false,
}) async {
  if (!skipConfirm &&
      !await confirmDeleteSettlement(
        context,
        settlement,
        fromName: fromName,
        toName: toName,
      )) {
    return false;
  }
  if (!context.mounted) return false;
  final snack = UndoSnack.of(context, ref);
  final errors = ActionErrors.of(context);
  final l = context.l10n;
  final write = await ref
      .read(expenseAdderProvider.notifier)
      .deleteSettlement(settlement.id, settlement.roomId);
  if (write == null) {
    final error = context.mounted ? ref.read(expenseAdderProvider).error : null;
    if (error != null) errors.show(error);
    return false;
  }
  snack.show(l.paymentDeletedSnack, write);
  return true;
}
