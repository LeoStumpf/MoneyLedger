/// G51 spike: the link-group crypto from docs/design/no-login-sharing.md §3
/// and the minimal NIP-01 event layer (§3.3, §4.2). Pure Dart, no dart:io —
/// so the same code runs native (AOT) and under dart2js (E8).
///
/// Never imported by the app. G52 rebuilds this properly under lib/core/link/
/// with tests and fixed vectors.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bip340/bip340.dart' as bip340;
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

const kLinkKind = 31847;

/// §3.4: public, versioned salt = SHA-256("moneyledger-link-v1 salt").
final List<int> kLinkSaltV1 = hash.sha256
    .convert(utf8.encode('moneyledger-link-v1 salt'))
    .bytes;

final _rng = Random.secure();

Uint8List randomBytes(int n) =>
    Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

String hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<int> bytesOfHex(String h) => [
  for (var i = 0; i < h.length; i += 2)
    int.parse(h.substring(i, i + 2), radix: 16),
];

// ---------------------------------------------------------------- §3.1 keys

class LinkKeys {
  LinkKeys(this.topic, this.encKey);

  /// 64 hex chars, the `d` tag.
  final String topic;
  final SecretKey encKey;
}

const _hkdf = DartHkdf(hmac: DartHmac(DartSha256()), outputLength: 32);

Future<LinkKeys> deriveLinkKeys(List<int> secret) async {
  // HKDF(salt, secret, info) = Expand(Extract(salt, secret), info): one
  // Extract per call here, same result as extracting once.
  Future<List<int>> expand(String info) async => (await _hkdf.deriveKey(
    secretKey: SecretKey(secret),
    nonce: kLinkSaltV1,
    info: utf8.encode(info),
  )).extractBytes();
  final topic = hexOf(await expand('moneyledger-link-v1 topic'));
  final enc = SecretKey(await expand('moneyledger-link-v1 enc'));
  return LinkKeys(topic, enc);
}

// ------------------------------------------------------------ §3.2 envelope

final _aes = DartAesGcm.with256bits();

String _aad(String d, String pubkey) =>
    'moneyledger-link-v1|$kLinkKind|$d|$pubkey';

/// plain → gzip → AES-256-GCM (random nonce, AAD) → "1:" + base64.
Future<String> packContent(
  List<int> plain,
  SecretKey key,
  String d,
  String pubkey, {
  bool compress = true,
}) async {
  final packed = compress ? const GZipEncoder().encodeBytes(plain) : plain;
  final nonce = randomBytes(12);
  final box = await _aes.encrypt(
    packed,
    secretKey: key,
    nonce: nonce,
    aad: utf8.encode(_aad(d, pubkey)),
  );
  return '1:${base64.encode([...nonce, ...box.cipherText, ...box.mac.bytes])}';
}

/// Throws on a wrong key / tampering / wrong AAD (GCM can't tell them apart).
Future<List<int>> unpackContent(
  String content,
  SecretKey key,
  String d,
  String pubkey, {
  bool compressed = true,
}) async {
  if (!content.startsWith('1:')) throw const FormatException('version');
  final raw = base64.decode(content.substring(2));
  final box = SecretBox(
    raw.sublist(12, raw.length - 16),
    nonce: raw.sublist(0, 12),
    mac: Mac(raw.sublist(raw.length - 16)),
  );
  final packed = await _aes.decrypt(
    box,
    secretKey: key,
    aad: utf8.encode(_aad(d, pubkey)),
  );
  return compressed ? const GZipDecoder().decodeBytes(packed) : packed;
}

// ------------------------------------------------------- §3.3 NIP-01 events

final _n = BigInt.parse(
  'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141',
  radix: 16,
);

/// A random secp256k1 private key (hex), 1 ≤ d < n.
String newPrivateKey() {
  while (true) {
    final h = hexOf(randomBytes(32));
    final d = BigInt.parse(h, radix: 16);
    if (d > BigInt.zero && d < _n) return h;
  }
}

String publicKeyOf(String priv) => bip340.getPublicKey(priv);

