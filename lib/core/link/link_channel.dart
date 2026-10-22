/// G52 step 5: opening a link channel for an existing group on this device
/// — what the first *Invite by link* does (design doc
/// `docs/design/no-login-sharing.md` §3.1, §6.1, §6.3, §14 Q9: the channel
/// opens only on the first invite).
///
/// [openLinkChannel], in **one transaction**:
/// 1. refuses a group whose stored meta is **signed** (opening a channel
///    would turn it `mixed` — that is G53's *Invite by link* for Matrix
///    groups) and a group in which another Matrix account claims a
///    participant (a Matrix group with a legacy unsigned meta);
/// 2. this device's own participant — the one claimed by the ledger
///    identity (the MXID, or local mode's `local:self`) — is rewritten
///    **without the claim** (a new LWW version via `nextLwwClock`, unsigned,
///    `by` = itself; §6.1: member records of a link group carry no
///    `matrix_id`, and no `local:self` ever leaves the device) and becomes
///    `my_participant_id`;
/// 3. rows local mode left `pendingSign` become plain unsigned link
///    versions (same version — signatures and `pendingSign` aren't part of
///    the G27 hash; §6.3: link versions are never signed later);
/// 4. stores the channel: epoch 1, a fresh 32-byte link secret, a fresh
///    per-group Nostr key (§3.1), `opened_at` = now.
///
/// An existing channel is returned unchanged. After it, the group is
/// `linkOnly` (`group_policy.dart`) and the link sync engine publishes it.
library;

import 'dart:math';

import '../../models/group_model.dart';
import '../../models/link_model.dart';
import '../../models/member_model.dart';
import '../database/app_database.dart';
import '../database/daos/expenses_dao.dart';
import '../database/daos/groups_dao.dart';
import '../database/daos/history_dao.dart';
import '../database/daos/link_dao.dart';
import '../database/daos/members_dao.dart';
import 'link_keys.dart';
import 'link_uri.dart';
import 'nostr/nostr_event.dart';

/// Why a group can't get a link channel.
enum LinkChannelError {
  /// The group isn't stored on this device.
  noGroup,

  /// Its meta is signed — a Matrix group (G53 adds mixed groups).
  signedGroup,

  /// Another Matrix account claims a participant — a Matrix group.
  matrixMembers,

  /// G52 step 12: the group has no link channel on this device (reset /
  /// switch need one).
  noChannel,

  /// G53: opening a link on a Matrix group needs this account to be an
  /// active participant of it (it signs the meta and becomes "me").
  notParticipant,
}

class LinkChannelException implements Exception {
  final LinkChannelError kind;
  const LinkChannelException(this.kind);

  @override
  String toString() => 'LinkChannelException(${kind.name})';
}

/// Why [openLinkChannel] would refuse a group (null = it can get a link
/// channel) — pure, so the invite UI (G52 step 6) offers *Invite with a
/// link* exactly when opening can succeed. [group] is the stored meta
/// (null = not stored), [people] its participants, [identity] the ledger
/// identity whose own claim the channel drops.
LinkChannelError? linkChannelBlocker(
  GroupModel? group,
  List<MemberModel> people, {
  required String? identity,
}) {
  if (group == null) return LinkChannelError.noGroup;
  if (group.sig != null) return LinkChannelError.signedGroup;
  if (people.any((m) => m.matrixId != null && m.matrixId != identity)) {
    return LinkChannelError.matrixMembers;
  }
  return null;
}

/// A fresh channel of [groupId] (epoch 1): a new 32-byte link secret and a
/// new per-group Nostr key (§3.1). Shared by [openLinkChannel] and the
/// *Create group → Share with a link* path (G52 step 6), which stores it
/// **before** the group's first write so the meta is written unsigned in a
/// `linkOnly` group.
///
/// G52 step 7: a **join** passes the link's [secret] (`k`, base64url) —
/// the channel then belongs to the group the link names.
LinkChannelModel newLinkChannel(
  String groupId, {
  required String? myParticipantId,
  required int openedAt,
  String? secret,
  int epoch = 1,
  Random? random,
}) => LinkChannelModel(
  groupId: groupId,
  epoch: epoch,
  secret: secret ?? encodeLinkSecret(generateLinkSecret(random)),
  nostrPriv: generateNostrPrivateKey(random),
  openedAt: openedAt,
  myParticipantId: myParticipantId,
);

