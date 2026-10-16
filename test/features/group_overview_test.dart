/// G17: net balances, the per-expense "you lent / you borrowed" effect, the
/// groups page totals and the balance summary text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/theme/app_theme.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_page.dart'
    show netsFromDebts;
import 'package:money_ledger/features/balance/settle_up.dart';
import 'package:money_ledger/features/groups/group_overview_provider.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/test_providers.dart';

ExpenseModel expense(
  String paidBy,
  int amount,
  Map<String, int> split, {
  String currency = 'EUR',
  int at = 1,
}) => ExpenseModel(
  id: 'e$at',
  roomId: 'g1',
  description: 'x',
  amountCents: amount,
  currency: currency,
  paidBy: paidBy,
  splitsJson:
      '{${split.entries.map((e) => '"${e.key}":${e.value}').join(',')}}',
  createdAt: at,
);

MemberModel member(String id) => MemberModel(
  groupId: 'g1',
  userId: id,
  displayName: id,
  status: 'active',
  updatedAt: 1,
);

void main() {
  group('netBalances / netBalanceOf', () {
    final expenses = [
      expense('a', 3000, {'a': 1000, 'b': 1000, 'c': 1000}),
      expense('b', 1000, {'a': 500, 'b': 500}, currency: 'CHF', at: 2),
    ];
    final settlements = [
      const SettlementModel(
        id: 's',
        roomId: 'g1',
        amountCents: 500,
        currency: 'EUR',
        fromUser: 'c',
        toUser: 'a',
        createdAt: 3,
      ),
    ];

    test('per currency, sums to zero, settlements applied', () {
      final nets = netBalances(expenses, settlements);
      expect(nets['EUR'], {'a': 1500, 'b': -1000, 'c': -500});
      expect(nets['CHF'], {'b': 500, 'a': -500});
    });

    test('netBalanceOf drops zero currencies and sorts by currency', () {
      expect(netBalanceOf('a', expenses, settlements), {
        'CHF': -500,
        'EUR': 1500,
      });
      expect(netBalanceOf('z', expenses, settlements), isEmpty);
    });

    test('nets derived from the simplified debts match', () {
      final debts = calculateDebts(expenses, settlements);
      final fromDebts = netsFromDebts(debts);
      expect(Map.fromEntries(fromDebts['EUR']!), {
        'a': 1500,
        'b': -1000,
        'c': -500,
      });
      // creditors first
      expect(fromDebts['EUR']!.first.key, 'a');
    });
  });

  group('expenseEffectFor', () {
    final e = expense('a', 3000, {'a': 1000, 'b': 2000});
    test('payer lent the others\' shares', () {
      expect(expenseEffectFor(e, 'a'), (net: 2000, involved: true));
    });
    test('a participant borrowed their share', () {
      expect(expenseEffectFor(e, 'b'), (net: -2000, involved: true));
    });
    test('someone else is not involved', () {
      expect(expenseEffectFor(e, 'c'), (net: 0, involved: false));
      expect(expenseEffectFor(e, null), (net: 0, involved: false));
    });
    test('paying only for yourself nets zero', () {
      expect(expenseEffectFor(expense('a', 500, {'a': 500}), 'a'), (
        net: 0,
        involved: true,
      ));
    });
  });

  test('balanceTotals keeps owed and owing apart per currency', () {
    final t = balanceTotals([
      {'EUR': 1250},
      {'EUR': -300, 'CHF': 400},
      {},
      {'EUR': 50},
    ]);
    expect(t.owed, {'CHF': 400, 'EUR': 1300});
    expect(t.owing, {'EUR': 300});
  });

  test('settleUpSuggestion: what I pay, else what I get', () {
    const pay = DebtEntry(from: 'me', to: 'b', cents: 1, currency: 'EUR');
    const get = DebtEntry(from: 'c', to: 'me', cents: 2, currency: 'EUR');
    const other = DebtEntry(from: 'c', to: 'b', cents: 3, currency: 'EUR');
    expect(settleUpSuggestion([other, get, pay], 'me'), pay);
    expect(settleUpSuggestion([other, get], 'me'), get);
    expect(settleUpSuggestion([other], 'me'), isNull);
  });

  group('GroupCard balance text', () {
    Future<void> pump(
      WidgetTester tester,
      GroupOverview o, {
      Locale? locale,
    }) async {
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: GroupCard(
              group: const GroupModel(
                roomId: 'g1',
                name: 'Trip',
                currency: 'EUR',
              ),
              overview: o,
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pump();
    }

    final me = member('me');
    GroupOverview overview(Map<String, int> balance, {int records = 1}) =>
        GroupOverview(
          members: [me, member('Bea'), member('Carl')],
          me: me,
          myBalance: balance,
          lastActivityAt: null,
          recordCount: records,
        );

    testWidgets('owed (green) and owing (red) per currency', (tester) async {
      await pump(tester, overview({'CHF': -300, 'EUR': 1250}));
      expect(find.text('You owe CHF 3.00'), findsOneWidget);
      expect(find.text('You are owed €12.50'), findsOneWidget);
      final owed = tester.widget<Text>(find.text('You are owed €12.50'));
      expect(owed.style?.color, LedgerColors.light.positive);
      final owe = tester.widget<Text>(find.text('You owe CHF 3.00'));
      expect(owe.style?.color, LedgerColors.light.negative);
      expect(find.text('3 members'), findsOneWidget);
      expect(find.text('Trip'), findsOneWidget);
    });

    testWidgets('settled up / no expenses / not a participant', (tester) async {
      await pump(tester, overview({}));
      expect(find.text('Settled up'), findsOneWidget);
      await pump(tester, overview({}, records: 0));
      expect(find.text('No expenses yet'), findsOneWidget);
      await pump(
        tester,
        GroupOverview(
          members: [member('Bea')],
          me: null,
          myBalance: const {},
          lastActivityAt: null,
          recordCount: 3,
        ),
      );
      expect(find.text('Not a participant'), findsOneWidget);
    });

    testWidgets('German', (tester) async {
      await pump(tester, overview({'EUR': -300}), locale: const Locale('de'));
      expect(find.text('Du schuldest 3,00 €'), findsOneWidget);
      expect(find.text('3 Mitglieder'), findsOneWidget);
    });
  });
}
