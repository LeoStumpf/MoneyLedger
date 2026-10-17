/// G52: the encrypted `content` of a link-group Nostr event (design doc
/// `docs/design/no-login-sharing.md` §3.2).
///
/// ```
/// plain   = utf8(json(snapshot))              // link_snapshot.dart, §5.1
/// packed  = gzip(plain)                       // `archive` (pure Dart on web)
/// nonce   = 12 random bytes                   // fresh per event
/// aad     = "moneyledger-link-v1|31847|<d>|<pubkey hex>"
/// ct      = AES-256-GCM(encKey, nonce, packed, aad)   // ct ‖ 16-byte tag
/// content = "1:" + base64(nonce ‖ ct)
/// ```
///
/// The AAD binds the ciphertext to the event kind, its `d` tag (topic or
/// part topic) and the publishing pubkey: another key holder can't re-publish
/// a device's snapshot under its own pubkey or another part. `base64` is the
/// standard alphabet with padding (as the G51 spike).
///
/// Opening never throws a raw exception: every failure is a
/// [LinkEnvelopeException] with a [LinkEnvelopeError] kind (the caller
/// ignores + logs the event, §3.2). Pure Dart, no Flutter; the pure-Dart
/// [DartAesGcm] on every platform (as G34).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// The Nostr kind of a link-group snapshot event (addressable range, §4.1).
const kLinkEventKind = 31847;

/// The envelope version prefix of `content`.
const kLinkEnvelopePrefix = '1:';

/// AES-GCM nonce / tag sizes.
const kLinkNonceLength = 12;
const kLinkTagLength = 16;

/// Longest `content` [openLinkContent] looks at: the default relays' event
/// cap (65 536 bytes, §16) — a part we build stays within
/// `kLinkContentBudget` (60 000). Also bounds what a gunzip can expand to.
const kLinkMaxContentLength = 65536;

/// Largest decompressed snapshot accepted (a 60 000-char part of real
/// ledger JSON inflates to well under 1 MB).
const kLinkMaxPlainBytes = 16 * 1024 * 1024;

/// Why an event's content couldn't be opened.
enum LinkEnvelopeError {
  /// A different envelope version prefix (`2:…`) — from a newer app.
  unsupportedVersion,

  /// No version prefix, bad base64, too short / too long.
  malformed,

  /// The AES-GCM tag didn't verify: wrong key (another group / app salt),
  /// tampered ciphertext, or a different kind / `d` / pubkey in the AAD
  /// (GCM can't tell these apart).
  decryptFailed,

  /// Authentic, but the plaintext isn't gzip of a UTF-8 JSON object.
  corruptPayload,
}

/// An event content that couldn't be opened.
class LinkEnvelopeException implements Exception {
  final LinkEnvelopeError kind;
  const LinkEnvelopeException(this.kind);

  @override
  String toString() => 'LinkEnvelopeException(${kind.name})';
}

/// The AAD string of an event with tag `d` = [d], published by [pubkey]
/// (64 lowercase hex chars).
String linkAad(String d, String pubkey) =>
    'moneyledger-link-v1|$kLinkEventKind|$d|$pubkey';

/// `gzip(utf8(json(snapshot)))` — the `packed` bytes of §3.2. The gzip
/// header's modification time is zeroed (the web encoder stamps the current
/// time), so the output is deterministic per platform; native (`dart:io`
/// zlib) and web (pure-Dart deflate) still produce different, equally valid
/// bytes. Change detection must therefore compare plaintext, never packed or
/// sealed bytes.
Uint8List packLinkSnapshot(Map<String, dynamic> snapshot) {
  final out = const GZipEncoder().encodeBytes(
    utf8.encode(jsonEncode(snapshot)),
  );
  // RFC 1952: ID1 ID2 CM FLG MTIME(4 bytes, LE) … — 0 = "no time stamp".
  out.fillRange(4, 8, 0);
  return out;
}

