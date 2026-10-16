/// G16: the optional `category` / `note` expense fields on the wire — part
/// of the signed content and the G27 version hash, absent when unset (so
/// every pre-G16 signature and hash stays valid).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/hmac_record_crypto.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/expense_model.dart';

const alice = '@alice:x.org';

ExpenseModel expense({String? category, String? note}) => ExpenseModel(
  id: 'e1',
  roomId: 'g1',
  description: 'Dinner',
  amountCents: 4200,
  currency: 'EUR',
  paidBy: 'p1',
  splitsJson: '{"p1":2100,"p2":2100}',
  createdAt: 1000,
  updatedAt: 1000,
  category: category,
  note: note,
);

/// Simulates the relay: JSON out and back in.
Map<String, dynamic> overTheWire(Map<String, dynamic> payload) =>
    jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;

void main() {
  final keys = HmacKeyRegistry();
  final crypto = keys.deviceCrypto(alice, 'AAAA');

  test('payload carries category + note only when set', () {
    final plain = expensePayload(expense());
    expect(plain.containsKey('category'), isFalse);
    expect(plain.containsKey('note'), isFalse);
    final rich = expensePayload(expense(category: 'food', note: 'Tip incl.'));
    expect(rich['category'], 'food');
    expect(rich['note'], 'Tip incl.');
  });

  test('signed content without them is exactly the pre-G16 body', () {
    final content = expenseContent(expense());
    expect(content.keys.toSet(), {
      't',
      'id',
      'group',
      'description',
      'amount',
      'currency',
      'paid_by',
      'split',
      'created_at',
      'updated_at',
      'deleted',
    });
    // Pinned G27 hash of a category-less expense: unchanged by G16.
    final before = expenseVersionHash(expense());
    expect(expenseVersionHash(expense(category: null, note: null)), before);
    expect(expenseVersionHash(expense(category: 'food')), isNot(before));
    expect(expenseVersionHash(expense(note: 'x')), isNot(before));
  });

  test('round trip: sign → wire → parse → the signature verifies', () async {
    final signed = await signExpense(
      crypto,
      expense(category: 'transport', note: 'Grüße — ünïcödé 🚕'),
      creating: true,
    );
    final parsed = expenseFromPayload(overTheWire(expensePayload(signed)))!;
    expect(parsed.category, 'transport');
    expect(parsed.note, 'Grüße — ünïcödé 🚕');
    expect(
      signatureMatches(
        crypto,
        expenseBody(parsed, signerOf(parsed.sig!)),
        parsed.sig!,
      ),
      isTrue,
    );
    expect(expenseVersionHash(parsed), expenseVersionHash(signed));
  });

  test(
    'changing / dropping the category or note breaks the signature',
    () async {
      final signed = await signExpense(
        crypto,
        expense(category: 'food', note: 'n'),
        creating: true,
      );
      final payload = overTheWire(expensePayload(signed));
      for (final tamper in <void Function(Map<String, dynamic>)>[
        (p) => p['category'] = 'travel',
        (p) => p.remove('category'),
        (p) => p['note'] = 'other',
        (p) => p.remove('note'),
      ]) {
        final p = Map<String, dynamic>.from(payload);
        tamper(p);
        final parsed = expenseFromPayload(p)!;
        expect(
          signatureMatches(
            crypto,
            expenseBody(parsed, signerOf(parsed.sig!)),
            parsed.sig!,
          ),
          isFalse,
        );
      }
    },
  );

  test(
    'an unknown category id survives verbatim (forward compatible)',
    () async {
      final signed = await signExpense(
        crypto,
        expense(category: 'pets'),
        creating: true,
      );
      final parsed = expenseFromPayload(overTheWire(expensePayload(signed)))!;
      expect(parsed.category, 'pets');
      expect(
        signatureMatches(
          crypto,
          expenseBody(parsed, signerOf(parsed.sig!)),
          parsed.sig!,
        ),
        isTrue,
      );
    },
  );

  test('malformed values are ignored, empty strings mean none', () {
    final p = expensePayload(expense())
      ..['category'] = 42
      ..['note'] = '';
    final parsed = expenseFromPayload(p)!;
    expect(parsed.category, isNull);
    expect(parsed.note, isNull);
  });

  test('bootstraps (and so backups) carry the fields', () {
    final content = overTheWire(
      buildBootstrapContent('g1', null, const [], [
        expense(category: 'home', note: 'Q3'),
      ], const []),
    );
    final e = expenseFromPayload(
      Map<String, dynamic>.from((content['expenses'] as List).single as Map),
    )!;
    expect((e.category, e.note), ('home', 'Q3'));
  });
}
