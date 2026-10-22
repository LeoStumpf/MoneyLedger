import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../models/link_model.dart';
import '../../link/group_policy.dart';
import '../app_database.dart';
import 'groups_dao.dart';
import 'members_dao.dart';
import 'settings_dao.dart';

part 'link_dao.g.dart';

/// G52: device-local link-group bookkeeping — this device's link channel per
/// group (incl. the link secret and its per-group Nostr key, both
/// **secrets**: never log them) and the other publishers seen on it
/// (`docs/design/no-login-sharing.md` §7.1). Nothing here is synced.
@DriftAccessor(tables: [LinkChannels, LinkPeers])
class LinkDao extends DatabaseAccessor<AppDatabase> with _$LinkDaoMixin {
  LinkDao(super.db);

  // --- policy ---------------------------------------------------------------

  /// G52 step 4: [groupId]'s [GroupPolicy] (+ who this device is in it),
  /// derived from this device's channel and the **stored** meta only
  /// ([deriveGroupPolicy] — never from inbound data, see `group_policy.dart`).
  ///
  /// G53: a signed meta with an open link makes the group `mixed` also
  /// without a channel here (a Matrix device that hasn't bridged yet).
  Future<GroupPolicyInfo> policyOf(String groupId) async {
    final channel = await getChannel(groupId);
    final meta = await GroupsDao(attachedDatabase).getGroup(groupId);
    final me = channel?.myParticipantId;
    String? myMatrixId;
    if (me != null) {
      final rows = await MembersDao(attachedDatabase).getMembers(groupId);
      myMatrixId = rows.where((m) => m.userId == me).firstOrNull?.matrixId;
    }
    return groupPolicyInfo(
      channel: channel,
      meta: meta,
      myMatrixId: myMatrixId,
    );
  }

  /// Whether [groupId] is link-only here (the Matrix engines skip it).
  Future<bool> isLinkOnly(String groupId) async =>
      (await policyOf(groupId)).isLinkOnly;

  // --- channels -------------------------------------------------------------

  SimpleSelectStatement<$LinkChannelsTable, LinkChannel> _channel(
    String groupId,
  ) => select(linkChannels)..where((t) => t.groupId.equals(groupId));

  Future<LinkChannelModel?> getChannel(String groupId) => _channel(
    groupId,
  ).getSingleOrNull().then((row) => row == null ? null : _channelModel(row));

  Stream<LinkChannelModel?> watchChannel(String groupId) => _channel(
    groupId,
  ).watchSingleOrNull().map((row) => row == null ? null : _channelModel(row));

  /// Every link channel of this ledger DB (= the link groups), by group id.
  Future<List<LinkChannelModel>> getAllChannels() =>
      (select(linkChannels)
            ..orderBy([(t) => OrderingTerm(expression: t.groupId)]))
          .get()
          .then((rows) => rows.map(_channelModel).toList());

  Stream<List<LinkChannelModel>> watchAllChannels() =>
      (select(linkChannels)
            ..orderBy([(t) => OrderingTerm(expression: t.groupId)]))
          .watch()
          .map((rows) => rows.map(_channelModel).toList());

  /// Creates or replaces the channel of [channel]'s group (open / join /
  /// rejoin after a restore / new epoch). Its peers are kept.
  Future<void> putChannel(LinkChannelModel channel) =>
      into(linkChannels).insertOnConflictUpdate(_channelCompanion(channel));

  /// Sets (or clears) who this device is in the group. No-op without a
  /// channel.
  Future<void> setMyParticipant(String groupId, String? participantId) =>
      (update(linkChannels)..where((t) => t.groupId.equals(groupId))).write(
        LinkChannelsCompanion(myParticipantId: Value(participantId)),
      );

