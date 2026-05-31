import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/models/expense_model.dart';

ExpenseModel _expense({
  required String id,
  required String paidBy,
  required int amountCents,
  required String splitsJson,
}) =>
    ExpenseModel(
      id: id,
      roomId: 'r1',
      description: 'Test',
      amountCents: amountCents,
      currency: 'EUR',
      paidBy: paidBy,
      splitsJson: splitsJson,
      createdAt: 0,
    );

SettlementModel _settlement({
  required String id,
  required String fromUser,
  required String toUser,
  required int amountCents,
}) =>
    SettlementModel(
      id: id,
      roomId: 'r1',
      amountCents: amountCents,
      currency: 'EUR',
      fromUser: fromUser,
      toUser: toUser,
      createdAt: 0,
    );

void main() {
  group('calculateDebts', () {
    test('equal split between two people', () {
      final expenses = [
        _expense(
          id: '1',
          paidBy: '@alice:m.org',
          amountCents: 2000,
          splitsJson: '{"@alice:m.org": 1000, "@bob:m.org": 1000}',
        ),
      ];
      final debts = calculateDebts(expenses, []);
      expect(debts.length, 1);
      expect(debts.first.from, '@bob:m.org');
      expect(debts.first.to, '@alice:m.org');
      expect(debts.first.cents, 1000);
    });

    test('all settled returns empty', () {
      final expenses = [
        _expense(
          id: '1',
          paidBy: '@alice:m.org',
          amountCents: 2000,
          splitsJson: '{"@alice:m.org": 1000, "@bob:m.org": 1000}',
        ),
      ];
      final settlements = [
        _settlement(
          id: 's1',
          fromUser: '@bob:m.org',
          toUser: '@alice:m.org',
          amountCents: 1000,
        ),
      ];
      final debts = calculateDebts(expenses, settlements);
      expect(debts, isEmpty);
    });

    test('three-way debt simplification', () {
      // Alice pays 30 (split 3 ways: alice 10, bob 10, carol 10)
      // Bob pays 30 (split 3 ways: alice 10, bob 10, carol 10)
      // Net: carol owes alice 10, carol owes bob 10
      final expenses = [
        _expense(
          id: '1',
          paidBy: '@alice:m.org',
          amountCents: 3000,
          splitsJson:
              '{"@alice:m.org": 1000, "@bob:m.org": 1000, "@carol:m.org": 1000}',
        ),
        _expense(
          id: '2',
          paidBy: '@bob:m.org',
          amountCents: 3000,
          splitsJson:
              '{"@alice:m.org": 1000, "@bob:m.org": 1000, "@carol:m.org": 1000}',
        ),
      ];
      final debts = calculateDebts(expenses, []);
      final totalOwed = debts.fold<int>(0, (sum, d) => sum + d.cents);
      expect(totalOwed, 2000);
      for (final d in debts) {
        expect(d.from, '@carol:m.org');
      }
    });
  });
}
