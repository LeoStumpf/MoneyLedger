/// G52: the snapshot payload of a link-group event and its sharding plan
/// (design doc `docs/design/no-login-sharing.md` §5.1, §5.4, §16).
///
/// Each device publishes its **whole group snapshot**: the G14 bootstrap
/// content (`buildBootstrapContent`: meta, members, expenses, settlements
/// incl. tombstones, `device_keys`) under a small link header:
///
/// ```json
/// { "format": "moneyledger-link", "v": 1,
///   "group": "<groupId>", "me": "<participant id of the publisher>",
///   "part": 0, "parts": 1, "app": "1.4.0",
///   "name": …, "currency": …, "updated_at": …, "meta": …, "members": […],
///   "expenses": […], "settlements": […], "device_keys": {…} }
/// ```
///
/// The header keys **replace** the bootstrap's own: `v` is the link snapshot
/// version (1), not the bootstrap's protocol version — every record inside
/// keeps its own `"v": 2` (as the G51 spike).
///
/// **Sharding.** The sealed `content` of one event must stay within
/// [kLinkContentBudget] chars (both default relays refuse events over
/// 65 536 bytes, §16). A bigger snapshot is split into [parts] = 2, 4 or 8:
/// record `id` goes to part `fnv1a(id) % parts` (the G14 digest bucket hash,
/// [digestBucketOf]), and part `i` is published under `d` = topic (`i` = 0) or
/// `topic.<i>` ([linkPartTopic]). Every part is self-contained (meta + all
/// members + `device_keys` + its slice), so parts merge LWW in any order and
/// across generations. When the part count drops, the parts no longer used
/// are overwritten with header-only parts ([buildRetiredLinkPart]).
///
/// Pure Dart (gzip via `archive` to measure the real packed size), no DB,
/// no network, no crypto: [planLinkSnapshot] returns the packed bytes the
/// envelope (`link_envelope.dart`) then seals.
library;

import 'dart:typed_data';

import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart' as hash;

import '../sync/record_version.dart';
import 'link_envelope.dart';

/// The `format` marker of a link snapshot.
const kLinkSnapshotFormat = 'moneyledger-link';

/// The link snapshot version this build writes and reads.
const kLinkSnapshotVersion = 1;

/// Most `content` chars per event (G51, §16): ≈ 60 500-byte events under the
/// relays' 65 536-byte cap, ~5 KB headroom for the envelope / tags.
const kLinkContentBudget = 60000;

/// Part counts a snapshot may be split into, smallest first.
const kLinkPartCounts = [1, 2, 4, 8];

/// Most parts of one snapshot (readers subscribe to all of them).
const kLinkMaxParts = 8;

/// The `d` tag of part [index] of the group with [topic]: the topic itself
/// for part 0, `<topic>.<index>` otherwise.
String linkPartTopic(String topic, int index) {
  RangeError.checkValueInInterval(index, 0, kLinkMaxParts - 1, 'index');
  return index == 0 ? topic : '$topic.$index';
}

/// Every `d` tag a reader subscribes to for [topic] (parts 0 … 7).
List<String> linkPartTopics(String topic) => [
  for (var i = 0; i < kLinkMaxParts; i++) linkPartTopic(topic, i),
];

/// One part of a planned snapshot.
class LinkSnapshotPart {
  /// 0-based part index (its `d` tag: [linkPartTopic]).
  final int index;

  /// The snapshot JSON of this part (header + its slice).
  final Map<String, dynamic> snapshot;

  /// `gzip(utf8(json(snapshot)))` ([packLinkSnapshot]) — what gets sealed.
  final Uint8List packed;

  const LinkSnapshotPart({
    required this.index,
    required this.snapshot,
    required this.packed,
  });

  /// Chars of the sealed `content` ([linkContentLength]).
  int get contentLength => linkContentLength(packed.length);
}

/// A snapshot split into `parts.length` ∈ [kLinkPartCounts] parts, each
/// within the budget it was planned for.
class LinkSnapshotPlan {
  final List<LinkSnapshotPart> parts;
  const LinkSnapshotPlan(this.parts);
}

/// The snapshot doesn't fit [kLinkMaxParts] parts — "This group is too big
/// for link sharing" (§5.4). [largestContentLength] is the biggest part's
/// content at 8 parts.
class LinkSnapshotTooLargeException implements Exception {
  final int largestContentLength;
  final int budget;
  const LinkSnapshotTooLargeException(this.largestContentLength, this.budget);