/// Opens (or returns) this device's link channel of [groupId] — see the
/// library doc. [identity] is the ledger identity (MXID / `local:self`;
/// null = none, then no participant is "me" yet). [clock] (ms) and
/// [random] are for tests.
Future<LinkChannelModel> openLinkChannel(
  AppDatabase db,
  String groupId, {
  required String? identity,
  int Function()? clock,
  Random? random,
}) {
  final now = clock ?? () => DateTime.now().millisecondsSinceEpoch;
  final link = LinkDao(db);
  final groups = GroupsDao(db);
  final members = MembersDao(db);
  final expenses = ExpensesDao(db);
  return db.transaction(() async {
    final existing = await link.getChannel(groupId);
    if (existing != null) return existing;
    final group = await groups.getGroup(groupId);
    final people = await members.getMembers(groupId);
    final blocker = linkChannelBlocker(group, people, identity: identity);
    if (blocker != null) throw LinkChannelException(blocker);
    final meta = group!; // stored: no blocker
    final mine = identity == null ? null : claimedBy(people, identity);

    // 2. + 3. — members: our claim dropped, pendingSign → link version.
    for (final m in people) {
      final MemberModel next;
      if (m.matrixId != null) {
        next = MemberModel(
          groupId: m.groupId,
          userId: m.userId,
          displayName: m.displayName,
          status: m.status,
          updatedAt: nextLwwClock(m.updatedAt, now: now()),
          linkAuthor: mine?.userId ?? m.userId,
          // G74: carried over unchanged.
          payment: m.payment,
        );
      } else if (m.pendingSign) {
        next = m.asLinkVersion(m.linkAuthor);
      } else {
        continue;
      }
      await members.upsertMemberLww(memberCompanion(next));
    }
    if (meta.pendingSign) {
      await groups.upsertGroupLww(
        groupCompanion(meta.asLinkVersion(meta.linkAuthor)),
      );
    }
    for (final e in await expenses.getAllExpensesForGroup(groupId)) {
      if (!e.pendingSign) continue;
      await expenses.upsertExpenseLww(
        expenseCompanion(e.asLinkVersion(e.linkAuthor)),
      );
    }
    for (final s in await expenses.getAllSettlementsForGroup(groupId)) {
      if (!s.pendingSign) continue;
      await expenses.upsertSettlementLww(
        settlementCompanion(s.asLinkVersion(s.linkAuthor)),
      );
    }

    // 4. — the channel.
    final channel = newLinkChannel(
      groupId,
      myParticipantId: mine?.userId,
      openedAt: now(),
      random: random,
    );
    await link.putChannel(channel);
    return channel;
  });
}

/// Why [joinLinkChannel] refuses a link (G52 step 7).
enum LinkJoinError {
  /// This device holds the group the link names as a **non-link** group
  /// (a Matrix group, or a local group never shared) — joining would turn
  /// it into a link group behind the user's back.
  notALinkGroup,

  /// This device already shares the group with a **different** link —
  /// G52 step 12: the join page offers to **switch** to it
  /// ([replaceLinkChannel] via `LinkSyncEngine.switchLink`; someone reset
  /// the invite link and sent the new one), [joinLinkChannel] itself still
  /// refuses it.
  otherLink,
}

class LinkJoinException implements Exception {
  final LinkJoinError kind;
  const LinkJoinException(this.kind);

  @override
  String toString() => 'LinkJoinException(${kind.name})';
}