/// Length of the `content` string sealing [packedLength] bytes:
/// `"1:"` + base64 of nonce ‖ ciphertext ‖ tag.
int linkContentLength(int packedLength) =>
    kLinkEnvelopePrefix.length +
    4 * ((kLinkNonceLength + packedLength + kLinkTagLength + 2) ~/ 3);

/// Encrypts [packed] (see [packLinkSnapshot]) for the event with tag
/// `d` = [d] published by [pubkey]. [nonce] defaults to 12 fresh random
/// bytes — pass one only in tests (a reused nonce breaks GCM).
Future<String> sealLinkContent(
  List<int> packed,
  List<int> encKey, {
  required String d,
  required String pubkey,
  List<int>? nonce,
}) async {
  final n = nonce ?? _randomNonce();
  if (n.length != kLinkNonceLength) {
    throw ArgumentError.value(n.length, 'nonce', 'must be 12 bytes');
  }
  final box = await _aes.encrypt(
    packed,
    secretKey: SecretKey(List<int>.of(encKey)),
    nonce: n,
    aad: utf8.encode(linkAad(d, pubkey)),
  );
  return kLinkEnvelopePrefix +
      base64.encode([...n, ...box.cipherText, ...box.mac.bytes]);
}

/// Decrypts + unpacks an event's [content] → the snapshot JSON object
/// (not yet validated as a snapshot: `parseLinkSnapshotHeader`). Throws
/// [LinkEnvelopeException] only.
Future<Map<String, dynamic>> openLinkContent(
  String content,
  List<int> encKey, {
  required String d,
  required String pubkey,
}) async {
  final colon = content.indexOf(':');
  if (colon <= 0 ||
      !RegExp(r'^[0-9]+$').hasMatch(content.substring(0, colon))) {
    throw const LinkEnvelopeException(LinkEnvelopeError.malformed);
  }
  if (!content.startsWith(kLinkEnvelopePrefix)) {
    throw const LinkEnvelopeException(LinkEnvelopeError.unsupportedVersion);
  }
  if (content.length > kLinkMaxContentLength) {
    throw const LinkEnvelopeException(LinkEnvelopeError.malformed);
  }
  final Uint8List raw;
  try {
    raw = base64.decode(content.substring(kLinkEnvelopePrefix.length));
  } on FormatException {
    throw const LinkEnvelopeException(LinkEnvelopeError.malformed);
  }
  if (raw.length < kLinkNonceLength + kLinkTagLength) {
    throw const LinkEnvelopeException(LinkEnvelopeError.malformed);
  }

  final List<int> packed;
  try {
    packed = await _aes.decrypt(
      SecretBox(
        raw.sublist(kLinkNonceLength, raw.length - kLinkTagLength),
        nonce: raw.sublist(0, kLinkNonceLength),
        mac: Mac(raw.sublist(raw.length - kLinkTagLength)),
      ),
      secretKey: SecretKey(List<int>.of(encKey)),
      aad: utf8.encode(linkAad(d, pubkey)),
    );
  } catch (_) {
    // SecretBoxAuthenticationError, or an ArgumentError for a bad key length.
    throw const LinkEnvelopeException(LinkEnvelopeError.decryptFailed);
  }

  final Object? json;
  try {
    final plain = const GZipDecoder().decodeBytes(packed, verify: true);
    if (plain.length > kLinkMaxPlainBytes) {
      throw const FormatException('too large');
    }
    json = jsonDecode(utf8.decode(plain));
  } catch (_) {
    // archive throws various exception / error types on corrupt input.
    throw const LinkEnvelopeException(LinkEnvelopeError.corruptPayload);
  }
  if (json is! Map<String, dynamic>) {
    throw const LinkEnvelopeException(LinkEnvelopeError.corruptPayload);
  }
  return json;
}

final _aes = DartAesGcm.with256bits();

final _rng = Random.secure();

Uint8List _randomNonce() => Uint8List.fromList(
  List<int>.generate(kLinkNonceLength, (_) => _rng.nextInt(256)),
);
