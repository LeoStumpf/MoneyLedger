/// G52 step 2: Nostr events (NIP-01) — model, id, BIP-340 sign / verify and
/// the per-group secp256k1 key (design doc `docs/design/no-login-sharing.md`
/// §3.3, §4.2).
///
/// ```
/// id  = sha256(utf8(json([0, pubkey, created_at, kind, tags, content])))
/// sig = BIP-340 Schnorr signature of id under the event's private key
/// ```
///
/// **Serialization.** The id JSON is Dart's `jsonEncode` (no whitespace,
/// UTF-8, `\" \\ \n \r \t \b \f` escaped, other control characters as
/// `\u00XX`, everything else verbatim) — byte-identical to JavaScript's
/// `JSON.stringify`, which nostr-tools and the relays' clients use (as the
/// G51 spike). NIP-01's text asks for other control characters verbatim;
/// our own events never contain any (base64 content, hex / ASCII tags), and a
/// foreign event that relies on it just fails the id check.
///
/// **Keys.** Each device makes a random secp256k1 key **per link group**
/// (§3.1, never derived from the link secret). `bip340` (MIT) does the
/// curve math with Dart `BigInt` — not constant-time, acceptable for
/// throwaway per-group keys (§11). Signing costs ≈ 18 ms native / 230 ms
/// dart2js, verifying ≈ 12 / 170 ms (§16) — the pool verifies on native only
/// (`kVerifyNostrSignatures`, Leo 2026-10-17).
///
/// Pure Dart, no Flutter, no I/O (compiles with dart2js).
library;

import 'dart:convert';
import 'dart:math';

import 'package:bip340/bip340.dart' as bip340;
import 'package:crypto/crypto.dart' as hash;

import '../link_keys.dart' show hexOf;

/// Largest event JSON (`jsonEncode(event.toJson())`, UTF-8 bytes) we send:
/// both default relays (strfry `maxEventSize`) refuse anything bigger with
/// `invalid: event too large`, although NIP-11 advertises a 131 072-byte
/// frame (G51 E1, §16).
const kNostrMaxEventBytes = 65536;

/// NIP-01 kind ranges.
bool isAddressableKind(int kind) => kind >= 30000 && kind < 40000;
bool isReplaceableKind(int kind) =>
    kind == 0 || kind == 3 || (kind >= 10000 && kind < 20000);

/// The secp256k1 group order n.
final _curveOrder = BigInt.parse(
  'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
  radix: 16,
);

final _hex64 = RegExp(r'^[0-9a-f]{64}$');
final _hex128 = RegExp(r'^[0-9a-f]{128}$');

/// Whether [s] is 32 bytes of lowercase hex (an id / pubkey / key).
bool isHex64(String s) => _hex64.hasMatch(s);

/// A signed Nostr event (immutable; tags are copied on construction).
class NostrEvent {
  /// 64 lowercase hex chars: [nostrEventId] of the other fields.
  final String id;

  /// 64 lowercase hex chars: the x-only secp256k1 public key.
  final String pubkey;

  /// Seconds since the epoch.
  final int createdAt;

  final int kind;
  final List<List<String>> tags;
  final String content;

  /// 128 lowercase hex chars: the BIP-340 signature of [id].
  final String sig;

  NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required List<List<String>> tags,
    required this.content,
    required this.sig,
  }) : tags = List.unmodifiable([
         for (final t in tags) List<String>.unmodifiable(t),
       ]);

  /// Parses an event object from a relay. Returns null (never throws) for
  /// anything that isn't a structurally valid NIP-01 event: missing / wrongly
  /// typed fields, ids / keys / signatures that aren't lowercase hex of the
  /// right length. Doesn't check the id or the signature ([verifyNostrEvent]).
  static NostrEvent? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final pubkey = json['pubkey'];
    final createdAt = json['created_at'];
    final kind = json['kind'];
    final tags = json['tags'];
    final content = json['content'];
    final sig = json['sig'];
    if (id is! String || !_hex64.hasMatch(id)) return null;
    if (pubkey is! String || !_hex64.hasMatch(pubkey)) return null;
    if (sig is! String || !_hex128.hasMatch(sig)) return null;
    if (createdAt is! int || createdAt < 0) return null;
    if (kind is! int || kind < 0 || kind > 65535) return null;
    if (content is! String || tags is! List) return null;
    final parsed = <List<String>>[];
    for (final t in tags) {
      if (t is! List) return null;
      final tag = <String>[];
      for (final v in t) {
        if (v is! String) return null;
        tag.add(v);
      }
      parsed.add(tag);
    }
    return NostrEvent(
      id: id,
      pubkey: pubkey,
      createdAt: createdAt,
      kind: kind,
      tags: parsed,
      content: content,
      sig: sig,
    );
  }

  /// The first value of the first tag named [name] (`["d", "<topic>"]` →
  /// `tag('d')`), or null.
  String? tag(String name) {
    for (final t in tags) {
      if (t.length > 1 && t[0] == name) return t[1];
    }
    return null;
  }

  /// The `d` tag of an addressable event ("" when absent, as NIP-01).
  String get dTag => tag('d') ?? '';

  /// NIP-40 `expiration` (seconds), or null when absent / not a number.
  int? get expiration {
    final v = tag('expiration');
    return v == null ? null : int.tryParse(v);
  }

  /// Whether the event has expired at [nowSeconds] (NIP-40: clients SHOULD
  /// ignore expired events; relays MAY still serve them).
  bool isExpiredAt(int nowSeconds) {
    final e = expiration;
    return e != null && e <= nowSeconds;
  }

  /// The replacement address: `kind:pubkey:d` for addressable kinds,
  /// `kind:pubkey` for replaceable ones, null for regular events.
  String? get address {
    if (isAddressableKind(kind)) return '$kind:$pubkey:$dTag';
    if (isReplaceableKind(kind)) return '$kind:$pubkey';
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pubkey': pubkey,
    'created_at': createdAt,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': sig,
  };

  /// UTF-8 size of the event JSON — what [kNostrMaxEventBytes] limits.
  int get jsonBytes => utf8.encode(jsonEncode(toJson())).length;

  @override
  String toString() => 'NostrEvent($kind, ${id.substring(0, 8)}…)';
}

