/// G6 signed records — the codec: canonical bodies, the signed message,
/// signing + verification (with the fake HMAC device keys), tamper / replay
/// resistance and the local signer's pending fallback.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/hmac_record_crypto.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import '../helpers/fake_ledger_network.dart';

const alice = '@alice:x.org';

ExpenseModel expense({String description = 'Dinner', int amount = 4200}) =>
    ExpenseModel(
      id: 'e1',
      roomId: 'g1',
      description: description,
      amountCents: amount,
      currency: 'EUR',
      paidBy: 'p1',
      splitsJson: '{"p1":2100,"p2":2100}',
      createdAt: 1000,
      updatedAt: 1000,
    );

void main() {
  final keys = HmacKeyRegistry();
  final crypto = keys.deviceCrypto(alice, 'AAAA');
  final signer = crypto.identity!;

  group('signingMessage', () {
    test('is ASCII, prefixed and independent of key order', () {
      final a = signingMessage({'b': 1, 'a': 'x'});
      final b = signingMessage({'a': 'x', 'b': 1});
      expect(a, b);
      expect(a, startsWith('mlsig1:'));
      expect(a.codeUnits.every((c) => c < 128), isTrue);
      expect(a.length, 'mlsig1:'.length + 43); // unpadded base64url SHA-256
    });

    test('non-ASCII text: NFC and NFD spellings sign the same message', () {
      const nfc = 'Café';
      const nfd = 'Café';
      expect(
        signingMessage({'description': nfc}),
        signingMessage({'description': nfd}),
      );
      expect(
        signingMessage({'description': nfc}),
        isNot(signingMessage({'description': 'Cafe'})),
      );
    });

    test('golden: a fixed body has a fixed message', () {
      expect(
        signingMessage({
          't': 'com.moneyledger.group',
          'group': 'g1',
          'name': 'Trip',
          'currency': 'EUR',
          'updated_at': 5,
          'signer': {'user': alice, 'device': 'AAAA', 'key': 'K'},
        }),
        // Pinned: changing the body encoding would break every stored
        // signature — never change it without a protocol bump.
        _goldenMetaMessage,
      );
    });
  });

  group('sign + verify', () {
    test('an expense creation carries origin + sig, both verifying', () async {
      final e = await signExpense(crypto, expense(), creating: true);
      expect(e.origin!.user, alice);
      expect(e.sig!.device, 'AAAA');
      expect(signatureMatches(crypto, expenseBody(e, signer), e.sig!), isTrue);
      expect(
        signatureMatches(
          crypto,
          originBody(RecordKind.expense, 'e1', 'g1', 1000, signer),
          e.origin!,
        ),
        isTrue,
      );
    });

    test('any changed field breaks the signature', () async {
      final e = await signExpense(crypto, expense(), creating: true);
      for (final tampered in [
        expense(description: 'Lunch'),
        expense(amount: 4201),
      ]) {
        final t = tampered.withSigning(sig: e.sig, origin: e.origin);
        expect(
          signatureMatches(crypto, expenseBody(t, signer), e.sig!),
          isFalse,
        );
      }
    });

    test('a signature does not replay across types or groups', () async {
      final g = await signGroupMeta(
        crypto,
        const GroupModel(roomId: 'g1', name: 'Trip', currency: 'EUR'),
      );
      // Same fields, other group → invalid.
      const other = GroupModel(roomId: 'g2', name: 'Trip', currency: 'EUR');
      expect(
        signatureMatches(crypto, groupMetaBody(other, signer), g.sig!),
        isFalse,
      );
      // An expense signature presented for a settlement body → invalid.
      final e = await signExpense(crypto, expense(), creating: true);
      final s = SettlementModel(
        id: 'e1',
        roomId: 'g1',
        amountCents: 4200,
        currency: 'EUR',
        fromUser: 'p1',
        toUser: 'p2',
        createdAt: 1000,
        updatedAt: 1000,
        origin: e.origin,
      );
      expect(
        signatureMatches(crypto, settlementBody(s, signer), e.sig!),
        isFalse,
      );
    });

    test('nobody can sign for a device without its secret', () async {
      final m = await signMember(
        crypto,
        const MemberModel(
          groupId: 'g1',
          userId: alice,
          matrixId: alice,
          status: 'active',
          updatedAt: 7,
        ),
      );
      // An impostor device claiming alice/AAAA but with its own key: its
      // signature verifies only against *its* key, never alice's.
      final impostor = keys.unlistedCrypto(alice, 'AAAA');
      final forged = await signMember(impostor, m);
      expect(forged.sig!.key, isNot(m.sig!.key));
      final withAliceKey = RecordSignature(
        user: alice,
        device: 'AAAA',
        key: m.sig!.key,
        sig: forged.sig!.sig,
      );
      expect(
        signatureMatches(crypto, memberBody(m, signer), withAliceKey),
        isFalse,
      );
    });

    test('a payload round-trip (wire → model) still verifies', () async {
      final e = await signExpense(crypto, expense(), creating: true);
      final parsed = expenseFromPayload(expensePayload(e))!;
      expect(parsed.sig, e.sig);
      expect(parsed.origin, e.origin);
      expect(
        signatureMatches(crypto, expenseBody(parsed, signer), parsed.sig!),
        isTrue,
      );
    });
  });

  group('RecordSignature', () {
    test('encode / decode and malformed input', () {
      const s = RecordSignature(user: alice, device: 'D', key: 'K', sig: 'S');
      expect(RecordSignature.decode(s.encode()), s);
      expect(RecordSignature.decode(null), isNull);
      expect(RecordSignature.decode('nope'), isNull);
      expect(RecordSignature.fromJson({'user': alice, 'device': 'D'}), isNull);
    });
  });

  group('LocalRecordSigner', () {
    test('signs when ready; marks pendingSign when not', () async {
      final net = FakeMatrixNetwork();
      final t = net.clientFor(alice);
      final local = LocalRecordSigner(Future.value(t));
      final signed = await local.expense(expense(), creating: true);
      expect(signed.sig, isNotNull);
      expect(signed.pendingSign, isFalse);

      t.crypto.ready = false;
      final pending = await local.expense(expense());
      expect(pending.sig, isNull);
      expect(pending.pendingSign, isTrue);
    });

    test('a failing transport yields pendingSign, never an error', () async {
      final local = LocalRecordSigner(Future.error(StateError('no client')));
      final m = await local.member(
        const MemberModel(
          groupId: 'g',
          userId: 'p',
          status: 'active',
          updatedAt: 1,
        ),
      );
      expect(m.pendingSign, isTrue);
    });
  });
}

const _goldenMetaMessage = 'mlsig1:sDTGbRHlk4Fq5R96sLyV5CxkNZzPBYVpvoz-hSf9NjM';