  /// The Nostr `created_at` (seconds) for our next event in [groupId]:
  /// `max(nowSec, lastCreatedAt + 1)` — strictly increasing per channel
  /// (§4.5) — stored before it is returned, so two publishes never reuse
  /// one. Null when the group has no channel (dropped meanwhile).
  Future<int?> nextCreatedAt(String groupId, int nowSec) =>
      transaction(() async {
        final row = await _channel(groupId).getSingleOrNull();
        if (row == null) return null;
        final next = math.max(nowSec, row.lastCreatedAt + 1);
        await _setCreatedAt(groupId, next);
        return next;
      });

  /// Moves `lastCreatedAt` up to at least [atLeast] (a relay answered
  /// `replaced:` — it holds a newer event of ours, §4.4). Never backwards.
  Future<void> bumpCreatedAt(String groupId, int atLeast) =>
      transaction(() async {
        final row = await _channel(groupId).getSingleOrNull();
        if (row == null || row.lastCreatedAt >= atLeast) return;
        await _setCreatedAt(groupId, atLeast);
      });

  Future<void> _setCreatedAt(String groupId, int createdAt) =>
      (update(linkChannels)..where((t) => t.groupId.equals(groupId))).write(
        LinkChannelsCompanion(lastCreatedAt: Value(createdAt)),
      );

  /// Records a publish of a snapshot with digest [hash] in [parts] parts at
  /// [at] (ms epoch). No-op without a channel.
  Future<void> recordPublished(
    String groupId, {
    required String hash,
    required int at,
    required int parts,
  }) => (update(linkChannels)..where((t) => t.groupId.equals(groupId))).write(
    LinkChannelsCompanion(
      lastPublishedHash: Value(hash),
      lastPublishedAt: Value(at),
      parts: Value(parts),
    ),
  );

  /// Drops the group's channel and its peers (leave / lock / reset). The
  /// ledger rows stay — [AppDatabase.purgeGroup] removes everything.
  Future<void> deleteChannel(String groupId) => transaction(() async {
    await (delete(linkChannels)..where((t) => t.groupId.equals(groupId))).go();
    await (delete(linkPeers)..where((t) => t.groupId.equals(groupId))).go();
    await SettingsDao(attachedDatabase).clearLinkReplaced(groupId);
  });

  // --- peers ----------------------------------------------------------------

  /// Forgets every publisher seen in [groupId] (G52 step 12: the invite
  /// link was reset — they published under the old topic).
  Future<void> deletePeers(String groupId) =>
      (delete(linkPeers)..where((t) => t.groupId.equals(groupId))).go();

  /// Forgets one publisher of [groupId] (G52 step 12 follow-up: it posted
  /// the "link replaced" marker — it left this topic).
  Future<void> deletePeer(String groupId, String pubkey) => (delete(
    linkPeers,
  )..where((t) => t.groupId.equals(groupId) & t.pubkey.equals(pubkey))).go();

  SimpleSelectStatement<$LinkPeersTable, LinkPeer> _peers(String groupId) =>
      select(linkPeers)
        ..where((t) => t.groupId.equals(groupId))
        ..orderBy([(t) => OrderingTerm(expression: t.pubkey)]);

  Future<List<LinkPeerModel>> getPeers(String groupId) =>
      _peers(groupId).get().then((rows) => rows.map(_peerModel).toList());

  Stream<List<LinkPeerModel>> watchPeers(String groupId) =>
      _peers(groupId).watch().map((rows) => rows.map(_peerModel).toList());

  Future<LinkPeer?> _peer(String groupId, String pubkey) =>
      (select(linkPeers)
            ..where((t) => t.groupId.equals(groupId) & t.pubkey.equals(pubkey)))
          .getSingleOrNull();

  /// Whether [eventId] is the event of [pubkey]'s part [part] in [groupId]
  /// already processed — then it is skipped before decrypting (§4.3).
  Future<bool> isProcessed(
    String groupId,
    String pubkey,
    int part,
    String eventId,
  ) async {
    final row = await _peer(groupId, pubkey);
    return row != null && _decodeEventIds(row.eventIdsJson)[part] == eventId;
  }

