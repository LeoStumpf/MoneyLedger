/// G49: the optional expense `date` (ISO `YYYY-MM-DD`) on the wire — part of
/// the signed content and the G27 version hash only when set (so every
/// pre-G49 expense signature and hash stays valid), its helpers and its
/// content rules (`expenseProblem`).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/hmac_record_crypto.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_validation.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/expense_date.dart';
import 'package:money_ledger/models/expense_model.dart';

const alice = '@alice:x.org';
const bob = '@bob:x.org';

ExpenseModel expense({String? date, int createdAt = 1760000000000}) =>
    ExpenseModel(
      id: 'e1',
      roomId: 'g1',
      description: 'Dinner',
      amountCents: 4200,
      currency: 'EUR',
      paidBy: alice,
      splitsJson: jsonEncode({alice: 2100, bob: 2100}),
      createdAt: createdAt,
      updatedAt: 1760000050000,
      date: date,
    );

Map<String, dynamic> overTheWire(Map<String, dynamic> payload) =>
    jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;

void main() {
  final keys = HmacKeyRegistry();
  final crypto = keys.deviceCrypto(alice, 'AAAA');

  test('an undated expense keeps the pre-G49 body, payload and hash', () {
    expect(expenseContent(expense()).containsKey('date'), isFalse);
    expect(expensePayload(expense()).containsKey('date'), isFalse);
    // Golden: SHA-256 of the pre-G49 canonical body
    // {"amount":4200,"created_at":1760000000000,"currency":"EUR",
    //  "deleted":false,"description":"Dinner","group":"g1","id":"e1",
    //  "paid_by":"@alice:x.org","split":{"@alice:x.org":2100,
    //  "@bob:x.org":2100},"t":"com.moneyledger.expense",
    //  "updated_at":1760000050000} (computed outside the app).
    expect(
      computeExpenseVersionHash(expense()),
      'cc7640279c250f3ba65d19c2df1936c0c0b0f9e1c2525f9b1917397cd104e83c',
    );
    expect(
      computeExpenseVersionHash(expense(date: '2025-10-05')),
      isNot(computeExpenseVersionHash(expense())),
    );
    // "" is no date.
    expect(expense(date: '').date, isNull);
  });

  test('round trip: sign → wire → parse → verifies, same hash', () async {
    final signed = await signExpense(
      crypto,
      expense(date: '2025-10-05'),
      creating: true,
    );
    final payload = overTheWire(expensePayload(signed));
    expect(payload['date'], '2025-10-05');
    final parsed = expenseFromPayload(payload)!;
    expect(parsed.date, '2025-10-05');
    expect(
      signatureMatches(
        crypto,
        expenseBody(parsed, signerOf(parsed.sig!)),
        parsed.sig!,
      ),
      isTrue,
    );
    // The creation statement doesn't cover the date: it stays valid when an
    // editor changes the day.
    expect(
      originBody(
        RecordKind.expense,
        'e1',
        'g1',
        parsed.createdAt,
        signerOf(parsed.origin!),
      ).containsKey('date'),
      isFalse,
    );
    expect(
      computeExpenseVersionHash(parsed),
      computeExpenseVersionHash(signed),
    );
  });

  test('a pre-G49 build (body without the date) cannot verify a dated '
      'version — the documented mixed-version caveat', () async {
    final signed = await signExpense(crypto, expense(date: '2025-10-05'));
    final oldBody = Map.of(expenseBody(signed, signerOf(signed.sig!)))
      ..remove('date');
    expect(signatureMatches(crypto, oldBody, signed.sig!), isFalse);
  });

  group('helpers', () {
    test('parseExpenseDate accepts only real calendar days', () {
      expect(parseExpenseDate('2026-02-28'), DateTime(2026, 2, 28));
      expect(parseExpenseDate('2024-02-29'), DateTime(2024, 2, 29));
      expect(parseExpenseDate('2026-02-30'), isNull);
      expect(parseExpenseDate('2026-2-3'), isNull);
      expect(parseExpenseDate('2026-10-17T12:00:00'), isNull);
      expect(parseExpenseDate(null), isNull);
      expect(expenseDateOf(DateTime(2026, 3, 4, 23, 59)), '2026-03-04');
    });

    test('storedExpenseDate: today → none, another day → ISO', () {
      final created = DateTime(2026, 10, 17, 9, 30).millisecondsSinceEpoch;
      expect(storedExpenseDate(DateTime(2026, 10, 17), created), isNull);
      expect(
        storedExpenseDate(DateTime(2026, 10, 16, 18), created),
        '2026-10-16',
      );
    });

    test('displayDay = date ?? the local day of created_at', () {
      final created = DateTime(2026, 10, 17, 9, 30).millisecondsSinceEpoch;
      expect(expense(createdAt: created).displayDay, DateTime(2026, 10, 17));
      expect(
        expense(createdAt: created, date: '2026-10-01').displayDay,
        DateTime(2026, 10, 1),
      );
      // A malformed stored date falls back to the creation day.
      expect(
        expense(createdAt: created, date: 'soon').displayDay,
        DateTime(2026, 10, 17),
      );
    });
  });

  group('content rules', () {
    final now = DateTime(2026, 10, 17, 12);
    test('valid dates pass', () {
      expect(expenseProblem(expense(), now: now), isNull);
      expect(expenseProblem(expense(date: '2026-10-10'), now: now), isNull);
      expect(expenseProblem(expense(date: '2000-01-01'), now: now), isNull);
      expect(expenseProblem(expense(date: '2027-10-17'), now: now), isNull);
    });

    test('malformed, too early or too far ahead → refused', () {
      expect(expenseProblem(expense(date: 'yesterday'), now: now), isNotNull);
      expect(expenseProblem(expense(date: '2026-13-01'), now: now), isNotNull);
      expect(expenseProblem(expense(date: '1999-12-31'), now: now), isNotNull);
      expect(expenseProblem(expense(date: '2028-01-01'), now: now), isNotNull);
    });
  });
}