class NostrEvent {
  NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  factory NostrEvent.fromJson(Map<String, dynamic> j) => NostrEvent(
    id: j['id'] as String,
    pubkey: j['pubkey'] as String,
    createdAt: j['created_at'] as int,
    kind: j['kind'] as int,
    tags: [
      for (final t in j['tags'] as List)
        [for (final x in t as List) x as String],
    ],
    content: j['content'] as String,
    sig: j['sig'] as String,
  );

  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  String? tag(String name) {
    for (final t in tags) {
      if (t.isNotEmpty && t[0] == name && t.length > 1) return t[1];
    }
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

  /// Bytes of the whole client → relay frame `["EVENT", {...}]`.
  int get frameBytes => utf8.encode(jsonEncode(['EVENT', toJson()])).length;
}

/// NIP-01 id: sha256 of `[0,pubkey,created_at,kind,tags,content]`. Dart's
/// jsonEncode escapes exactly what NIP-01 asks (\" \\ \n \r \t \b \f, other
/// controls as \u00XX) and writes non-ASCII as UTF-8.
String eventId(
  String pubkey,
  int createdAt,
  int kind,
  List<List<String>> tags,
  String content,
) => hexOf(
  hash.sha256
      .convert(
        utf8.encode(jsonEncode([0, pubkey, createdAt, kind, tags, content])),
      )
      .bytes,
);

NostrEvent signEvent(
  String priv, {
  required int kind,
  required List<List<String>> tags,
  required String content,
  required int createdAt,
}) {
  final pub = publicKeyOf(priv);
  final id = eventId(pub, createdAt, kind, tags, content);
  final sig = bip340.sign(priv, id, hexOf(randomBytes(32)));
  return NostrEvent(
    id: id,
    pubkey: pub,
    createdAt: createdAt,
    kind: kind,
    tags: tags,
    content: content,
    sig: sig,
  );
}

bool verifyEvent(NostrEvent e) {
  if (eventId(e.pubkey, e.createdAt, e.kind, e.tags, e.content) != e.id) {
    return false;
  }
  return bip340.verify(e.pubkey, e.id, e.sig);
}

int nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// The §4.2 tag set.
List<List<String>> linkTags(String d, {required int expiresAt}) => [
  ['d', d],
  ['expiration', '$expiresAt'],
  ['alt', 'MoneyLedger encrypted group data'],
];

/// NIP-09 deletion for addressable events (+ the concrete ids).
NostrEvent deletionEvent(
  String priv, {
  required List<String> ids,
  required List<String> dTags,
  int? createdAt,
}) {
  final pub = publicKeyOf(priv);
  return signEvent(
    priv,
    kind: 5,
    tags: [
      for (final id in ids) ['e', id],
      for (final d in dTags) ['a', '$kLinkKind:$pub:$d'],
      ['k', '$kLinkKind'],
    ],
    content: 'MoneyLedger G51 spike cleanup',
    createdAt: createdAt ?? nowSec(),
  );
}

// ------------------------------------------------- synthetic snapshot (E8)

/// A fake group in the shape of `buildBootstrapContent` (unsigned, protocol
/// v2 field names) + the §5.1 header. Synthetic names / amounts only.
Map<String, dynamic> syntheticSnapshot({int records = 200, int members = 5}) {
  final r = Random(42);
  const group = '0192a6b4-7c3e-7a01-9f00-5e1d2c3b4a59';
  String uuid() {
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    final h = hexOf(b);
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-7${h.substring(13, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  const names = ['Alex', 'Sam', 'Mia', 'Jonas', 'Lea', 'Ben', 'Nora', 'Tim'];
  const what = [
    'Dinner at the harbour',
    'Groceries',
    'Train tickets',
    'Museum',
    'Coffee',
    'Taxi to the airport',
    'Apartment',
    'Pizza',
    'Fuel',
    'Ice cream',
    'Boat trip',
    'Breakfast',
  ];
  const cats = [
    'food',
    'groceries',
    'transport',
    'entertainment',
    'accommodation',
  ];
  final pids = [for (var i = 0; i < members; i++) uuid()];
  var clock = 1760000000000;
  final m = <Map<String, dynamic>>[
    for (var i = 0; i < members; i++)
      {
        'v': 2,
        'group': group,
        'participant_id': pids[i],
        'name': names[i],
        'matrix_id': null,
        'status': 'active',
        'updated_at': clock += 1000,
      },
  ];
  final expenses = <Map<String, dynamic>>[];
  final settlements = <Map<String, dynamic>>[];
  final nSettle = records ~/ 10;
  for (var i = 0; i < records - nSettle; i++) {
    final amount = 300 + r.nextInt(20000);
    final share = members - r.nextInt(2);
    final split = <String, int>{};
    var rest = amount;
    for (var k = 0; k < share; k++) {
      final c = k == share - 1 ? rest : amount ~/ share;
      split[pids[k]] = c;
      rest -= c;
    }
    final created = clock += 60000 + r.nextInt(3600000);
    expenses.add({
      'v': 2,
      'id': uuid(),
      'group': group,
      'description': what[r.nextInt(what.length)],
      'amount': amount,
      'currency': 'EUR',
      'paid_by': pids[r.nextInt(members)],
      'split': split,
      'created_at': created,
      'updated_at': created + (r.nextBool() ? 0 : r.nextInt(100000)),
      'deleted': r.nextInt(20) == 0,
      if (r.nextBool()) 'category': cats[r.nextInt(cats.length)],
      if (r.nextInt(4) == 0) 'note': 'Tip included, paid by card',
    });
  }
  for (var i = 0; i < nSettle; i++) {
    final created = clock += 60000 + r.nextInt(3600000);
    final from = r.nextInt(members);
    settlements.add({
      'v': 2,
      'id': uuid(),
      'group': group,
      'amount': 500 + r.nextInt(5000),
      'currency': 'EUR',
      'from': pids[from],
      'to': pids[(from + 1) % members],
      'created_at': created,
      'updated_at': created,
      'deleted': false,
    });
  }
  final meta = {
    'v': 2,
    'group': group,
    'name': 'Trip to Rome',
    'currency': 'EUR',
    'updated_at': 1760000000000,
  };
  return {
    'format': 'moneyledger-link',
    'v': 1,
    'group': group,
    'me': pids[0],
    'part': 0,
    'parts': 1,
    'app': '1.4.0',
    'name': meta['name'],
    'currency': meta['currency'],
    'updated_at': meta['updated_at'],
    'meta': meta,
    'members': m,
    'expenses': expenses,
    'settlements': settlements,
    'device_keys': <String, dynamic>{},
  };
}
