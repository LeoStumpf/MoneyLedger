import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../../models/expense_model.dart';

part 'expenses_dao.g.dart';

@DriftAccessor(tables: [Expenses, Settlements])
class ExpensesDao extends DatabaseAccessor<AppDatabase>
    with _$ExpensesDaoMixin {
  ExpensesDao(super.db);

  Stream<List<ExpenseModel>> watchExpensesForRoom(String roomId) =>
      (select(expenses)
            ..where((t) => t.roomId.equals(roomId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch()
          .map((rows) => rows.map(_toExpenseModel).toList());

  Stream<List<SettlementModel>> watchSettlementsForRoom(String roomId) =>
      (select(settlements)
            ..where((t) => t.roomId.equals(roomId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch()
          .map((rows) => rows.map(_toSettlementModel).toList());

  Future<void> upsertExpense(ExpensesCompanion expense) =>
      into(expenses).insertOnConflictUpdate(expense);

  Future<void> upsertSettlement(SettlementsCompanion settlement) =>
      into(settlements).insertOnConflictUpdate(settlement);

  Future<List<ExpenseModel>> getExpensesForRoom(String roomId) =>
      (select(expenses)..where((t) => t.roomId.equals(roomId)))
          .get()
          .then((rows) => rows.map(_toExpenseModel).toList());

  Future<List<SettlementModel>> getSettlementsForRoom(String roomId) =>
      (select(settlements)..where((t) => t.roomId.equals(roomId)))
          .get()
          .then((rows) => rows.map(_toSettlementModel).toList());

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
      );
}
