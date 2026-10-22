import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../models/exchange_rates.dart';
import '../../models/expense_model.dart';
import '../expenses/expenses_provider.dart';
import '../groups/group_provider.dart';
import 'balance_calculator.dart';
import 'settle_currency.dart';

part 'balance_provider.g.dart';

/// G73: [roomId]'s fixed exchange rates (null = none / group unknown).
@riverpod
ExchangeRates? groupExchangeRates(Ref ref, String roomId) =>
    (ref.watch(ledgerGroupsProvider).value ?? const [])
        .where((g) => g.roomId == roomId)
        .firstOrNull
        ?.exchangeRates;

/// G73: [roomId]'s expenses + payments as the balances see them — converted
/// into the base currency while "settle up in {base}" is on
/// ([ledgerForSettling]), else as stored.
@riverpod
({List<ExpenseModel> expenses, List<SettlementModel> settlements})
settlingLedger(Ref ref, String roomId) => ledgerForSettling(
  ref.watch(expensesForRoomProvider(roomId)).value ?? <ExpenseModel>[],
  ref.watch(settlementsForRoomProvider(roomId)).value ?? <SettlementModel>[],
  ref.watch(groupExchangeRatesProvider(roomId)),
);

@riverpod
List<DebtEntry> balanceForRoom(Ref ref, String roomId) {
  final ledger = ref.watch(settlingLedgerProvider(roomId));
  return calculateDebts(ledger.expenses, ledger.settlements);
}
