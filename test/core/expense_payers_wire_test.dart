/// G76: several payers on the wire — an optional `payers` map plus an
/// **empty** `paid_by`, part of the signed content and the G27 hash only
/// when set (a single-payer expense keeps the pre-G76 body, payload and
/// hash), the content rules, and why a pre-G76 build refuses rather than
/// misreads such a version.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/hmac_record_crypto.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_validation.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/expense_payers.dart';

const alice = '@alice:x.org';
const bob = '@bob:x.org';

ExpenseModel expense({String paidBy = alice, String? payersJson}) =>
    ExpenseModel(
      id: 'e1',
      roomId: 'g1',
      description: 'Dinner',
      amountCents: 4200,
      currency: 'EUR',
      paidBy: paidBy,
      payersJson: payersJson,
      splitsJson: jsonEncode({alice: 2100, bob: 2100}),
      createdAt: 1760000000000,
      updatedAt: 1760000050000,
    );

ExpenseModel twoPayers() =>
    expense(paidBy: '', payersJson: jsonEncode({alice: 3000, bob: 1200}));

Map<String, dynamic> overTheWire(Map<String, dynamic> payload) =>
    jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;

void main() {
  final keys = HmacKeyRegistry();
  final crypto = keys.deviceCrypto(alice, 'AAAA');

  test('a single-payer expense keeps the pre-G76 body, payload and hash', () {
    expect(expenseContent(expense()).containsKey('payers'), isFalse);
    expect(expensePayload(expense()).containsKey('payers'), isFalse);
    // Same golden as G49's (`expense_date_wire_test.dart`): the pre-G76
    // canonical body.
    expect(
      computeExpenseVersionHash(expense()),
      'cc7640279c250f3ba65d19c2df1936c0c0b0f9e1c2525f9b1917397cd104e83c',
    );
    expect(
      computeExpenseVersionHash(twoPayers()),
      isNot(computeExpenseVersionHash(expense())),
    );
  });

  test('round trip: sign → wire → parse → verifies, same hash', () async {
    final signed = await signExpense(crypto, twoPayers(), creating: true);
    final payload = overTheWire(expensePayload(signed));
    expect(payload['paid_by'], '');
    expect(payload['payers'], {alice: 3000, bob: 1200});
    final parsed = expenseFromPayload(payload)!;
    expect(paidAmountsOf(parsed), {alice: 3000, bob: 1200});
    expect(expenseProblem(parsed), isNull);
    expect(
      signatureMatches(
        crypto,
        expenseBody(parsed, signerOf(parsed.sig!)),
        parsed.sig!,
      ),
      isTrue,
    );
    expect(
      computeExpenseVersionHash(parsed),
      computeExpenseVersionHash(signed),
    );
    // Key order of the stored JSON doesn't matter (canonical JSON).
    final reordered = expense(
      paidBy: '',
      payersJson: jsonEncode({bob: 1200, alice: 3000}),
    );
    expect(
      computeExpenseVersionHash(reordered),
      computeExpenseVersionHash(twoPayers()),
    );
  });

  test(
    'a pre-G76 build refuses a multi-payer version instead of misreading '
    'it: its parse drops `payers`, the empty `paid_by` is "no payer"',
    () async {
      final signed = await signExpense(crypto, twoPayers(), creating: true);
      final payload = overTheWire(expensePayload(signed))..remove('payers');
      final oldView = expenseFromPayload(payload)!;
      // Content rules run before the signature check (signed and unsigned /
      // link path alike) → `invalid_record`, never a sole payer.
      expect(expenseProblem(oldView), 'no payer');
      // And the signature wouldn't verify either (body without `payers`).
      expect(
        signatureMatches(
          crypto,
          expenseBody(oldView, signerOf(oldView.sig!)),
          signed.sig!,
        ),
        isFalse,
      );
    },
  );

  group('content rules', () {
    String? problem(String paidBy, Object? payers) =>
        expenseProblem(expense(paidBy: paidBy, payersJson: jsonEncode(payers)));

    test('valid payers pass', () {
      expect(problem('', {alice: 3000, bob: 1200}), isNull);
      expect(problem('', {alice: 4199, bob: 1}), isNull);
    });

    test('refused: both shapes, one payer, zero, wrong sum, malformed', () {
      expect(problem(alice, {alice: 3000, bob: 1200}), 'paid_by and payers');
      expect(problem('', {alice: 4200}), '1 payers');
      expect(problem('', {alice: 4200, bob: 0}), 'payer amount 0');
      expect(problem('', {alice: 4300, bob: -100}), 'payer amount -100');
      expect(problem('', {alice: 3000, bob: 1000}), contains('sum to 4000'));
      expect(problem('', [alice, bob]), 'malformed payers');
      expect(problem('', {alice: 21.5, bob: 4178.5}), 'malformed payers');
      expect(problem('', {'': 2100, bob: 2100}), 'malformed payers');
      expect(
        problem('', {
          for (var i = 0; i < 101; i++) '@p$i:x': i == 0 ? 4100 : 1,
        }),
        '101 payers',
      );
    });

    test('no payer at all is still refused', () {
      expect(expenseProblem(expense(paidBy: '')), 'no payer');
    });
  });

  group('helpers', () {
    test('paidAmountsOf: one payer = the whole amount', () {
      expect(paidAmountsOf(expense()), {alice: 4200});
      expect(paidAmountsOf(expense(paidBy: '')), isEmpty);
      expect(paidAmountsOf(twoPayers()), {alice: 3000, bob: 1200});
      expect(
        paidAmountsOf(expense(paidBy: '', payersJson: 'not json')),
        isEmpty,
      );
      expect(hasSeveralPayers(twoPayers()), isTrue);
      expect(paidByParticipant(twoPayers(), bob), isTrue);
      expect(paidByParticipant(expense(), bob), isFalse);
    });

    test('payerFields: zeros dropped, one left = the single-payer shape', () {
      expect(payerFields({alice: 0, bob: 0}), isNull);
      expect(payerFields({alice: 4200, bob: 0}), (
        paidBy: alice,
        payersJson: null,
      ));
      final several = payerFields({alice: 3000, bob: 1200})!;
      expect(several.paidBy, '');
      expect(jsonDecode(several.payersJson!), {alice: 3000, bob: 1200});
    });
  });
}