  /// Records a processed event of [pubkey] (part [part], Nostr
  /// [createdAt] in seconds) received at [seenAt] (ms epoch). The
  /// `lastCreatedAt` / `lastSeenAt` clocks only move forward; [me] and
  /// [snapshotDigest] are taken from the publisher's newest event (an older
  /// part arriving later doesn't overwrite them).
  Future<void> recordPeerEvent({
    required String groupId,
    required String pubkey,
    required int part,
    required String eventId,
    required int createdAt,
    required int seenAt,
    String? me,
    String? snapshotDigest,
  }) => transaction(() async {
    final row = await _peer(groupId, pubkey);
    final ids = row == null
        ? <int, String>{}
        : _decodeEventIds(row.eventIdsJson);
    ids[part] = eventId;
    final newest = row == null || createdAt >= row.lastCreatedAt;
    await into(linkPeers).insertOnConflictUpdate(
      LinkPeersCompanion(
        groupId: Value(groupId),
        pubkey: Value(pubkey),
        eventIdsJson: Value(_encodeEventIds(ids)),
        lastCreatedAt: Value(math.max(createdAt, row?.lastCreatedAt ?? 0)),
        lastSeenAt: Value(math.max(seenAt, row?.lastSeenAt ?? 0)),
        me: newest ? Value(me) : const Value.absent(),
        snapshotDigest: newest ? Value(snapshotDigest) : const Value.absent(),
      ),
    );
  });

  /// The newest Nostr `created_at` (seconds) seen from any publisher — in
  /// [groupId], or in every link group when null; 0 if none. The live
  /// subscription's `since` is based on it (§4.3).
  Future<int> newestPeerCreatedAt([String? groupId]) async {
    final newest = linkPeers.lastCreatedAt.max();
    final query = selectOnly(linkPeers)..addColumns([newest]);
    if (groupId != null) query.where(linkPeers.groupId.equals(groupId));
    final row = await query.getSingle();
    return row.read(newest) ?? 0;
  }

  // --- mapping --------------------------------------------------------------

  static LinkChannelModel _channelModel(LinkChannel r) => LinkChannelModel(
    groupId: r.groupId,
    epoch: r.epoch,
    secret: r.secret,
    myParticipantId: r.myParticipantId,
    nostrPriv: r.nostrPriv,
    lastPublishedHash: r.lastPublishedHash,
    lastPublishedAt: r.lastPublishedAt,
    lastCreatedAt: r.lastCreatedAt,
    parts: r.parts,
    openedAt: r.openedAt,
  );

  static LinkChannelsCompanion _channelCompanion(LinkChannelModel c) =>
      LinkChannelsCompanion(
        groupId: Value(c.groupId),
        epoch: Value(c.epoch),
        secret: Value(c.secret),
        myParticipantId: Value(c.myParticipantId),
        nostrPriv: Value(c.nostrPriv),
        lastPublishedHash: Value(c.lastPublishedHash),
        lastPublishedAt: Value(c.lastPublishedAt),
        lastCreatedAt: Value(c.lastCreatedAt),
        parts: Value(c.parts),
        openedAt: Value(c.openedAt),
      );

  static LinkPeerModel _peerModel(LinkPeer r) => LinkPeerModel(
    groupId: r.groupId,
    pubkey: r.pubkey,
    me: r.me,
    eventIds: _decodeEventIds(r.eventIdsJson),
    lastCreatedAt: r.lastCreatedAt,
    lastSeenAt: r.lastSeenAt,
    snapshotDigest: r.snapshotDigest,
  );

  /// Parses the per-part event id map; anything malformed reads as empty
  /// (worst case an event is decrypted and merged once more — harmless).
  static Map<int, String> _decodeEventIds(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (int.tryParse('${e.key}') case final part? when e.value is String)
            part: e.value as String,
      };
    } on FormatException {
      return {};
    }
  }

  static String _encodeEventIds(Map<int, String> ids) => jsonEncode({
    for (final part in ids.keys.toList()..sort()) '$part': ids[part],
  });
}
