import 'dart:convert';
import '../../models/expense_model.dart';

// Returns a simplified list of who owes whom and how much (in cents).
List<DebtEntry> calculateDebts(
  List<ExpenseModel> expenses,
  List<SettlementModel> settlements,
) {
  // balance[person] = positive means creditor, negative means debtor
  final balance = <String, int>{};

  for (final e in expenses) {
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
    // s.fromUser paid s.toUser → fromUser's debt decreases, toUser's credit decreases
    balance[s.fromUser] = (balance[s.fromUser] ?? 0) + s.amountCents;
    balance[s.toUser] = (balance[s.toUser] ?? 0) - s.amountCents;
  }

  // Greedy debt simplification: match biggest creditor against biggest debtor
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
    debts.add(DebtEntry(from: d.name, to: c.name, cents: amount));
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
  const DebtEntry({required this.from, required this.to, required this.cents});
}