/// Why [groupId] can't be joined with the link secret [secret] on this
/// device (null = it can) — pure over what is stored: [channel] (this
/// device's channel of the group, if any) and whether the group's meta
/// ([groupStored]) is stored. Shared by [joinLinkChannel] and the join
/// page's preview.
LinkJoinError? linkJoinBlocker({
  required LinkChannelModel? channel,
  required bool groupStored,
  required String secret,
}) {
  if (channel != null) {
    return channel.secret == secret ? null : LinkJoinError.otherLink;
  }
  return groupStored ? LinkJoinError.notALinkGroup : null;
}

/// G52 step 7: stores this device's channel of [groupId] for a joined link
/// ([secret] = its `k`) — **before** anything of the group is merged, so
/// the first snapshot already goes through the link path of the record
/// gate (`linkOnly`). One transaction: an existing channel with the same
/// secret is returned unchanged (opening the link again); a different one
/// ([LinkJoinError.otherLink]) or a stored group without a channel
/// ([LinkJoinError.notALinkGroup]) throws [LinkJoinException]. A new
/// channel has epoch 1, a fresh per-group Nostr key and no "me" yet (the
/// join picker sets it; nothing is published before).
Future<LinkChannelModel> joinLinkChannel(
  AppDatabase db,
  String groupId, {
  required String secret,
  int Function()? clock,
  Random? random,
}) {
  final now = clock ?? () => DateTime.now().millisecondsSinceEpoch;
  final link = LinkDao(db);
  final groups = GroupsDao(db);
  return db.transaction(() async {
    final existing = await link.getChannel(groupId);
    final blocker = linkJoinBlocker(
      channel: existing,
      groupStored: existing == null && await groups.getGroup(groupId) != null,
      secret: secret,
    );
    if (blocker != null) throw LinkJoinException(blocker);
    if (existing != null) return existing;
    decodeLinkSecret(secret); // a malformed secret never gets stored
    final channel = newLinkChannel(
      groupId,
      myParticipantId: null,
      openedAt: now(),
      secret: secret,
      random: random,
    );
    await link.putChannel(channel);
    return channel;
  });
}

/// G52 step 10: re-opens the channel of [groupId] from a backup file's
/// invite key ([epoch] + [secret], design doc §7.2) — called by the
/// restore **before** the group's records are merged (inside its
/// transaction), so they already go in as a `linkOnly` group. The new
/// channel has a fresh per-group Nostr key and no "me" (a new device for
/// the group: the group page asks "Which person are you?"; nothing is
/// published before). Returns whether a channel was stored. Nothing is
/// stored when this device already has a channel of the group (kept as it
/// is — the same link, or a newer one), when the group is stored here
/// without one (a Matrix / unshared group — like a join, §6.2, a link never
/// turns it into a link group) or when [secret] is malformed.
Future<bool> reopenLinkChannel(
  AppDatabase db,
  String groupId, {
  required int epoch,
  required String secret,
  int Function()? clock,
  Random? random,
}) {
  final now = clock ?? () => DateTime.now().millisecondsSinceEpoch;
  final link = LinkDao(db);
  final groups = GroupsDao(db);
  return db.transaction(() async {
    if (await link.getChannel(groupId) != null) return false;
    if (await groups.getGroup(groupId) != null) return false;
    try {
      decodeLinkSecret(secret);
    } catch (_) {
      return false;
    }
    await link.putChannel(
      newLinkChannel(
        groupId,
        myParticipantId: null,
        openedAt: now(),
        secret: secret,
        epoch: epoch,
        random: random,
      ),
    );
    return true;
  });
}