  @override
  String toString() =>
      'LinkSnapshotTooLargeException($largestContentLength > $budget)';
}

/// Builds the snapshot part [index] of [parts] from a bootstrap content map
/// ([bootstrap], see `buildBootstrapContent`): the link header, every
/// non-record key of the bootstrap, and only the expenses / settlements whose
/// id falls into this part ([linkPartOf]; all of them when [parts] is 1).
Map<String, dynamic> buildLinkSnapshotPart(
  Map<String, dynamic> bootstrap, {
  required String me,
  required String app,
  int index = 0,
  int parts = 1,
}) {
  _checkPartCount(parts);
  RangeError.checkValueInInterval(index, 0, parts - 1, 'index');
  bool mine(Object? record) =>
      parts == 1 ||
      (record is Map && linkPartOf(_idOf(record), parts) == index);
  return {
    ..._header(bootstrap, me: me, app: app, index: index, parts: parts),
    'expenses': [
      for (final e in _list(bootstrap['expenses']))
        if (mine(e)) e,
    ],
    'settlements': [
      for (final s in _list(bootstrap['settlements']))
        if (mine(s)) s,
    ],
  };
}

/// A header-only part (meta, all members, `device_keys`, no records) that
/// overwrites part [index] — no longer used now that the snapshot has
/// [parts] parts (§5.4 shrinking; `parts` ≤ [index] tells readers it is
/// retired).
Map<String, dynamic> buildRetiredLinkPart(
  Map<String, dynamic> bootstrap, {
  required String me,
  required String app,
  required int index,
  required int parts,
}) {
  _checkPartCount(parts);
  RangeError.checkValueInInterval(index, parts, kLinkMaxParts - 1, 'index');
  return {
    ..._header(bootstrap, me: me, app: app, index: index, parts: parts),
    'expenses': const <Object?>[],
    'settlements': const <Object?>[],
  };
}

/// The part indices to retire when a snapshot goes from [previousParts] to
/// [parts] parts (empty when it grows or stays).
List<int> retiredLinkParts(int previousParts, int parts) => [
  for (var i = parts; i < previousParts && i < kLinkMaxParts; i++) i,
];

/// The part of [parts] a record id belongs to: `fnv1a(id) % parts`
/// ([digestBucketOf] with `log2(parts)` bits — parts is a power of two).
int linkPartOf(String id, int parts) {
  _checkPartCount(parts);
  return digestBucketOf(id, parts.bitLength - 1);
}

/// Plans the snapshot of a group: the fewest parts ([kLinkPartCounts]) such
/// that every part's sealed content is within [budget] chars. Throws
/// [LinkSnapshotTooLargeException] when even [kLinkMaxParts] parts don't
/// fit. [budget] defaults to [kLinkContentBudget] (a custom relay with a
/// smaller limit passes its own, §4.6).
LinkSnapshotPlan planLinkSnapshot(
  Map<String, dynamic> bootstrap, {
  required String me,
  required String app,
  int budget = kLinkContentBudget,
}) {
  var largest = 0;
  for (final parts in kLinkPartCounts) {
    final planned = <LinkSnapshotPart>[];
    largest = 0;
    for (var i = 0; i < parts; i++) {
      final snapshot = buildLinkSnapshotPart(
        bootstrap,
        me: me,
        app: app,
        index: i,
        parts: parts,
      );
      final part = LinkSnapshotPart(
        index: i,
        snapshot: snapshot,
        packed: packLinkSnapshot(snapshot),
      );
      if (part.contentLength > largest) largest = part.contentLength;
      planned.add(part);
    }
    if (largest <= budget) return LinkSnapshotPlan(planned);
  }
  throw LinkSnapshotTooLargeException(largest, budget);
}

/// Why a decrypted object isn't a usable link snapshot.
enum LinkSnapshotError {
  /// No `format: moneyledger-link` marker.
  notASnapshot,

  /// A newer snapshot `v` — from a newer app.
  unsupportedVersion,

  /// Missing / wrong-typed `group`, `part` or `parts`.
  malformed,
}

class LinkSnapshotException implements Exception {
  final LinkSnapshotError kind;
  const LinkSnapshotException(this.kind);

