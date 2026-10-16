/// G18 review (findings 5, 6, 12): the content rules every expense / payment
/// must satisfy, and balance code that never throws on a malformed split.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/sync/record_validation.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/models/expense_model.dart';

ExpenseModel _e(int amount, String split, {String paidBy = 'a'}) =>
    ExpenseModel(
      id: 'e',
      roomId: 'g',
      description: 'x',
      amountCents: amount,
      currency: 'EUR',
      paidBy: paidBy,
      splitsJson: split,
      createdAt: 1,
      updatedAt: 1,
    );

SettlementModel _s(int amount, String from, String to) => SettlementModel(
  id: 's',
  roomId: 'g',
  amountCents: amount,
  currency: 'EUR',
  fromUser: from,
  toUser: to,
  createdAt: 1,
  updatedAt: 1,
);

void main() {
  test('amount bounds: 1 cent … 10^13 cents', () {
    expect(isValidAmountCents(0), isFalse);
    expect(isValidAmountCents(-5), isFalse);
    expect(isValidAmountCents(1), isTrue);
    expect(isValidAmountCents(kMaxAmountCents), isTrue);
    expect(isValidAmountCents(kMaxAmountCents + 1), isFalse);
  });

  test('tryParseSplit accepts only {non-empty string: int ≥ 0}', () {
    expect(tryParseSplit('{"a":1,"b":0}'), {'a': 1, 'b': 0});
    for (final bad in [
      '[1]',
      '{"a":1.5}',
      '{"a":"1"}',
      '{"a":-1}',
      '{"":1}',
      'not json',
      '{"a":null}',
    ]) {
      expect(tryParseSplit(bad), isNull, reason: bad);
    }
  });

  test('expenseProblem', () {
    expect(expenseProblem(_e(100, '{"a":60,"b":40}')), isNull);
    expect(expenseProblem(_e(0, '{}')), isNotNull);
    expect(expenseProblem(_e(-100, '{"a":-100}')), isNotNull);
    expect(expenseProblem(_e(100, '{"a":99}')), contains('sums'));
    expect(expenseProblem(_e(100, '{}')), isNotNull);
    expect(expenseProblem(_e(100, '{"a":100}', paidBy: '')), isNotNull);
    expect(
      expenseProblem(_e(kMaxAmountCents + 1, '{"a":${kMaxAmountCents + 1}}')),
      isNotNull,
    );
  });

  test('settlementProblem', () {
    expect(settlementProblem(_s(100, 'a', 'b')), isNull);
    expect(settlementProblem(_s(0, 'a', 'b')), isNotNull);
    expect(settlementProblem(_s(100, 'a', 'a')), isNotNull);
    expect(settlementProblem(_s(100, '', 'b')), isNotNull);
  });

  test('balances skip a malformed split instead of throwing', () {
    final rows = [
      _e(100, '{"a":50,"b":50}'),
      _e(100, '{"b":"oops"}'),
      _e(100, '[]'),
      _e(100, 'garbage'),
    ];
    final debts = calculateDebts(rows, const []);
    expect(debts.single.cents, 50);
    expect(splitsOf(rows[1]), isEmpty);
    expect(expenseEffectFor(rows[3], 'b').involved, isFalse);
  });
}
