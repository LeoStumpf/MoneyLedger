/// G52 step 7: the **look-up before a join** (design doc
/// `docs/design/no-login-sharing.md` §6.2) — what the join page shows
/// before anything is stored: the group the link names, its name and the
/// people to pick "who are you" from.
///
/// [probeLinkGroup] fetches every stored event of the link's topics (all
/// [kLinkMaxParts] parts) from the relays once (`EOSE` or the timeout),
/// opens each with the link's key and builds a [LinkGroupPreview] with the
/// pure [linkGroupPreviewFrom]. It needs **no ledger DB** — a fresh install
/// opened from a link (no account, no local profile yet) can show the
/// picker first and create the local profile with the picked name (§6.2
/// step 2). Nothing is written, nothing is published: the join itself
/// (`LinkSyncEngine.join`) stores the channel and merges the group through
/// the record gate's link path.
///
/// The preview is a **hint only** (records aren't verified here; the gate
/// does that on the real merge): undecryptable events, foreign headers and
/// malformed members are skipped, and when events name different groups
/// the group of the newest event wins.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/member_model.dart';
import '../sync/ledger_payloads.dart';
import 'link_envelope.dart';
import 'link_keys.dart';
import 'link_snapshot.dart';
import 'nostr/nostr_frames.dart';
import 'nostr/nostr_relay_pool.dart';

/// How long the join's look-up waits for the relays (§6.2: 10 s).
const kLinkJoinFetchTimeout = Duration(seconds: 10);

/// A person the join picker offers.
class LinkJoinPerson {
  /// The participant id.
  final String id;
  final String name;

  /// Another phone's snapshot names this participant as its `me` (§6.1 —
  /// a hint: a person's second phone may pick it too).
  final bool usedElsewhere;

  const LinkJoinPerson({
    required this.id,
    required this.name,
    required this.usedElsewhere,
  });
}

/// What a link's events say about its group.
class LinkGroupPreview {
  final String groupId;

  /// The group's name (from the newest meta), null when no event had one.
  final String? name;

  /// Active participants without a Matrix claim, sorted by name.
  final List<LinkJoinPerson> people;

  const LinkGroupPreview({
    required this.groupId,
    required this.name,
    required this.people,
  });
}

/// One opened event: its decrypted snapshot part and Nostr `created_at`.
typedef OpenedLinkPart = ({
  Map<String, dynamic> content,
  LinkSnapshotHeader header,
  int createdAt,
});

/// Pure: the preview of [parts] (any order), or null when there is none.
LinkGroupPreview? linkGroupPreviewFrom(List<OpenedLinkPart> parts) {
  if (parts.isEmpty) return null;
  final newest = parts.reduce((a, b) => b.createdAt > a.createdAt ? b : a);
  final groupId = newest.header.group;
  String? name;
  var metaAt = -1;
  final people = <String, MemberModel>{};
  final used = <String>{};
  for (final p in parts) {
    if (p.header.group != groupId) continue;
    final me = p.header.me;
    if (me != null) used.add(me);
    final meta = p.content['meta'];
    if (meta is Map<String, dynamic>) {
      try {
        final g = groupMetaFromPayload(meta);
        if (g != null && g.roomId == groupId && g.updatedAt > metaAt) {
          metaAt = g.updatedAt;
          name = g.name;
        }
      } catch (_) {
        // A malformed meta is the gate's business; no name from it.
      }
    }
    final top = p.content['name'];
    if (name == null && top is String && top.trim().isNotEmpty) name = top;
    final members = p.content['members'];
    if (members is! List) continue;
    for (final raw in members) {
      if (raw is! Map<String, dynamic>) continue;
      MemberModel? m;
      try {
        m = memberFromPayload(raw);
      } catch (_) {
        m = null;
      }
      if (m == null || m.groupId != groupId) continue;
      final have = people[m.userId];
      if (have == null || m.updatedAt > have.updatedAt) people[m.userId] = m;
    }
  }
  final list = [
    for (final m in people.values)
      if (m.isActive && m.matrixId == null)
        LinkJoinPerson(
          id: m.userId,
          name: m.label,
          usedElsewhere: used.contains(m.userId),
        ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return LinkGroupPreview(groupId: groupId, name: name, people: list);
}

/// Fetches and opens the events of the link with [secret] through [pool]
/// (see the library doc). Null when nothing usable was found. Never throws
/// for relay trouble (the pool doesn't); the caller closes [pool].
Future<LinkGroupPreview?> probeLinkGroup(
  Uint8List secret, {
  required NostrRelayPool pool,
  Duration timeout = kLinkJoinFetchTimeout,
}) async {
  final keys = await deriveLinkKeys(secret);
  final topics = linkPartTopics(keys.topic);
  final result = await pool.fetchOnce([
    NostrFilter(kinds: const [kLinkEventKind], tags: {'d': topics}),
  ], timeout: timeout);
  final parts = <OpenedLinkPart>[];
  for (final e in result.events) {
    final index = topics.indexOf(e.dTag);
    if (index < 0 || e.kind != kLinkEventKind) continue;
    try {
      final content = await openLinkContent(
        e.content,
        keys.encKey,
        d: e.dTag,
        pubkey: e.pubkey,
      );
      final header = parseLinkSnapshotHeader(content);
      if (header.part != index) continue;
      parts.add((content: content, header: header, createdAt: e.createdAt));
    } on LinkEnvelopeException catch (err) {
      debugPrint('[link] join: ignored event ${e.id}: $err');
    } on LinkSnapshotException catch (err) {
      debugPrint('[link] join: ignored event ${e.id}: $err');
    }
  }
  return linkGroupPreviewFrom(parts);
}
