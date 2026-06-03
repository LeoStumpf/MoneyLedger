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
  // currency -> (person -> balance cents); positive = creditor, negative = debtor
  final byCurrency = <String, Map<String, int>>{};
  Map<String, int> ledgerFor(String currency) =>
      byCurrency.putIfAbsent(currency, () => <String, int>{});

  for (final e in expenses) {
    final balance = ledgerFor(e.currency);
    final splits = (jsonDecode(e.splitsJson) as Map).cast<String, dynamic>();
    for (final entry in splits.entries) {
      final debtor = entry.key;
      final share = (entry.value as num).toInt();
      if (debtor == e.paidBy) continue;
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

  final debts = <DebtEntry>[];
  for (final currency in byCurrency.keys.toList()..sort()) {
    debts.addAll(_simplify(byCurrency[currency]!, currency));
  }
  return debts;
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
