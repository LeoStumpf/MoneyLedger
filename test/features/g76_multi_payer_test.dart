/// G76: several payers in the pure ledger logic — balances, "you lent /
/// borrowed", the overview, settling in one currency, search / filter, the
/// payer line and the CSV (round trip; a pre-G76 parser sees an empty
/// `Paid By`).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/sync/record_validation.dart';
import 'package:money_ledger/features/backup/ledger_csv.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/group_stats.dart';
import 'package:money_ledger/features/balance/settle_currency.dart';
import 'package:money_ledger/features/expenses/expense_filter.dart';
import 'package:money_ledger/features/expenses/payer_line.dart';
import 'package:money_ledger/models/exchange_rates.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/expense_payers.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/l10n.dart';

const anna = 'p-anna';
const ben = 'p-ben';
const cleo = 'p-cleo';

/// €90 dinner: Anna paid 60, Ben 30; split equally among the three.
ExpenseModel dinner({String currency = 'EUR', String id = 'e1'}) =>
    ExpenseModel(
      id: id,
      roomId: 'g1',
      description: 'Dinner',
      amountCents: 9000,
      currency: currency,
      paidBy: '',
      payersJson: jsonEncode({anna: 6000, ben: 3000}),
      splitsJson: jsonEncode({anna: 3000, ben: 3000, cleo: 3000}),
      createdAt: DateTime(2026, 10, 20, 12).millisecondsSinceEpoch,
      updatedAt: DateTime(2026, 10, 20, 12).millisecondsSinceEpoch,
    );

ExpenseModel taxi() => ExpenseModel(
  id: 'e2',
  roomId: 'g1',
  description: 'Taxi',
  amountCents: 3000,
  currency: 'EUR',
  paidBy: cleo,
  splitsJson: jsonEncode({anna: 1000, ben: 1000, cleo: 1000}),
  createdAt: DateTime(2026, 10, 20, 13).millisecondsSinceEpoch,
  updatedAt: DateTime(2026, 10, 20, 13).millisecondsSinceEpoch,
);

