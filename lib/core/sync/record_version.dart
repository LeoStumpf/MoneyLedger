import 'dart:convert';

import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import 'record_signing.dart';

/// G27 — deterministic LWW tie-break, and the per-record version tokens the
/// digests carry (plain Dart, no Flutter / DB).
///
/// A record **version** is `(updated_at, hash)`: the LWW clock, and the
/// SHA-256 (lowercase hex) of the version's **content** — Matrix canonical
/// JSON of the same body G6 signs, minus the signatures (`origin`, `signer`;
/// see `expenseContent` & co. in `record_signing.dart`). Ordering: the higher
/// clock wins; on an **equal clock the higher hash wins** (plain string
/// compare of the hex). Equal clock + equal hash = the same content → no-op.
///
/// Signatures are excluded on purpose: the signed and the still
/// `pending_sign` copy of a local write are the same version (re-signing at
/// the same clock must still be written), and two devices that wrote the
/// identical content at the same millisecond simply agree (only "last edited
/// by" may then differ between devices).

/// One record version: LWW clock + content hash. An empty [hash] means
/// "unknown" (a digest entry without a hash) and ties with any hash.
typedef RecordVersion = ({int at, String hash});

/// Compares two versions: clock first, then (when both are known) the hash.
/// Negative when [a] loses to [b], 0 when they are the same version (or the
/// tie can't be decided because a hash is unknown), positive when [a] wins.
int compareVersions(RecordVersion a, RecordVersion b) {
  if (a.at != b.at) return a.at < b.at ? -1 : 1;
  if (a.hash.isEmpty || b.hash.isEmpty) return 0;
  final short = a.hash.length < b.hash.length ? a.hash.length : b.hash.length;
  // Compare on the common prefix: a digest carries only [kDigestHashChars]
  // of the hash, and prefix order agrees with full-string order whenever the
  // prefixes differ.
  return a.hash.substring(0, short).compareTo(b.hash.substring(0, short));
}

/// Whether [incoming] should replace [stored] in an LWW upsert: strictly
/// newer, or same clock with a higher hash. Same version → false (no-op).
bool versionWins(RecordVersion incoming, RecordVersion? stored) =>
    stored == null || compareVersions(incoming, stored) > 0;

String _hash(Map<String, Object?> content) =>
    sha256.convert(canonicalJson.encode(content)).toString();

/// The content hash of [e] — the DB-cached one (G37, `version_hash`) when the
/// model was read from a row, else computed.
String expenseVersionHash(ExpenseModel e) =>
    e.versionHash ?? computeExpenseVersionHash(e);
String settlementVersionHash(SettlementModel s) =>
    s.versionHash ?? computeSettlementVersionHash(s);

/// The content hash of [e], always computed (what the DAO stores, G37).
String computeExpenseVersionHash(ExpenseModel e) => _hash(expenseContent(e));
String computeSettlementVersionHash(SettlementModel s) =>
    _hash(settlementContent(s));
String memberVersionHash(MemberModel m) => _hash(memberContent(m));
String groupMetaVersionHash(GroupModel g) => _hash(groupMetaContent(g));

RecordVersion expenseVersion(ExpenseModel e) =>
    (at: e.updatedAt, hash: expenseVersionHash(e));
RecordVersion settlementVersion(SettlementModel s) =>
    (at: s.updatedAt, hash: settlementVersionHash(s));
RecordVersion memberVersion(MemberModel m) =>
    (at: m.updatedAt, hash: memberVersionHash(m));
RecordVersion groupMetaVersion(GroupModel g) =>
    (at: g.updatedAt, hash: groupMetaVersionHash(g));

/// How many hex chars of the content hash a digest entry carries (32 bits:
/// enough to *detect* a same-clock divergence; the receiver's tie-break then
/// compares the full hash of the records themselves).
const kDigestHashChars = 8;

/// A digest entry for [v]: `"<updated_at>:<hash8>"`.
String encodeDigestVersion(RecordVersion v) =>
    v.hash.isEmpty ? '${v.at}' : '${v.at}:${_short(v.hash)}';

String _short(String hash) => hash.length <= kDigestHashChars
    ? hash
    : hash.substring(0, kDigestHashChars);

/// Parses a digest entry: `"<ms>:<hash>"`, or a bare int / `"<ms>"` (no
/// hash → unknown, ties with anything at the same clock). Null if malformed.
RecordVersion? parseDigestVersion(Object? raw) {
  if (raw is int) return (at: raw, hash: '');
  if (raw is! String) return null;
  final i = raw.indexOf(':');
  final at = int.tryParse(i < 0 ? raw : raw.substring(0, i));
  if (at == null) return null;
  return (at: at, hash: i < 0 ? '' : raw.substring(i + 1));
}

// ── hash buckets (G14) ──────────────────────────────────────────────────────

/// 32-bit FNV-1a over the UTF-16 code units of [s] (ids are ASCII UUIDs).
int _fnv1a32(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// The digest bucket of a record id for a digest with `2^bits` buckets.
/// Independent of the record kind and content — both sides agree on it.
int digestBucketOf(String id, int bits) => _fnv1a32(id) & ((1 << bits) - 1);

/// Smallest / largest bucket exponent a bucketed digest uses (16 … 2048
/// buckets). The upper bound keeps the bucket-hash summary itself well inside
/// one to-device message (2048 × ~15 bytes ≈ 31 KB).
const kMinDigestBucketBits = 4;
const kMaxDigestBucketBits = 11;

/// Target average records per bucket: a bucket's detail (~16 × 65 bytes) is
/// small, so a few mismatching buckets cost a few KB.
const kDigestRecordsPerBucket = 16;

/// The bucket exponent for a group with [recordCount] expenses + settlements.
int digestBucketBitsFor(int recordCount) {
  var bits = kMinDigestBucketBits;
  while (bits < kMaxDigestBucketBits &&
      recordCount > kDigestRecordsPerBucket * (1 << bits)) {
    bits++;
  }
  return bits;
}

/// How many chars of the bucket hash (base64url of SHA-256) a summary
/// carries: 72 bits — an accidental collision (a divergence the summary
/// can't see) is negligible.
const kBucketHashChars = 12;

/// Per-bucket hashes over every record version (tombstones included):
/// `hashes[b]` covers the expenses and settlements whose id falls into
/// bucket `b`; an empty bucket hashes to `""`. Expense and settlement entries
/// are tagged so moving an id between kinds would change the hash.
List<String> digestBucketHashes({
  required Map<String, RecordVersion> expenses,
  required Map<String, RecordVersion> settlements,
  required int bits,
}) {
  final lines = List<List<String>>.generate(1 << bits, (_) => []);
  void add(String tag, Map<String, RecordVersion> m) {
    for (final MapEntry(key: id, value: v) in m.entries) {
      lines[digestBucketOf(id, bits)].add('$tag$id=${encodeDigestVersion(v)}');
    }
  }

  add('e', expenses);
  add('s', settlements);
  return [
    for (final l in lines)
      if (l.isEmpty)
        ''
      else
        base64Url
            .encode(sha256.convert(utf8.encode((l..sort()).join('\n'))).bytes)
            .substring(0, kBucketHashChars),
  ];
}
