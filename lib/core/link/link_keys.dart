/// G52: key derivation of a link group (design doc
/// `docs/design/no-login-sharing.md` §3.1).
///
/// ```
/// secret = 32 random bytes (Random.secure), carried in the link (`k`)
/// salt   = kLinkSaltV1 = SHA-256("moneyledger-link-v1 salt")   (public)
/// prk    = HKDF-Extract(salt, secret)                         (SHA-256)
/// topic  = HKDF-Expand(prk, "moneyledger-link-v1 topic", 32)  → hex = `d` tag
/// encKey = HKDF-Expand(prk, "moneyledger-link-v1 enc",   32)  → AES-256-GCM key
/// ```
///
/// The salt is a public, versioned protocol constant (§3.4: no secret app
/// key — "the link is the key"); a later link version (`v=2`) can change the
/// derivation. Library: `cryptography` (Apache-2.0), its pure-Dart [DartHkdf]
/// on every platform (as the G34 backup crypto). Pure Dart, no Flutter.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Length of a link secret in bytes.
const kLinkSecretLength = 32;

/// The public HKDF salt of link version 1: SHA-256 of the ASCII string
/// `moneyledger-link-v1 salt` (pinned by `test/core/link/link_keys_test.dart`).
/// Never change it — every existing link would point to another topic.
const List<int> kLinkSaltV1 = [
  0xf4, 0xeb, 0x57, 0x03, 0xe8, 0x7b, 0x5f, 0x22, //
  0x32, 0x55, 0xb0, 0x17, 0x4f, 0x95, 0x08, 0x8d,
  0x63, 0x07, 0x3d, 0x50, 0xf7, 0x36, 0x9d, 0xac,
  0xb5, 0xb0, 0x4d, 0xe5, 0xe5, 0x4b, 0xa3, 0x31,
];

/// HKDF `info` of the topic (`d` tag).
const kLinkTopicInfoV1 = 'moneyledger-link-v1 topic';

/// HKDF `info` of the AES-256-GCM key.
const kLinkEncInfoV1 = 'moneyledger-link-v1 enc';

/// The keys derived from a link secret.
class LinkKeys {
  /// 64 lowercase hex chars: the Nostr `d` tag of part 0 (later parts append
  /// `.<i>`, see `link_snapshot.dart`).
  final String topic;

  /// The 32-byte AES-256-GCM key of the envelope (`link_envelope.dart`).
  final Uint8List encKey;

  const LinkKeys({required this.topic, required this.encKey});
}

/// A fresh random link secret ([kLinkSecretLength] bytes from
/// `Random.secure()`; tests may pass their own [random]).
Uint8List generateLinkSecret([Random? random]) {
  final rng = random ?? Random.secure();
  return Uint8List.fromList(
    List<int>.generate(kLinkSecretLength, (_) => rng.nextInt(256)),
  );
}

const _hkdf = DartHkdf(hmac: DartHmac(DartSha256()), outputLength: 32);

/// Derives the [LinkKeys] of a link-version-1 [secret]. Throws an
/// [ArgumentError] when [secret] isn't [kLinkSecretLength] bytes (a parsed
/// link always is).
Future<LinkKeys> deriveLinkKeys(List<int> secret) async {
  if (secret.length != kLinkSecretLength) {
    throw ArgumentError.value(
      secret.length,
      'secret',
      'a link secret has $kLinkSecretLength bytes',
    );
  }
  // HKDF(salt, secret, info) = Expand(Extract(salt, secret), info) — one
  // Extract per call, the same result as extracting once.
  Future<Uint8List> expand(String info) async {
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(List<int>.of(secret)),
      nonce: kLinkSaltV1,
      info: utf8.encode(info),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  final topic = await expand(kLinkTopicInfoV1);
  return LinkKeys(topic: hexOf(topic), encKey: await expand(kLinkEncInfoV1));
}

/// Lowercase hex of [bytes].
String hexOf(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}
