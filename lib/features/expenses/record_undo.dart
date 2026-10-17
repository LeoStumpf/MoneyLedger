import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/history_dao.dart';
import '../../core/sync/record_signing.dart' show RecordKind;
import '../../core/sync/record_validation.dart';
import '../../core/sync/record_version.dart';
import '../../models/expense_model.dart';
import '../../models/member_model.dart' show nextLwwClock;
import '../history/group_history.dart';
import '../history/group_reset.dart';
import 'expenses_provider.dart';

/// G67 (U13) — undo of one local write of an expense or payment.
///
/// A write the user just made (delete, record a payment, add an expense)
/// hands back an [UndoableWrite]: the version it stored and the content
/// before it (none for a creation). *Undo* writes a **new version** with the
/// earlier content — exactly like a G48 reset of that one record
/// ([GroupResetService.apply]: `nextLwwClock`, the creator's `origin` kept,
/// signed by this device / `pendingSign` without a key / unsigned in a
/// link-only group, history source `revert`, relayed like an edit). Undoing
/// a creation writes a tombstone.
///
/// It only undoes **its own** version: when the record changed after it
/// (someone else edited / deleted / restored it meanwhile, or another undo)
/// nothing is written ([UndoOutcome.changedMeanwhile]) — undo never
/// overwrites a change the user hasn't seen.
class UndoableWrite {
  const UndoableWrite.expense({
    required ExpenseModel this.writtenExpense,
    this.beforeExpense,
  }) : writtenSettlement = null,
       beforeSettlement = null;

  const UndoableWrite.settlement({
    required SettlementModel this.writtenSettlement,
    this.beforeSettlement,
  }) : writtenExpense = null,
       beforeExpense = null;

  /// The version this write stored (signed / pending / link version).
  final ExpenseModel? writtenExpense;
  final SettlementModel? writtenSettlement;

  /// The stored version before the write; null = the write created it.
  final ExpenseModel? beforeExpense;
  final SettlementModel? beforeSettlement;

  RecordKind get kind =>
      writtenExpense != null ? RecordKind.expense : RecordKind.settlement;
  String get groupId => writtenExpense?.roomId ?? writtenSettlement!.roomId;
  String get recordId => writtenExpense?.id ?? writtenSettlement!.id;
}

/// What an undo did.
enum UndoOutcome {
  /// The earlier content was written as a new version.
  undone,

  /// The record changed after the write (or is gone) — nothing written.
  changedMeanwhile,
}

/// The new version that undoes [write], given what is stored **now**
/// ([currentExpense] / [currentSettlement]) — or null when the stored
/// version isn't the one [write] wrote (changed meanwhile / gone), or the
/// earlier content breaks today's content rules. Pure.
ResetChange? planUndo(
  UndoableWrite write, {
  ExpenseModel? currentExpense,
  SettlementModel? currentSettlement,
  int? now,
}) {
  if (write.writtenExpense case final written?) {
    final cur = currentExpense;
    if (cur == null ||
        cur.roomId != written.roomId ||
        cur.updatedAt != written.updatedAt ||
        expenseVersionHash(cur) != expenseVersionHash(written)) {
      return null;
    }
    final clock = nextLwwClock(cur.updatedAt, now: now);
    final before = write.beforeExpense;
    if (before == null || before.deleted) {
      // Undo a creation (or a restore): the record goes again.
      if (cur.deleted) return null;
      return ResetChange.expense(
        ResetEffect.removed,
        resetExpenseVersion(cur, clock, deleted: true, origin: cur),
      );
    }
    final next = resetExpenseVersion(
      before,
      clock,
      deleted: false,
      origin: cur,
    );
    if (expenseProblem(next) != null) return null;
    return ResetChange.expense(
      cur.deleted ? ResetEffect.restored : ResetEffect.reverted,
      next,
    );
  }
  final written = write.writtenSettlement!;
  final cur = currentSettlement;
  if (cur == null ||
      cur.roomId != written.roomId ||
      cur.updatedAt != written.updatedAt ||
      settlementVersionHash(cur) != settlementVersionHash(written)) {
    return null;
  }
  final clock = nextLwwClock(cur.updatedAt, now: now);
  final before = write.beforeSettlement;
  if (before == null || before.deleted) {
    if (cur.deleted) return null;
    return ResetChange.settlement(
      ResetEffect.removed,
      resetSettlementVersion(cur, clock, deleted: true, origin: cur),
    );
  }
  final next = resetSettlementVersion(
    before,
    clock,
    deleted: false,
    origin: cur,
  );
  if (settlementProblem(next) != null) return null;
  return ResetChange.settlement(
    cur.deleted ? ResetEffect.restored : ResetEffect.reverted,
    next,
  );
}

/// Undoes [UndoableWrite]s of the current account's ledger (G67).
///
/// Everything is captured when [undo] starts (G19): the write context and a
/// [GroupResetService] on the same DB, so the undo goes through the reset's
/// sign → store (source `revert`) → relay path. No group poke: one record is
/// always relayed live (≤ [kResetLiveRelayMax]); anti-entropy repairs a lost
/// relay like for any edit.
class RecordUndoer {
  RecordUndoer(this._ref);
  final Ref _ref;

  Future<UndoOutcome> undo(UndoableWrite write) async {
    final w = LedgerWriteContext(_ref);
    final service = GroupResetService(
      write: w,
      groups: GroupsDao(w.db),
      history: HistoryDao(w.db),
      poke: (_) {},
    );
    if (w.db.isClosed) return UndoOutcome.changedMeanwhile;
    final change = write.kind == RecordKind.expense
        ? planUndo(
            write,
            currentExpense: await w.expenses.getExpenseById(write.recordId),
          )
        : planUndo(
            write,
            currentSettlement: await w.expenses.getSettlementById(
              write.recordId,
            ),
          );
    if (change == null || w.db.isClosed) return UndoOutcome.changedMeanwhile;
    final written = await service.apply(
      GroupResetPlan(groupId: write.groupId, beforeId: 0, changes: [change]),
    );
    return written > 0 ? UndoOutcome.undone : UndoOutcome.changedMeanwhile;
  }
}

/// The [RecordUndoer] of the current account (reads the DB per undo).
final recordUndoerProvider = Provider<RecordUndoer>(RecordUndoer.new);
