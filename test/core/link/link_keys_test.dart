import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/link/link_keys.dart';

/// Fixed vectors (computed once with Python's `hmac` / `hashlib`, RFC 5869
/// HKDF-SHA256 with salt = kLinkSaltV1). They pin the v1 derivation forever:
/// a change here means every existing invite link points nowhere.
const _vectors = [
  (
    secret: '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
    topic: '0af6181b4ce360892e655e4362d17c3b901bfc3d200b173ece7989e5498a0f30',
    enc: 'f59d40f946b95632c6bbd4db35e54bc9f778024254d3ff64179d5af6a800eb4d',
  ),
  (
    secret: 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    topic: '51885a4054ab2c02308f0da748823c22c6f084039259cb71ab10e6f4df9b9f9e',
    enc: 'c1ba8772df509e45b052d212f4e76853399a39bb3834bb9bbf3fff013aae865d',
  ),
];

List<int> _bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

void main() {
  test('kLinkSaltV1 is SHA-256("moneyledger-link-v1 salt")', () {
    expect(
      kLinkSaltV1,
      sha256.convert(utf8.encode('moneyledger-link-v1 salt')).bytes,
    );
    expect(
      hexOf(kLinkSaltV1),
      'f4eb5703e87b5f223255b0174f95088d63073d50f7369dacb5b04de5e54ba331',
    );
  });

  test('info strings are pinned', () {
    expect(kLinkTopicInfoV1, 'moneyledger-link-v1 topic');
    expect(kLinkEncInfoV1, 'moneyledger-link-v1 enc');
  });

  for (final v in _vectors) {
    test('derivation vector ${v.secret.substring(0, 8)}…', () async {
      final keys = await deriveLinkKeys(_bytes(v.secret));
      expect(keys.topic, v.topic);
      expect(keys.topic, hasLength(64));
      expect(hexOf(keys.encKey), v.enc);
      expect(keys.encKey, hasLength(32));
    });
  }

  test('topic and key differ, and differ per secret', () async {
    final a = await deriveLinkKeys(generateLinkSecret(Random(1)));
    final b = await deriveLinkKeys(generateLinkSecret(Random(2)));
    expect(a.topic, isNot(hexOf(a.encKey)));
    expect(a.topic, isNot(b.topic));
    expect(a.encKey, isNot(b.encKey));
  });

  test('a secret of the wrong length is an ArgumentError', () {
    expect(() => deriveLinkKeys(List.filled(31, 0)), throwsArgumentError);
    expect(() => deriveLinkKeys(List.filled(33, 0)), throwsArgumentError);
  });

  test('generateLinkSecret: 32 bytes, not constant', () {
    final a = generateLinkSecret();
    final b = generateLinkSecret();
    expect(a, hasLength(kLinkSecretLength));
    expect(a, isNot(b));
  });
}
