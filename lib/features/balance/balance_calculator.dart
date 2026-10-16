import 'dart:convert';
import '../../models/expense_model.dart';

/// Returns a simplified list of who owes whom and how much (in cents).
///
/// Balances are computed **independently per currency** — a group mixing, say,
/// EUR and CHF expenses produces separate debts per currency rather than
/// nonsensically summing across them. Debts are ordered by currency, then by the
/// greedy creditor/debtor matching within each currency.
List<DebtEntry> calculateDebts(
  List<ExpenseModel> expenses,
  List<SettlementModel> settlements,
) {
  final byCurrency = netBalances(expenses, settlements);
  final debts = <DebtEntry>[];
  for (final currency in byCurrency.keys.toList()..sort()) {
    debts.addAll(_simplify(byCurrency[currency]!, currency));
  }
  return debts;
}

/// Every participant's **net balance** per currency (G17):
/// `currency → participant id → cents`, positive = gets money back (a
/// creditor), negative = owes. Participants who net to zero in a currency
/// are kept with 0 (they took part), so callers can tell "settled" from
/// "never involved". Per currency, the values sum to zero.
Map<String, Map<String, int>> netBalances(
  List<ExpenseModel> expenses,
  List<SettlementModel> settlements,
) {
  final byCurrency = <String, Map<String, int>>{};
  Map<String, int> ledgerFor(String currency) =>
      byCurrency.putIfAbsent(currency, () => <String, int>{});

  for (final e in expenses) {
    final balance = ledgerFor(e.currency);
    for (final MapEntry(key: debtor, value: share) in splitsOf(e).entries) {
      if (debtor == e.paidBy) {
        balance[debtor] = balance[debtor] ?? 0;
        continue;
      }
      balance[e.paidBy] = (balance[e.paidBy] ?? 0) + share;
      balance[debtor] = (balance[debtor] ?? 0) - share;
    }
  }

  for (final s in settlements) {
    final balance = ledgerFor(s.currency);
    // s.fromUser paid s.toUser → fromUser's debt decreases, toUser's credit decreases
    balance[s.fromUser] = (balance[s.fromUser] ?? 0) + s.amountCents;
    balance[s.toUser] = (balance[s.toUser] ?? 0) - s.amountCents;
  }
  return byCurrency;
}

/// [participant]'s non-zero net balance per currency (sorted by currency) —
/// e.g. `{EUR: 1250}` = "you are owed €12.50". Empty = settled up.
Map<String, int> netBalanceOf(
  String participant,
  List<ExpenseModel> expenses,
  List<SettlementModel> settlements,
) {
  final all = netBalances(expenses, settlements);
  return {
    for (final currency in all.keys.toList()..sort())
      if ((all[currency]![participant] ?? 0) != 0)
        currency: all[currency]![participant]!,
  };
}

/// The `{participantId: cents}` split of [e].
Map<String, int> splitsOf(ExpenseModel e) =>
    (jsonDecode(e.splitsJson) as Map)
        .map((k, v) => MapEntry(k as String, (v as num).toInt()));

/// What one expense means for [participant] (G17, the "you lent / you
/// borrowed" line): [net] > 0 = lent (others owe them that much from this
/// expense), < 0 = borrowed (their share of someone else's payment).
/// [involved] is false when they neither paid nor share in it.
({int net, bool involved}) expenseEffectFor(
    ExpenseModel e, String? participant) {
  if (participant == null) return (net: 0, involved: false);
  final splits = splitsOf(e);
  final paid = e.paidBy == participant;
  final share = splits[participant] ?? 0;
  if (!paid && !splits.containsKey(participant)) {
    return (net: 0, involved: false);
  }
  return (net: (paid ? e.amountCents : 0) - share, involved: true);
}

/// Greedy debt simplification for a single currency: match the biggest creditor
/// against the biggest debtor until everyone nets to zero.
List<DebtEntry> _simplify(Map<String, int> balance, String currency) {
  final creditors = balance.entries
      .where((e) => e.value > 0)
      .map((e) => _Bal(e.key, e.value))
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));
  final debtors = balance.entries
      .where((e) => e.value < 0)
      .map((e) => _Bal(e.key, e.value.abs()))
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  final debts = <DebtEntry>[];
  var ci = 0;
  var di = 0;

  while (ci < creditors.length && di < debtors.length) {
    final c = creditors[ci];
    final d = debtors[di];
    final amount = c.amount < d.amount ? c.amount : d.amount;
    debts.add(
        DebtEntry(from: d.name, to: c.name, cents: amount, currency: currency));
    c.amount -= amount;
    d.amount -= amount;
    if (c.amount == 0) ci++;
    if (d.amount == 0) di++;
  }

  return debts;
}

class _Bal {
  final String name;
  int amount;
  _Bal(this.name, this.amount);
}

class DebtEntry {
  final String from;
  final String to;
  final int cents;
  final String currency;
  const DebtEntry({
    required this.from,
    required this.to,
    required this.cents,
    required this.currency,
  });
}
