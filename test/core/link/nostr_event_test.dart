import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/link/link_envelope.dart';
import 'package:money_ledger/core/link/nostr/nostr_event.dart';

/// The official BIP-340 test vectors (bitcoin/bips `bip-0340/test-vectors.csv`
/// at afa13249): index, secret key, public key, aux_rand, message, signature,
/// verification result, comment. Vectors 0–3 also sign; 5–14 must fail.
const _bip340 = [
  (
    0,
    '0000000000000000000000000000000000000000000000000000000000000003',
    'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    'e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca821525f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0',
    true,
    '',
  ),
  (
    1,
    'b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef',
    'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659',
    '0000000000000000000000000000000000000000000000000000000000000001',
    '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
    '6896bd60eeae296db48a229ff71dfe071bde413e6d43f917dc8dcf8c78de33418906d11ac976abccb20b091292bff4ea897efcb639ea871cfa95f6de339e4b0a',
    true,
    '',
  ),
  (
    2,
    'c90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b14e5c9',
    'dd308afec5777e13121fa72b9cc1b7cc0139715309b086c960e18fd969774eb8',
    'c87aa53824b4d7ae2eb035a2b5bbbccc080e76cdc6d1692c4b0b62d798e6d906',
    '7e2d58d8b3bcdf1abadec7829054f90dda9805aab56c77333024b9d0a508b75c',
    '5831aaeed7b44bb74e5eab94ba9d4294c49bcf2a60728d8b4c200f50dd313c1bab745879a5ad954a72c45a91c3a51d3c7adea98d82f8481e0e1e03674a6f3fb7',
    true,
    '',
  ),
  (
    3,
    '0b432b2677937381aef05bb02a66ecd012773062cf3fa2549e44f58ed2401710',
    '25d1dff95105f5253c4022f628a996ad3a0d95fbf21d468a1b33f8c160d8f517',
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    '7eb0509757e246f19449885651611cb965ecc1a187dd51b64fda1edc9637d5ec97582b9cb13db3933705b32ba982af5af25fd78881ebb32771fc5922efc66ea3',
    true,
    'test fails if msg is reduced modulo p or n',
  ),
  (
    4,
    '',
    'd69c3509bb99e412e68b0fe8544e72837dfa30746d8be2aa65975f29d22dc7b9',
    '',
    '4df3c3f68fcc83b27e9d42c90431a72499f17875c81a599b566c9889b9696703',
    '00000000000000000000003b78ce563f89a0ed9414f5aa28ad0d96d6795f9c6376afb1548af603b3eb45c9f8207dee1060cb71c04e80f593060b07d28308d7f4',
    true,
    '',
  ),
  (
    5,
    '',
    'eefdea4cdb677750a420fee807eacf21eb9898ae79b9768766e4faa04a2d4a34',
    '',
    '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
    '6cff5c3ba86c69ea4b7376f31a9bcb4f74c1976089b2d9963da2e5543e17776969e89b4c5564d00349106b8497785dd7d1d713a8ae82b32fa79d5f7fc407d39b',
    false,
    'public key not on the curve',
  ),
  (
    6,
    '',
    'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659',
    '',
    '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
    'fff97bd5755eeea420453a14355235d382f6472f8568a18b2f057a14602975563cc27944640ac607cd107ae10923d9ef7a73c643e166be5ebeafa34b1ac553e2',
    false,
    'has_even_y(R) is false',
  ),
  (
    7,
    '',
    'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659',
    '',
    '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
    '1fa62e331edbc21c394792d2ab1100a7b432b013df3f6ff4f99fcb33e0e1515f28890b3edb6e7189b630448b515ce4f8622a954cfe545735aaea5134fccdb2bd',
    false,
    'negated message',
  ),
  (
    8,
    '',
    'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659',
    '',
    '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
    '6cff5c3ba86c69ea4b7376f31a9bcb4f74c1976089b2d9963da2e5543e177769961764b3aa9b2ffcb6ef947b6887a226e8d7c93e00c5ed0c1834ff0d0c2e6da6',
    false,
    'negated s value',
  ),
  (
    9,
    '',
    'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659',
    '',
    '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
    '0000000000000000000000000000000000000000000000000000000000000000123dda8328af9c23a94c1feecfd123ba4fb73476f0d594dcb65c6425bd186051',
    false,
    'sG - eP is infinite. Test fails in single verification if has_even_y(inf) is defined as true and x(inf) as 0',
  ),
  (
    10,
    '',
    'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659',
    '',
    '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
    '00000000000000000000000000000000000000000000000000000000000000017615fbaf5ae28864013c099742deadb4dba87f11ac6754f93780d5a1837cf197',
    false,
    'sG - eP is infinite. Test fails in single verification if has_even_y(inf) is defined as true and x(inf) as 1',
  ),
  (
    11,
    '',
    'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659',
    '',
    '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
    '4a298dacae57395a15d0795ddbfd1dcb564da82b0f269bc70a74f8220429ba1d69e89b4c5564d00349106b8497785dd7d1d713a8ae82b32fa79d5f7fc407d39b',
    false,
    'sig[0:32] is not an X coordinate on the curve',
  ),
  (
    12,
    '',
    'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659',
    '',
    '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
    'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f69e89b4c5564d00349106b8497785dd7d1d713a8ae82b32fa79d5f7fc407d39b',
    false,
    'sig[0:32] is equal to field size',
  ),
  (
    13,
    '',
    'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659',
    '',
    '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
    '6cff5c3ba86c69ea4b7376f31a9bcb4f74c1976089b2d9963da2e5543e177769fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
    false,
    'sig[32:64] is equal to curve order',
  ),
  (
    14,
    '',
    'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc30',
    '',
    '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
    '6cff5c3ba86c69ea4b7376f31a9bcb4f74c1976089b2d9963da2e5543e17776969e89b4c5564d00349106b8497785dd7d1d713a8ae82b32fa79d5f7fc407d39b',
    false,
    'public key is not a valid X coordinate because it exceeds the field size',
  ),
];

