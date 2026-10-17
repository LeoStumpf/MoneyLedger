import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/link/link_envelope.dart';
import 'package:money_ledger/core/link/link_keys.dart';

final _secret = List<int>.generate(32, (i) => i);
final _pub = 'ab' * 32;
final _nonce = List<int>.generate(12, (i) => 0xa0 + i);

/// Pinned: AES-256-GCM of "hello link" under the key of secret 00…1f
/// (`link_keys_test.dart`), nonce a0…ab, AAD of d = its topic and pubkey
/// "abab…". The ciphertext part was cross-checked with `openssl enc
/// -aes-256-ctr` (GCM = CTR from counter 2).
const _helloVector = '1:oKGio6Slpqeoqaqrl/wqMzzD7ioX68zVg4lVLAY0Y7zubGpI7r4=';

/// Pinned: a sealed gzip snapshot (packed natively, same key / nonce / AAD).
/// Opening must keep working on every platform and gzip implementation.
const _snapshotVector =
    '1:oKGio6Slpqeoqaqr4BJOX1PjgkN5gzp8Y9J8iTFLISSIxyrg3FAGkQMn9r7a2MJy0K5+MO04'
    '1vBvGlrU7DLPGhke5MuJn1R6w53QU4EUGvrs/W6naPLGF+CrWOkk+2GOJxGSH9mc+kzPYXB+'
    'dsCWb2/Yi8WxUBY=';

const _snapshot = {
  'format': 'moneyledger-link',
  'v': 1,
  'group': 'g1',
  'note': 'Grüße 🍕',
};

Matcher _fails(LinkEnvelopeError kind) =>
    throwsA(isA<LinkEnvelopeException>().having((e) => e.kind, 'kind', kind));

void main() {
  late LinkKeys keys;
  setUpAll(() async => keys = await deriveLinkKeys(_secret));

  test('AAD string is pinned', () {
    expect(kLinkEventKind, 31847);
    expect(linkAad('d0', 'p1'), 'moneyledger-link-v1|31847|d0|p1');
  });

  test('seal vector (fixed nonce)', () async {
    final c = await sealLinkContent(
      utf8.encode('hello link'),
      keys.encKey,
      d: keys.topic,
      pubkey: _pub,
      nonce: _nonce,
    );
    expect(c, _helloVector);
    expect(c.length, linkContentLength(10));
  });

  test('open vector → the pinned snapshot', () async {
    final json = await openLinkContent(
      _snapshotVector,
      keys.encKey,
      d: keys.topic,
      pubkey: _pub,
    );
    expect(json, _snapshot);
  });

  test('round trip with random nonces; nonce differs per seal', () async {
    final packed = packLinkSnapshot(_snapshot);
    final a = await sealLinkContent(
      packed,
      keys.encKey,
      d: keys.topic,
      pubkey: _pub,
    );
    final b = await sealLinkContent(
      packed,
      keys.encKey,
      d: keys.topic,
      pubkey: _pub,
    );
    expect(a, isNot(b));
    expect(a, startsWith('1:'));
    expect(a.length, linkContentLength(packed.length));
    for (final c in [a, b]) {
      expect(
        await openLinkContent(c, keys.encKey, d: keys.topic, pubkey: _pub),
        _snapshot,
      );
    }
  });

  test('packLinkSnapshot: valid gzip, deterministic, no timestamp', () {
    final p1 = packLinkSnapshot(_snapshot);
    final p2 = packLinkSnapshot(_snapshot);
    expect(p1, p2);
    expect(p1.sublist(0, 2), [0x1f, 0x8b]);
    expect(p1.sublist(4, 8), [0, 0, 0, 0]);
    expect(
      jsonDecode(utf8.decode(const GZipDecoder().decodeBytes(p1))),
      _snapshot,
    );
  });

  test('linkContentLength matches base64 length', () async {
    for (final n in [0, 1, 2, 3, 4, 100, 101, 102]) {
      final c = await sealLinkContent(
        List.filled(n, 7),
        keys.encKey,
        d: 'd',
        pubkey: _pub,
      );
      expect(c.length, linkContentLength(n), reason: '$n');
    }
  });

  group('tamper → typed error', () {
    Future<Map<String, dynamic>> open(
      String c, {
      List<int>? key,
      String? d,
      String? pubkey,
    }) => openLinkContent(
      c,
      key ?? keys.encKey,
      d: d ?? keys.topic,
      pubkey: pubkey ?? _pub,
    );

    test('flipped ciphertext / nonce / tag byte', () async {
      final raw = base64.decode(_snapshotVector.substring(2));
      for (final i in [0, 11, 12, raw.length ~/ 2, raw.length - 1]) {
        final bad = [...raw];
        bad[i] ^= 0x01;
        await expectLater(
          open('1:${base64.encode(bad)}'),
          _fails(LinkEnvelopeError.decryptFailed),
          reason: 'byte $i',
        );
      }
    });

    test('truncated ciphertext', () async {
      final raw = base64.decode(_snapshotVector.substring(2));
      await expectLater(
        open('1:${base64.encode(raw.sublist(0, raw.length - 1))}'),
        _fails(LinkEnvelopeError.decryptFailed),
      );
    });

    test('wrong key (another secret)', () async {
      final other = await deriveLinkKeys(List.filled(32, 0xff));
      await expectLater(
        open(_snapshotVector, key: other.encKey),
        _fails(LinkEnvelopeError.decryptFailed),
      );
      await expectLater(
        open(_snapshotVector, key: List.filled(16, 0)),
        _fails(LinkEnvelopeError.decryptFailed),
      );
    });

    test('AAD: other d (another part), other pubkey', () async {
      await expectLater(
        open(_snapshotVector, d: '${keys.topic}.1'),
        _fails(LinkEnvelopeError.decryptFailed),
      );
      await expectLater(
        open(_snapshotVector, pubkey: 'cd' * 32),
        _fails(LinkEnvelopeError.decryptFailed),
      );
    });

    test('version prefix', () async {
      await expectLater(
        open('2:${_snapshotVector.substring(2)}'),
        _fails(LinkEnvelopeError.unsupportedVersion),
      );
      for (final c in [
        '',
        'garbage',
        _snapshotVector.substring(2),
        ':abc',
        'x:abc',
      ]) {
        await expectLater(
          open(c),
          _fails(LinkEnvelopeError.malformed),
          reason: c,
        );
      }
    });

    test('bad base64, too short, too long', () async {
      for (final c in [
        '1:!!!!',
        '1:abc',
        '1:${base64.encode(List.filled(27, 0))}',
        '1:${'A' * kLinkMaxContentLength}',
      ]) {
        await expectLater(
          open(c),
          _fails(LinkEnvelopeError.malformed),
          reason: c.length > 40 ? 'long' : c,
        );
      }
    });

    test('authentic but not gzip / not JSON / not an object', () async {
      for (final packed in [
        utf8.encode('not gzip'),
        const GZipEncoder().encodeBytes(utf8.encode('{nope')),
        const GZipEncoder().encodeBytes(utf8.encode('[1,2]')),
        const GZipEncoder().encodeBytes([0xff, 0xfe, 0x00]),
        <int>[],
      ]) {
        final c = await sealLinkContent(
          packed,
          keys.encKey,
          d: keys.topic,
          pubkey: _pub,
        );
        await expectLater(open(c), _fails(LinkEnvelopeError.corruptPayload));
      }
    });
  });
}
