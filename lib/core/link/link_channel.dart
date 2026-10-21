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
    if (group == null) {
      throw const LinkChannelException(LinkChannelError.noGroup);
    }
    if (group.sig != null) {
      throw const LinkChannelException(LinkChannelError.signedGroup);
    }
    final people = await members.getMembers(groupId);
    if (people.any((m) => m.matrixId != null && m.matrixId != identity)) {
      throw const LinkChannelException(LinkChannelError.matrixMembers);
    }
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
    if (group.pendingSign) {
      await groups.upsertGroupLww(
        groupCompanion(group.asLinkVersion(group.linkAuthor)),
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
    final channel = LinkChannelModel(
      groupId: groupId,
      epoch: 1,
      secret: encodeLinkSecret(generateLinkSecret(random)),
      nostrPriv: generateNostrPrivateKey(random),
      openedAt: now(),
      myParticipantId: mine?.userId,
    );
    await link.putChannel(channel);
    return channel;
  });
}