/// Whether [a] supersedes [b] at the same address (NIP-01): the newer
/// `created_at` wins; on a tie the **lowest id** is kept.
bool nostrEventIsNewer(NostrEvent a, NostrEvent b) => a.createdAt != b.createdAt
    ? a.createdAt > b.createdAt
    : a.id.compareTo(b.id) < 0;

/// The NIP-01 id: lowercase hex SHA-256 of
/// `[0, pubkey, created_at, kind, tags, content]` (see the library doc for
/// the serialization).
String nostrEventId({
  required String pubkey,
  required int createdAt,
  required int kind,
  required List<List<String>> tags,
  required String content,
}) => hexOf(
  hash.sha256
      .convert(
        utf8.encode(jsonEncode([0, pubkey, createdAt, kind, tags, content])),
      )
      .bytes,
);

/// A fresh random secp256k1 private key (64 lowercase hex chars,
/// 1 ≤ d < n) from `Random.secure()`; tests may pass their own [random].
String generateNostrPrivateKey([Random? random]) {
  final rng = random ?? Random.secure();
  while (true) {
    final h = hexOf(List<int>.generate(32, (_) => rng.nextInt(256)));
    final d = BigInt.parse(h, radix: 16);
    if (d > BigInt.zero && d < _curveOrder) return h;
  }
}

/// Whether [privateKey] is a usable secp256k1 key (64 hex chars, 1 ≤ d < n).
bool isValidNostrPrivateKey(String privateKey) {
  if (!_hex64.hasMatch(privateKey)) return false;
  final d = BigInt.parse(privateKey, radix: 16);
  return d > BigInt.zero && d < _curveOrder;
}

/// The x-only public key (64 lowercase hex chars) of [privateKey]. Throws an
/// [ArgumentError] for an invalid key.
String nostrPublicKey(String privateKey) {
  _checkPrivateKey(privateKey);
  return bip340.getPublicKey(privateKey);
}

void _checkPrivateKey(String privateKey) {
  if (!isValidNostrPrivateKey(privateKey)) {
    throw ArgumentError('not a secp256k1 private key', 'privateKey');
  }
}

/// Builds and signs an event with [privateKey]. [aux] is the BIP-340
/// auxiliary randomness (32 bytes, default fresh from `Random.secure()`;
/// tests pass a fixed one to get a deterministic signature).
NostrEvent signNostrEvent({
  required String privateKey,
  required int kind,
  required List<List<String>> tags,
  required String content,
  required int createdAt,
  List<int>? aux,
}) {
  _checkPrivateKey(privateKey);
  final a = aux ?? List<int>.generate(32, (_) => _rng.nextInt(256));
  final pubkey = bip340.getPublicKey(privateKey);
  final id = nostrEventId(
    pubkey: pubkey,
    createdAt: createdAt,
    kind: kind,
    tags: tags,
    content: content,
  );
  return NostrEvent(
    id: id,
    pubkey: pubkey,
    createdAt: createdAt,
    kind: kind,
    tags: tags,
    content: content,
    sig: signBip340(privateKey, id, a),
  );
}

/// The BIP-340 signature (128 hex) of [message] (64 hex — an event id)
/// under [privateKey] with auxiliary randomness [aux] (32 bytes).
String signBip340(String privateKey, String message, List<int> aux) {
  _checkPrivateKey(privateKey);
  if (aux.length != 32) {
    throw ArgumentError.value(aux.length, 'aux', 'must be 32 bytes');
  }
  if (!_hex64.hasMatch(message)) {
    throw ArgumentError.value(message, 'message', 'must be 64 hex chars');
  }
  return bip340.sign(privateKey, message, hexOf(aux));
}

/// Whether [event]'s id matches its fields.
bool nostrEventIdValid(NostrEvent event) =>
    nostrEventId(
      pubkey: event.pubkey,
      createdAt: event.createdAt,
      kind: event.kind,
      tags: event.tags,
      content: event.content,
    ) ==
    event.id;

/// Verifies a BIP-340 signature: [pubkey] (64 hex), [message] (64 hex — the
/// event id), [signature] (128 hex). False (never throws) for malformed
/// input, a point off the curve or a bad signature.
bool verifyBip340(String pubkey, String message, String signature) {
  final p = pubkey.toLowerCase();
  final m = message.toLowerCase();
  final s = signature.toLowerCase();
  if (!_hex64.hasMatch(p) || !_hex64.hasMatch(m) || !_hex128.hasMatch(s)) {
    return false;
  }
  try {
    return bip340.verify(p, m, s);
  } catch (_) {
    // pointycastle throws on some degenerate points.
    return false;
  }
}

/// Checks [event]'s id and — when [checkSignature] (the pool passes
/// `kVerifyNostrSignatures`: native only) — its BIP-340 signature.
bool verifyNostrEvent(NostrEvent event, {bool checkSignature = true}) {
  if (!nostrEventIdValid(event)) return false;
  return !checkSignature || verifyBip340(event.pubkey, event.id, event.sig);
}

final _rng = Random.secure();
