import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../../models/expense_model.dart';
import '../../../models/record_signature.dart';

part 'expenses_dao.g.dart';

@DriftAccessor(tables: [Expenses, Settlements])
class ExpensesDao extends DatabaseAccessor<AppDatabase>
    with _$ExpensesDaoMixin {
  ExpensesDao(super.db);

  Stream<List<ExpenseModel>> watchExpensesForRoom(String roomId) =>
      (select(expenses)
            ..where((t) => t.roomId.equals(roomId) & t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch()
          .map((rows) => rows.map(_toExpenseModel).toList());

  Stream<List<SettlementModel>> watchSettlementsForRoom(String roomId) =>
      (select(settlements)
            ..where((t) => t.roomId.equals(roomId) & t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch()
          .map((rows) => rows.map(_toSettlementModel).toList());

  /// Last-writer-wins upsert: writes only when no existing row has a newer
  /// [Expenses.updatedAt]. The companion must set `updatedAt`. Lets concurrent
  /// edits/deletes of the same expense converge deterministically across
  /// devices (same pattern as [MembersDao.upsertMemberLww]).
  Future<void> upsertExpenseLww(ExpensesCompanion expense) =>
      into(expenses).insert(
        expense,
        onConflict: DoUpdate(
          (_) => expense,
          where: (old) =>
              old.updatedAt.isSmallerOrEqualValue(expense.updatedAt.value),
        ),
      );

  Future<void> upsertSettlementLww(SettlementsCompanion settlement) =>
      into(settlements).insert(
        settlement,
        onConflict: DoUpdate(
          (_) => settlement,
          where: (old) =>
              old.updatedAt.isSmallerOrEqualValue(settlement.updatedAt.value),
        ),
      );

  Future<List<ExpenseModel>> getExpensesForRoom(String roomId) =>
      (select(expenses)
            ..where((t) => t.roomId.equals(roomId) & t.deleted.equals(false)))
          .get()
          .then((rows) => rows.map(_toExpenseModel).toList());

  Future<List<SettlementModel>> getSettlementsForRoom(String roomId) =>
      (select(settlements)
            ..where((t) => t.roomId.equals(roomId) & t.deleted.equals(false)))
          .get()
          .then((rows) => rows.map(_toSettlementModel).toList());

  /// Single record incl. tombstones — for edit/delete (the full current row is
  /// needed to build a whole-record LWW payload).
  Future<ExpenseModel?> getExpenseById(String id) =>
      (select(expenses)..where((t) => t.id.equals(id))).getSingleOrNull().then(
        (row) => row == null ? null : _toExpenseModel(row),
      );

  Future<SettlementModel?> getSettlementById(String id) =>
      (select(settlements)..where((t) => t.id.equals(id)))
          .getSingleOrNull()
          .then((row) => row == null ? null : _toSettlementModel(row));

  /// All records including tombstones — for digest/bootstrap building, where
  /// deletions must propagate so peers never resurrect them.
  Future<List<ExpenseModel>> getAllExpensesForGroup(String groupId) =>
      (select(expenses)..where((t) => t.roomId.equals(groupId))).get().then(
        (rows) => rows.map(_toExpenseModel).toList(),
      );

  Future<List<SettlementModel>> getAllSettlementsForGroup(String groupId) =>
      (select(settlements)..where((t) => t.roomId.equals(groupId))).get().then(
        (rows) => rows.map(_toSettlementModel).toList(),
      );

  /// All records including tombstones, reactively — used by the sync-status UI
  /// to track the group's newest `updatedAt` (a delete bumps it too).
  Stream<List<ExpenseModel>> watchAllExpensesForGroup(String groupId) =>
      (select(expenses)..where((t) => t.roomId.equals(groupId))).watch().map(
        (rows) => rows.map(_toExpenseModel).toList(),
      );

  Stream<List<SettlementModel>> watchAllSettlementsForGroup(String groupId) =>
      (select(settlements)..where((t) => t.roomId.equals(groupId))).watch().map(
        (rows) => rows.map(_toSettlementModel).toList(),
      );

  static ExpenseModel _toExpenseModel(Expense e) => ExpenseModel(
    id: e.id,
    roomId: e.roomId,
    matrixEventId: e.matrixEventId,
    description: e.description,
    amountCents: e.amountCents,
    currency: e.currency,
    paidBy: e.paidBy,
    splitsJson: e.splitsJson,
    createdAt: e.createdAt,
    updatedAt: e.updatedAt,
    deleted: e.deleted,
    sig: RecordSignature.decode(e.sig),
    origin: RecordSignature.decode(e.origin),
    pendingSign: e.pendingSign,
  );

  static SettlementModel _toSettlementModel(Settlement s) => SettlementModel(
    id: s.id,
    roomId: s.roomId,
    matrixEventId: s.matrixEventId,
    amountCents: s.amountCents,
    currency: s.currency,
    fromUser: s.fromUser,
    toUser: s.toUser,
    createdAt: s.createdAt,
    updatedAt: s.updatedAt,
    deleted: s.deleted,
    sig: RecordSignature.decode(s.sig),
    origin: RecordSignature.decode(s.origin),
    pendingSign: s.pendingSign,
  );
}

/// A fully-populated companion for an LWW upsert of [e] (G6 fields included).
ExpensesCompanion expenseCompanion(ExpenseModel e) => ExpensesCompanion(
  id: Value(e.id),
  roomId: Value(e.roomId),
  description: Value(e.description),
  amountCents: Value(e.amountCents),
  currency: Value(e.currency),
  paidBy: Value(e.paidBy),
  splitsJson: Value(e.splitsJson),
  createdAt: Value(e.createdAt),
  updatedAt: Value(e.updatedAt),
  deleted: Value(e.deleted),
  sig: Value(e.sig?.encode()),
  origin: Value(e.origin?.encode()),
  pendingSign: Value(e.pendingSign),
);

/// A fully-populated companion for an LWW upsert of [s] (G6 fields included).
SettlementsCompanion settlementCompanion(SettlementModel s) =>
    SettlementsCompanion(
      id: Value(s.id),
      roomId: Value(s.roomId),
      amountCents: Value(s.amountCents),
      currency: Value(s.currency),
      fromUser: Value(s.fromUser),
      toUser: Value(s.toUser),
      createdAt: Value(s.createdAt),
      updatedAt: Value(s.updatedAt),
      deleted: Value(s.deleted),
      sig: Value(s.sig?.encode()),
      origin: Value(s.origin?.encode()),
      pendingSign: Value(s.pendingSign),
    );
