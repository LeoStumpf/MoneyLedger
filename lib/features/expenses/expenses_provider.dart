import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/matrix/matrix_service.dart';
import '../../models/expense_model.dart';
import '../auth/auth_provider.dart';

part 'expenses_provider.g.dart';

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) => AppDatabase();

@Riverpod(keepAlive: true)
ExpensesDao expensesDao(Ref ref) =>
    ExpensesDao(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
GroupsDao groupsDao(Ref ref) => GroupsDao(ref.watch(appDatabaseProvider));

@riverpod
Stream<List<ExpenseModel>> expensesForRoom(Ref ref, String roomId) {
  return ref.watch(expensesDaoProvider).watchExpensesForRoom(roomId);
}

@riverpod
Stream<List<SettlementModel>> settlementsForRoom(Ref ref, String roomId) {
  return ref.watch(expensesDaoProvider).watchSettlementsForRoom(roomId);
}

@riverpod
class ExpenseAdder extends _$ExpenseAdder {
  @override
  FutureOr<void> build() {}

  Future<void> addExpense({
    required String roomId,
    required String description,
    required int amountCents,
    required String currency,
    required String paidBy,
    required Map<String, int> splits,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = await ref.read(matrixClientProvider.future);
      final id = const Uuid().v7();
      await client.sendExpenseEvent(roomId, {
        'id': id,
        'description': description,
        'amount': amountCents,
        'currency': currency,
        'paid_by': paidBy,
        'split': splits,
      });
    });
  }

  Future<void> addSettlement({
    required String roomId,
    required int amountCents,
    required String currency,
    required String fromUser,
    required String toUser,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = await ref.read(matrixClientProvider.future);
      final id = const Uuid().v7();
      await client.sendSettlementEvent(roomId, {
        'id': id,
        'amount': amountCents,
        'currency': currency,
        'from': fromUser,
        'to': toUser,
      });
    });
  }
}
