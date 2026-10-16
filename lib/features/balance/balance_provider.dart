import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../models/expense_model.dart';
import '../expenses/expenses_provider.dart';
import 'balance_calculator.dart';

part 'balance_provider.g.dart';

@riverpod
List<DebtEntry> balanceForRoom(Ref ref, String roomId) {
  final expenses =
      ref.watch(expensesForRoomProvider(roomId)).value ?? <ExpenseModel>[];
  final settlements =
      ref.watch(settlementsForRoomProvider(roomId)).value ??
      <SettlementModel>[];
  return calculateDebts(expenses, settlements);
}
