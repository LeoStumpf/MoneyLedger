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
  Random? random,
}) => LinkChannelModel(
  groupId: groupId,
  epoch: 1,
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

  /// This device already shares the group with a **different** link
  /// (a reset invite link, step 12, decides what happens then).
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