/// G52 step 12 — **reset invite link** / **switch to a new link** (design
/// doc §7.3, §14 Q10): replaces this device's channel of [groupId] in one
/// transaction with a new one — the next epoch, a fresh per-group Nostr key
/// (the old pubkey was seen on the old topic; nothing links the two), the
/// same "me" and nothing published yet (`last_published_*`, `parts`,
/// `last_created_at` start over) — and forgets the old channel's
/// `link_peers` (they published under the old topic; each comes back with
/// its new key once it switched too). [secret] = the new link's `k`
/// (switching to a link someone else reset); null = a fresh random secret
/// (this device resets). The same secret as now → the channel unchanged.
/// Throws [LinkChannelException] ([LinkChannelError.noChannel]) without a
/// channel and a `LinkUriException` for a malformed [secret]. The ledger
/// rows stay as they are — the group's data simply moves to the new topic
/// with the next publish. Unpublishing the old copy is the caller's job
/// (`LinkSyncEngine.resetLink` / `switchLink`), before this runs.
///
/// G53: [epoch] — the epoch of the signed meta's link a Matrix device
/// follows (bridging); default: the current one + 1.
Future<LinkChannelModel> replaceLinkChannel(
  AppDatabase db,
  String groupId, {
  String? secret,
  int? epoch,
  int Function()? clock,
  Random? random,
}) {
  final now = clock ?? () => DateTime.now().millisecondsSinceEpoch;
  final link = LinkDao(db);
  return db.transaction(() async {
    final existing = await link.getChannel(groupId);
    if (existing == null) {
      throw const LinkChannelException(LinkChannelError.noChannel);
    }
    if (secret != null) {
      if (secret == existing.secret) return existing;
      decodeLinkSecret(secret); // a malformed secret never gets stored
    }
    final next = newLinkChannel(
      groupId,
      myParticipantId: existing.myParticipantId,
      openedAt: now(),
      secret: secret,
      epoch: epoch ?? existing.epoch + 1,
      random: random,
    );
    await link.deletePeers(groupId);
    await link.putChannel(next);
    return next;
  });
}

/// G53 (§10.1 "Matrix → link", step 2): what this device must do so its
/// link channel of [group] follows the group's **signed** meta — pure over
/// the stored meta, this device's [channel] and whether its account claims
/// an active participant ([me]: that participant's id, null = none / not a
/// Matrix account).
enum LinkBridgeAction {
  /// Nothing to do.
  none,

  /// The meta opens a link this device doesn't share yet: create a channel
  /// with the meta's secret + epoch, "me" = [me] (a Matrix device bridges).
  create,

  /// The meta names another link than this device's channel (someone reset
  /// it): switch to the meta's link (unpublish the old copy first).
  replace,

  /// "Me" of the channel isn't the participant this account claims.
  setMe,

  /// The meta is signed without a link — the group was locked (or is a
  /// Matrix group): drop the channel (unpublish first).
  drop,
}

LinkBridgeAction linkBridgeAction({
  required GroupModel? group,
  required LinkChannelModel? channel,
  required String? me,
}) {
  if (group == null || group.sig == null) return LinkBridgeAction.none;
  final link = group.link;
  if (link == null) {
    return channel == null ? LinkBridgeAction.none : LinkBridgeAction.drop;
  }
  // Only a device whose Matrix account is an active participant bridges /
  // follows the meta (a device without one shares the group by the link it
  // opened — it switches only when the user opens a new link).
  if (me == null) return LinkBridgeAction.none;
  if (channel == null) return LinkBridgeAction.create;
  if (channel.secret != link.secret) return LinkBridgeAction.replace;
  if (channel.myParticipantId != me) return LinkBridgeAction.setMe;
  return LinkBridgeAction.none;
}

/// The highest link epoch [groupId]'s metas ever carried on this device
/// (current meta + the G48 version history; 0 = none) — a reopened link
/// gets the next one (§10.1 "Reopen = a new epoch"). The epoch is
/// informational (the keys come from the secret alone).
Future<int> lastLinkEpoch(AppDatabase db, String groupId) async {
  var epoch = (await GroupsDao(db).getGroup(groupId))?.link?.epoch ?? 0;
  for (final e in await HistoryDao(db).entriesForGroup(groupId)) {
    final link = e.meta?.link;
    if (link != null && link.epoch > epoch) epoch = link.epoch;
  }
  final channel = await LinkDao(db).getChannel(groupId);
  if (channel != null && channel.epoch > epoch) epoch = channel.epoch;
  return epoch;
}