void main() {
  test('balances credit every payer what they paid', () {
    expect(netBalances([dinner()], const [])['EUR'], {
      anna: 3000,
      ben: 0,
      cleo: -3000,
    });
    // + the taxi Cleo paid: Anna gets 20 back, Ben and Cleo owe 10 each.
    final debts = calculateDebts([dinner(), taxi()], const []);
    expect(
      {for (final d in debts) d.from: (d.to, d.cents)},
      {ben: (anna, 1000), cleo: (anna, 1000)},
    );
    // Single-payer math unchanged.
    expect(netBalances([taxi()], const [])['EUR'], {
      anna: -1000,
      ben: -1000,
      cleo: 2000,
    });
  });

  test('expenseEffectFor: a partial payer lent / borrowed the difference', () {
    expect(expenseEffectFor(dinner(), anna), (net: 3000, involved: true));
    expect(expenseEffectFor(dinner(), ben), (net: 0, involved: true));
    expect(expenseEffectFor(dinner(), cleo), (net: -3000, involved: true));
    expect(expenseEffectFor(dinner(), 'p-x'), (net: 0, involved: false));
  });

  test('overview: paid per person splits the amount', () {
    final stats = groupStats([dinner()]).single;
    final byId = {for (final p in stats.people) p.id: p};
    expect(stats.total, 9000);
    expect(byId[anna]!.paid, 6000);
    expect(byId[ben]!.paid, 3000);
    expect(byId[cleo]!.paid, 0);
    expect(byId[cleo]!.share, 3000);
  });

  test('settling in one currency converts the payer amounts too', () {
    final fx = ExchangeRates(base: 'EUR', rates: {'CHF': '1.1'}, settle: true);
    final converted = ledgerForSettling(
      [dinner(currency: 'CHF')],
      const [],
      fx,
    ).expenses.single;
    expect(converted.amountCents, 9900);
    expect(paidAmountsOf(converted), {anna: 6600, ben: 3300});
    expect(expenseProblem(converted), isNull);
  });

  test('search finds every payer; "involving me" counts a partial payer', () {
    String nameOf(String id) =>
        {anna: 'Anna', ben: 'Ben', cleo: 'Cleo'}[id] ?? id;
    final onlyPayer = dinner();
    expect(
      expenseMatches(
        onlyPayer,
        const LedgerFilter(query: 'ben'),
        nameOf: nameOf,
        myId: null,
      ),
      isTrue,
    );
    final notInSplit = ExpenseModel(
      id: 'e3',
      roomId: 'g1',
      description: 'Gift',
      amountCents: 2000,
      currency: 'EUR',
      paidBy: '',
      payersJson: jsonEncode({anna: 1000, ben: 1000}),
      splitsJson: jsonEncode({cleo: 2000}),
      createdAt: 1,
      updatedAt: 1,
    );
    expect(
      expenseMatches(
        notInSplit,
        const LedgerFilter(involvingMe: true),
        nameOf: nameOf,
        myId: ben,
      ),
      isTrue,
    );
  });

  test('payer line: one, two (you first), several', () {
    String nameOf(String id) =>
        {anna: 'Anna', ben: 'Ben', cleo: 'Cleo'}[id] ?? id;
    expect(payerLineOf(taxi(), myId: cleo, nameOf: nameOf, l: en), 'You paid');
    expect(
      payerLineOf(dinner(), myId: null, nameOf: nameOf, l: en),
      'Paid by Anna and Ben',
    );
    expect(
      payerLineOf(dinner(), myId: ben, nameOf: nameOf, l: en),
      'Paid by you and Anna',
    );
    expect(
      payerLineOf(dinner(), myId: ben, nameOf: nameOf, l: de),
      'Bezahlt von dir und Anna',
    );
    final three = ExpenseModel(
      id: 'e4',
      roomId: 'g1',
      description: 'Hut',
      amountCents: 300,
      currency: 'EUR',
      paidBy: '',
      payersJson: jsonEncode({anna: 100, ben: 100, cleo: 100}),
      splitsJson: jsonEncode({anna: 300}),
      createdAt: 1,
      updatedAt: 1,
    );
    expect(
      payerLineOf(three, myId: null, nameOf: nameOf, l: en),
      'Paid by 3 people',
    );
    expect(
      payerLineOf(three, myId: null, nameOf: nameOf, l: de),
      'Bezahlt von 3 Personen',
    );
  });

  group('CSV', () {
    const group = GroupModel(roomId: 'g1', name: 'Trip', currency: 'EUR');
    final members = [
      for (final (id, name) in [(anna, 'Anna'), (ben, 'Ben'), (cleo, 'Cleo')])
        MemberModel(
          groupId: 'g1',
          userId: id,
          displayName: name,
          status: 'active',
          updatedAt: 1,
        ),
    ];

    test('without several payers the CSV is unchanged (no Paid: columns)', () {
      final csv = buildGroupCsv(group, members, [taxi()]);
      expect(csv, isNot(contains(csvPaidPrefix)));
    });

    test('round trip: empty Paid By + per-payer columns', () {
      final csv = buildGroupCsv(group, members, [dinner(), taxi()]);
      final lines = csv.split('\r\n');
      expect(
        lines.first,
        endsWith('Created At,Paid: Anna,Paid: Ben,Paid: Cleo'),
      );
      final parsed = parseGroupCsv(csv);
      final dinnerRow = parsed.rows.firstWhere((r) => r.id == 'e1');
      expect(dinnerRow.paidByName, '');
      expect(dinnerRow.payersByName, {'Anna': 6000, 'Ben': 3000});
      final taxiRow = parsed.rows.firstWhere((r) => r.id == 'e2');
      expect(taxiRow.paidByName, 'Cleo');
      expect(taxiRow.payersByName, {'Cleo': 3000});
      // The share columns stay the three people (no Paid: column).
      expect(parsed.participantNames, ['Anna', 'Ben', 'Cleo']);
      expect(dinnerRow.problem, isNull);
    });

    test('a malformed paid cell is a row problem', () {
      final csv = buildGroupCsv(group, members, [
        dinner(),
      ]).replaceFirst('60.00', 'sixty');
      final row = parseGroupCsv(csv).rows.single;
      expect(row.problem, contains('paid "sixty" of Anna'));
    });
  });
}
