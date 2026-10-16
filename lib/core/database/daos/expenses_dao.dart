import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../../models/expense_model.dart';
import '../../../models/record_signature.dart';
import '../../sync/record_version.dart';

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

  /// Last-writer-wins upsert: writes unless the stored row is a **newer
  /// version** — a higher [Expenses.updatedAt], or the same clock with a
  /// higher content hash (G27 tie-break, see `record_version.dart`). The same
  /// version is re-written (idempotent; lets `pendingSign` → signed land at
  /// the same clock). Read + write run in one transaction, so concurrent
  /// inbound versions resolve deterministically. The companion must set
  /// `id` and `updatedAt`.
  Future<void> upsertExpenseLww(ExpensesCompanion expense) =>
      transaction(() async {
        final old = await (select(
          expenses,
        )..where((t) => t.id.equals(expense.id.value))).getSingleOrNull();
        if (old != null &&
            compareVersions(
                  expenseVersion(_expenseFromCompanion(expense)),
                  expenseVersion(_toExpenseModel(old)),
                ) <
                0) {
          return;
        }
        await into(expenses).insertOnConflictUpdate(expense);
      });

  Future<void> upsertSettlementLww(SettlementsCompanion settlement) =>
      transaction(() async {
        final old = await (select(
          settlements,
        )..where((t) => t.id.equals(settlement.id.value))).getSingleOrNull();
        if (old != null &&
            compareVersions(
                  settlementVersion(_settlementFromCompanion(settlement)),
                  settlementVersion(_toSettlementModel(old)),
                ) <
                0) {
          return;
        }
        await into(settlements).insertOnConflictUpdate(settlement);
      });

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
    category: e.category,
    note: e.note,
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
  category: Value(e.category),
  note: Value(e.note),
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

T _v<T>(Value<T> v, T fallback) => v.present ? v.value : fallback;

/// The content fields of a (possibly partial) companion as a model — only
/// what the G27 version hash covers.
ExpenseModel _expenseFromCompanion(ExpensesCompanion c) => ExpenseModel(
  id: c.id.value,
  roomId: _v(c.roomId, ''),
  description: _v(c.description, ''),
  amountCents: _v(c.amountCents, 0),
  currency: _v(c.currency, 'EUR'),
  paidBy: _v(c.paidBy, ''),
  splitsJson: _v(c.splitsJson, '{}'),
  createdAt: _v(c.createdAt, 0),
  updatedAt: c.updatedAt.value,
  deleted: _v(c.deleted, false),
  category: _v(c.category, null),
  note: _v(c.note, null),
);

SettlementModel _settlementFromCompanion(SettlementsCompanion c) =>
    SettlementModel(
      id: c.id.value,
      roomId: _v(c.roomId, ''),
      amountCents: _v(c.amountCents, 0),
      currency: _v(c.currency, 'EUR'),
      fromUser: _v(c.fromUser, ''),
      toUser: _v(c.toUser, ''),
      createdAt: _v(c.createdAt, 0),
      updatedAt: c.updatedAt.value,
      deleted: _v(c.deleted, false),
    );
