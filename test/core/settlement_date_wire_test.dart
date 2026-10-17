/// G60: the optional payment (settlement) `date` (ISO `YYYY-MM-DD`) on the
/// wire — exactly like the G49 expense date: part of the signed content and
/// the G27 version hash only when set (every pre-G60 settlement signature
/// and hash stays valid), and checked by the content rules
/// (`settlementProblem` → `recordDateProblem`).
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

SettlementModel payment({String? date, int createdAt = 1760000000000}) =>
    SettlementModel(
      id: 's1',
      roomId: 'g1',
      amountCents: 2500,
      currency: 'EUR',
      fromUser: bob,
      toUser: alice,
      createdAt: createdAt,
      updatedAt: 1760000050000,
      date: date,
    );

Map<String, dynamic> overTheWire(Map<String, dynamic> payload) =>
    jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;

void main() {
  final keys = HmacKeyRegistry();
  final crypto = keys.deviceCrypto(bob, 'BBBB');

  test('an undated payment keeps the pre-G60 body, payload and hash', () {
    expect(settlementContent(payment()).containsKey('date'), isFalse);
    expect(settlementPayload(payment()).containsKey('date'), isFalse);
    // Golden: SHA-256 of the pre-G60 canonical body
    // {"amount":2500,"created_at":1760000000000,"currency":"EUR",
    //  "deleted":false,"from":"@bob:x.org","group":"g1","id":"s1",
    //  "t":"com.moneyledger.settlement","to":"@alice:x.org",
    //  "updated_at":1760000050000} (computed outside the app).
    expect(
      computeSettlementVersionHash(payment()),
      'db7e42f7c6979c7086743d108cc5bd2432b3b1b7296c33e58c098bb159f101cd',
    );
    expect(
      computeSettlementVersionHash(payment(date: '2025-10-05')),
      isNot(computeSettlementVersionHash(payment())),
    );
    expect(payment(date: '').date, isNull);
  });

  test('an undated payment signs exactly the pre-G60 body', () async {
    final signed = await signSettlement(crypto, payment(), creating: true);
    final signer = signerOf(signed.sig!);
    // The body a pre-G60 build rebuilds (no `date` key at all).
    final preG60Body = <String, Object?>{
      't': 'com.moneyledger.settlement',
      'id': 's1',
      'group': 'g1',
      'amount': 2500,
      'currency': 'EUR',
      'from': bob,
      'to': alice,
      'created_at': 1760000000000,
      'updated_at': 1760000050000,
      'deleted': false,
      'origin': signed.origin?.toJson(),
      'signer': settlementBody(signed, signer)['signer'],
    };
    expect(settlementBody(signed, signer), preG60Body);
    expect(signatureMatches(crypto, preG60Body, signed.sig!), isTrue);
  });

  test('round trip: sign → wire → parse → verifies, same hash', () async {
    final signed = await signSettlement(
      crypto,
      payment(date: '2025-10-05'),
      creating: true,
    );
    final payload = overTheWire(settlementPayload(signed));
    expect(payload['date'], '2025-10-05');
    final parsed = settlementFromPayload(payload)!;
    expect(parsed.date, '2025-10-05');
    expect(
      signatureMatches(
        crypto,
        settlementBody(parsed, signerOf(parsed.sig!)),
        parsed.sig!,
      ),
      isTrue,
    );
    expect(
      computeSettlementVersionHash(parsed),
      computeSettlementVersionHash(signed),
    );
    // A pre-G60 build (body without the date) can't verify it — the
    // documented mixed-version caveat (like G49).
    final oldBody = Map.of(settlementBody(signed, signerOf(signed.sig!)))
      ..remove('date');
    expect(signatureMatches(crypto, oldBody, signed.sig!), isFalse);
  });

  test('displayDay = date ?? the local day of created_at', () {
    final created = DateTime(2026, 10, 17, 9, 30).millisecondsSinceEpoch;
    expect(payment(createdAt: created).displayDay, DateTime(2026, 10, 17));
    expect(
      payment(createdAt: created, date: '2026-10-01').displayDay,
      DateTime(2026, 10, 1),
    );
    expect(
      payment(createdAt: created, date: 'soon').displayDay,
      DateTime(2026, 10, 17),
    );
  });

  group('content rules', () {
    final now = DateTime(2026, 10, 17, 12);
    test('valid dates pass', () {
      expect(settlementProblem(payment(), now: now), isNull);
      expect(settlementProblem(payment(date: '2026-10-10'), now: now), isNull);
      expect(settlementProblem(payment(date: '2027-10-17'), now: now), isNull);
    });

    test('malformed, too early or too far ahead → refused', () {
      for (final d in ['yesterday', '2026-13-01', '1999-12-31', '2028-01-01']) {
        expect(settlementProblem(payment(date: d), now: now), isNotNull);
      }
    });
  });
}