  @override
  String toString() => 'LinkSnapshotException(${kind.name})';
}

/// The link header of a decrypted snapshot.
class LinkSnapshotHeader {
  final String group;

  /// The publisher's participant id — only a hint ("taken" in the picker).
  final String? me;
  final int part;
  final int parts;
  final String? app;

  const LinkSnapshotHeader({
    required this.group,
    required this.me,
    required this.part,
    required this.parts,
    required this.app,
  });

  /// A header-only part overwriting a part no longer in use.
  bool get retired => part >= parts;
}

/// Validates the header of an opened snapshot (`openLinkContent`). The
/// records themselves are checked later by the record gate. Throws
/// [LinkSnapshotException] only.
LinkSnapshotHeader parseLinkSnapshotHeader(Map<String, dynamic> json) {
  if (json['format'] != kLinkSnapshotFormat) {
    throw const LinkSnapshotException(LinkSnapshotError.notASnapshot);
  }
  final v = json['v'];
  if (v is! int) {
    throw const LinkSnapshotException(LinkSnapshotError.malformed);
  }
  if (v > kLinkSnapshotVersion) {
    throw const LinkSnapshotException(LinkSnapshotError.unsupportedVersion);
  }
  final group = json['group'];
  final part = json['part'];
  final parts = json['parts'];
  if (v < 1 ||
      group is! String ||
      group.isEmpty ||
      part is! int ||
      parts is! int ||
      !kLinkPartCounts.contains(parts) ||
      part < 0 ||
      part >= kLinkMaxParts) {
    throw const LinkSnapshotException(LinkSnapshotError.malformed);
  }
  final me = json['me'];
  final app = json['app'];
  return LinkSnapshotHeader(
    group: group,
    me: me is String && me.isNotEmpty ? me : null,
    part: part,
    parts: parts,
    app: app is String ? app : null,
  );
}

/// G52 step 5: the **content digest** of a snapshot (a bootstrap content
/// map, or a decrypted part): lowercase hex SHA-256 of the canonical JSON of
/// its `meta`, `members`, `expenses` and `settlements` — the record lists
/// sorted by id, everything else (the link header, `device_keys`, the
/// legacy top-level meta mirror) left out. Plaintext, never packed / sealed
/// bytes (native and web deflate differ, §3.2).
///
/// Change detection: the engine republishes when the digest of the group's
/// current bootstrap differs from `link_channels.last_published_hash` (§4.4).
/// A publisher with a single part and ours compare equal exactly when they
/// carry the same versions (the cheap "has everything" signal, §5.3). Null
/// when the content can't be canonicalised (e.g. a float from a foreign
/// event).
String? linkSnapshotDigest(Map<String, dynamic> snapshot) {
  List<Object?> sorted(Object? raw, String key) {
    final list = [..._list(raw)];
    String idOf(Object? r) => r is Map ? '${r[key] ?? ''}' : '';
    list.sort((a, b) => idOf(a).compareTo(idOf(b)));
    return list;
  }

  try {
    final bytes = canonicalJson.encode({
      'meta': snapshot['meta'],
      'members': sorted(snapshot['members'], 'participant_id'),
      'expenses': sorted(snapshot['expenses'], 'id'),
      'settlements': sorted(snapshot['settlements'], 'id'),
    });
    return hash.sha256.convert(bytes).toString();
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _header(
  Map<String, dynamic> bootstrap, {
  required String me,
  required String app,
  required int index,
  required int parts,
}) {
  const own = {'format', 'v', 'group', 'me', 'part', 'parts', 'app'};
  return {
    'format': kLinkSnapshotFormat,
    'v': kLinkSnapshotVersion,
    'group': bootstrap['group'],
    'me': me,
    'part': index,
    'parts': parts,
    'app': app,
    for (final e in bootstrap.entries)
      if (!own.contains(e.key) && e.key != 'expenses' && e.key != 'settlements')
        e.key: e.value,
  };
}

List<Object?> _list(Object? raw) => raw is List ? raw : const [];

String _idOf(Map<dynamic, dynamic> record) {
  final id = record['id'];
  return id is String ? id : '';
}

void _checkPartCount(int parts) {
  if (!kLinkPartCounts.contains(parts)) {
    throw ArgumentError.value(parts, 'parts', 'must be 1, 2, 4 or 8');
  }
}
