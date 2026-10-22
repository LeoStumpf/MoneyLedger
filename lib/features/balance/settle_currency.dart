import 'dart:convert';

import '../../core/sync/record_validation.dart';
import '../../models/exchange_rates.dart';
import '../../models/expense_model.dart';
import '../expenses/split_calculator.dart';

/// G73 (U18): the ledger as the balances see it. With "settle up in
/// {base}" on ([ExchangeRates.settle]), every expense and payment in a
/// currency that has a rate is **converted into the base currency** (a copy
/// for the calculation only — nothing is stored): the amount at the fixed
/// rate (exact integer math, [convertCents]), the split re-spread over the
/// same people in proportion to their shares (largest remainder, so it
/// still sums to the converted amount). A record whose converted amount
/// would exceed `kMaxAmountCents` (huge amount × huge rate) stays as it is
/// — keeps the balance math in the safe integer range (also on the web).
/// Currencies without a rate, and the
/// whole ledger when settling in one currency is off or no rates are set,
/// stay as they are — balances are then per currency as before (G16).
({List<ExpenseModel> expenses, List<SettlementModel> settlements})
ledgerForSettling(
  List<ExpenseModel> expenses,
  List<SettlementModel> settlements,
  ExchangeRates? fx,
) {
  if (fx == null || !fx.settle || exchangeRatesProblem(fx) != null) {
    return (expenses: expenses, settlements: settlements);
  }
  return (
    expenses: [for (final e in expenses) _convertExpense(e, fx)],
    settlements: [for (final s in settlements) _convertSettlement(s, fx)],
  );
}

/// Whether [fx] converts something of [currencies] when settling (the
/// balance page's "converted at fixed rates" note).
bool settlesConverted(ExchangeRates? fx, Iterable<String> currencies) =>
    fx != null &&
    fx.settle &&
    exchangeRatesProblem(fx) == null &&
    currencies.any(fx.rates.containsKey);

ExpenseModel _convertExpense(ExpenseModel e, ExchangeRates fx) {
  final rate = fx.rates[e.currency];
  if (rate == null) return e;
  final split = tryParseSplit(e.splitsJson);
  if (split == null) return e; // malformed — the balances skip it anyway
  final amount = convertCents(e.amountCents, rate);
  // A huge amount at a huge rate would leave the safe integer range of the
  // balance math (and of JS numbers on the web) — it stays unconverted.
  if (amount > kMaxAmountCents) return e;
  final converted = distributeByWeights(amount, split);
  return ExpenseModel(
    id: e.id,
    roomId: e.roomId,
    description: e.description,
    amountCents: amount,
    currency: fx.base,
    paidBy: e.paidBy,
    splitsJson: jsonEncode(converted),
    createdAt: e.createdAt,
    updatedAt: e.updatedAt,
    deleted: e.deleted,
    category: e.category,
    note: e.note,
    date: e.date,
  );
}

SettlementModel _convertSettlement(SettlementModel s, ExchangeRates fx) {
  final rate = fx.rates[s.currency];
  if (rate == null) return s;
  final amount = convertCents(s.amountCents, rate);
  if (amount > kMaxAmountCents) return s; // see _convertExpense
  return SettlementModel(
    id: s.id,
    roomId: s.roomId,
    amountCents: amount,
    currency: fx.base,
    fromUser: s.fromUser,
    toUser: s.toUser,
    createdAt: s.createdAt,
    updatedAt: s.updatedAt,
    deleted: s.deleted,
    date: s.date,
  );
}