const _pub3 =
    'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9';
const _topic =
    'a926ec0d37565347ac2d300bf9762958d6d67110761343c185c883fc48311ef5';
const _linkTags = [
  ['d', _topic],
  ['expiration', '1797184000'],
  ['alt', 'MoneyLedger encrypted group data'],
];

void main() {
  group('BIP-340 vectors', () {
    for (final v in _bip340) {
      final (i, sec, pub, aux, msg, sig, ok, comment) = v;
      test('vector $i verifies $ok ${comment.isEmpty ? '' : '($comment)'}', () {
        expect(verifyBip340(pub, msg, sig), ok);
      });
      if (sec.isNotEmpty) {
        test('vector $i signs', () {
          expect(nostrPublicKey(sec), pub);
          expect(signBip340(sec, msg, _bytes(aux)), sig);
          final e = signNostrEvent(
            privateKey: sec,
            kind: 1,
            tags: const [],
            content: 'x',
            createdAt: 1,
            aux: _bytes(aux),
          );
          expect(verifyBip340(e.pubkey, e.id, e.sig), isTrue);
        });
      }
    }

    test('malformed input never throws', () {
      expect(verifyBip340('zz', 'aa', 'bb'), isFalse);
      expect(verifyBip340(_pub3, '00' * 32, '00' * 63), isFalse);
      expect(verifyBip340('ff' * 32, '00' * 32, '00' * 64), isFalse);
    });
  });

  group('NIP-01 id', () {
    // Cross-checked with Python: sha256(json.dumps(..., separators=(',',
    // ':'), ensure_ascii=False).encode()) — the JSON.stringify form.
    test('plain note', () {
      expect(
        nostrEventId(
          pubkey: _pub3,
          createdAt: 1700000000,
          kind: 1,
          tags: const [],
          content: 'hello',
        ),
        'a9d53fee641fe563de947fa330a3b4902e52e249894660aaa521cd039e896128',
      );
    });

    test('link event (kind 31847, §4.2 tags)', () {
      expect(
        nostrEventId(
          pubkey: _pub3,
          createdAt: 1792000000,
          kind: kLinkEventKind,
          tags: _linkTags,
          content: '1:AAAA',
        ),
        'e543bbc5f44536e6b25e0dafccd0147e0de4b73f011eed1349fee39ba5411792',
      );
    });

    test('escapes, non-ASCII, empty tag', () {
      expect(
        nostrEventId(
          pubkey: _pub3,
          createdAt: 0,
          kind: 0,
          tags: const [
            ['e', 'x'],
            ['p', 'y', 'wss://r'],
            [],
          ],
          content:
              'line1\nline2 "q" back\\slash\ttab\r\b\f ü 🍕 \u0001 / </script>',
        ),
        'a9deb4f6524ca31339036b1f8c16366592d1bccb3c80d2cffc12ba5807c8bfe0',
      );
    });
  });

  group('signNostrEvent', () {
    test('deterministic with fixed aux (cross-checked with the BIP-340 '
        'reference algorithm)', () {
      final e = signNostrEvent(
        privateKey: '00' * 31 + '03',
        kind: kLinkEventKind,
        tags: _linkTags,
        content: '1:AAAA',
        createdAt: 1792000000,
        aux: List.filled(32, 0),
      );
      expect(e.pubkey, _pub3);
      expect(
        e.id,
        'e543bbc5f44536e6b25e0dafccd0147e0de4b73f011eed1349fee39ba5411792',
      );
      expect(
        e.sig,
        'fd2340bc64993edc744397456e0a47ab270805a361c86634b212e948650d9f8a'
        'be83facf6f06b3f88cbd4ef1dd45957f4c4d6cf71021e278eb62edd053427b30',
      );
      expect(verifyNostrEvent(e), isTrue);
    });

    test('random key round trip; tampering fails', () {
      final priv = generateNostrPrivateKey();
      expect(isValidNostrPrivateKey(priv), isTrue);
      final e = signNostrEvent(
        privateKey: priv,
        kind: kLinkEventKind,
        tags: _linkTags,
        content: '1:abc',
        createdAt: 1792000001,
      );
      expect(e.pubkey, nostrPublicKey(priv));
      expect(verifyNostrEvent(e), isTrue);

      NostrEvent copy({String? content, String? sig, String? pubkey}) =>
          NostrEvent(
            id: e.id,
            pubkey: pubkey ?? e.pubkey,
            createdAt: e.createdAt,
            kind: e.kind,
            tags: e.tags,
            content: content ?? e.content,
            sig: sig ?? e.sig,
          );
      expect(verifyNostrEvent(copy(content: '1:abd')), isFalse);
      // A valid id with another signature: only the signature check sees it.
      final forged = copy(sig: '00' * 64);
      expect(verifyNostrEvent(forged), isFalse);
      expect(verifyNostrEvent(forged, checkSignature: false), isTrue);
    });

    test('rejects invalid private keys', () {
      for (final bad in [
        '00' * 32,
        'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
        'xyz',
        'AB' * 32,
      ]) {
        expect(isValidNostrPrivateKey(bad), isFalse, reason: bad);
        expect(() => nostrPublicKey(bad), throwsArgumentError);
      }
      expect(
        () => signNostrEvent(
          privateKey: '00' * 31 + '03',
          kind: 1,
          tags: const [],
          content: '',
          createdAt: 0,
          aux: [1, 2],
        ),
        throwsArgumentError,
      );
    });

    test('generated keys are in range and differ', () {
      final r = Random(1);
      final keys = {for (var i = 0; i < 5; i++) generateNostrPrivateKey(r)};
      expect(keys, hasLength(5));
      expect(keys.every(isValidNostrPrivateKey), isTrue);
    });
  });

  group('NostrEvent', () {
    final e = signNostrEvent(
      privateKey: '00' * 31 + '03',
      kind: kLinkEventKind,
      tags: _linkTags,
      content: '1:AAAA',
      createdAt: 1792000000,
      aux: List.filled(32, 0),
    );

    test('json round trip', () {
      final back = NostrEvent.tryParse(jsonDecode(jsonEncode(e.toJson())));
      expect(back!.toJson(), e.toJson());
      expect(verifyNostrEvent(back), isTrue);
      expect(e.jsonBytes, utf8.encode(jsonEncode(e.toJson())).length);
    });

    test('tags, address, expiration', () {
      expect(e.dTag, _topic);
      expect(e.tag('alt'), 'MoneyLedger encrypted group data');
      expect(e.tag('p'), isNull);
      expect(e.address, '$kLinkEventKind:$_pub3:$_topic');
      expect(e.expiration, 1797184000);
      expect(e.isExpiredAt(1797183999), isFalse);
      expect(e.isExpiredAt(1797184000), isTrue);
      expect(isAddressableKind(30000), isTrue);
      expect(isAddressableKind(40000), isFalse);
      expect(isReplaceableKind(0), isTrue);
      expect(isReplaceableKind(10002), isTrue);
      expect(isReplaceableKind(1), isFalse);
    });

    test('nostrEventIsNewer: created_at, then lowest id', () {
      NostrEvent at(int t, String id) => NostrEvent(
        id: id,
        pubkey: _pub3,
        createdAt: t,
        kind: kLinkEventKind,
        tags: const [],
        content: '',
        sig: '00' * 64,
      );
      expect(nostrEventIsNewer(at(2, 'ff' * 32), at(1, '00' * 32)), isTrue);
      expect(nostrEventIsNewer(at(1, '00' * 32), at(2, 'ff' * 32)), isFalse);
      expect(nostrEventIsNewer(at(1, '01' * 32), at(1, '02' * 32)), isTrue);
      expect(nostrEventIsNewer(at(1, '02' * 32), at(1, '01' * 32)), isFalse);
    });

    test('tryParse refuses malformed events', () {
      final good = e.toJson();
      Map<String, dynamic> with_(String k, Object? v) => {...good, k: v};
      for (final bad in <Object?>[
        null,
        'x',
        [],
        with_('id', 'AB' * 32),
        with_('id', 'ab'),
        with_('pubkey', null),
        with_('sig', '00' * 63),
        with_('created_at', 1.5),
        with_('created_at', -1),
        with_('kind', '1'),
        with_('kind', 70000),
        with_('tags', 'd'),
        with_('tags', [
          ['d', 1],
        ]),
        with_('tags', ['d']),
        with_('content', 5),
      ]) {
        expect(NostrEvent.tryParse(bad), isNull, reason: '$bad');
      }
      expect(NostrEvent.tryParse({...good, 'extra': 1}), isNotNull);
    });

    test('tags are immutable', () {
      expect(() => e.tags.add(['x']), throwsUnsupportedError);
      expect(() => e.tags.first.add('x'), throwsUnsupportedError);
    });
  });
}

List<int> _bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];
