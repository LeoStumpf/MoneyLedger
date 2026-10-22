/// G53 step 3 — **a link participant signs in later** (design doc
/// `docs/design/no-login-sharing.md` §10.1 "Link participant joins Matrix",
/// "Link → Matrix").
///
/// When local mode's ledger moves into a Matrix account ("Connect a Matrix
/// account", G40 `adoptLocalLedger`), every adopted **link group** in which
/// this device picked who it is (`my_participant_id`) is marked
/// ([SettingsDao.markLinkSelfClaimPending]). As soon as the account's device
/// key is ready, [claimLinkParticipants] writes, per marked group:
///  1. a **signed claim** of that participant for the MXID — a new LWW
///     version (`nextLwwClock`), name / status kept, signed by the account's
///     device; peers accept it under the scoped exception (the participant is
///     active and unclaimed, the version is signed by the claimed account,
///     the link is open — record gate / sender gate);
///  2. in a **link-only** group also a **signed meta** with `link` = the
///     channel's epoch + secret (the link is kept) — the group turns `mixed`
///     (§6.4): from then on the account's devices sync it over Matrix too,
///     and its own writes are signed.
/// Both go out on both channels: the link sync engine republishes the
/// snapshot (table change) and they are relayed over Matrix to the group's
/// active Matrix members.
///
/// Skipped (marker cleared): the group / channel / "me" is gone, "me" left
/// the group, another account claims it, or this account already claims
/// another active participant there. A key that isn't ready leaves the
/// marker for the next try (`linkSelfClaimProvider`, every account DB open).
///
/// Only for groups **adopted from local mode** — a Matrix account that joins
/// or creates a link-only group keeps writing it unsigned (G52 step 4);
/// whether such groups should be claimed too is open (plan.md G53).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/expenses/expenses_provider.dart';
import '../../features/auth/auth_provider.dart' show accountUserIdProvider;
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../database/app_database.dart';
import '../database/daos/groups_dao.dart';
import '../database/daos/history_dao.dart';
import '../database/daos/link_dao.dart';
import '../database/daos/members_dao.dart';
import '../database/daos/settings_dao.dart';
import '../matrix/ledger_transport.dart';
import '../matrix/transport_provider.dart';
import '../session/app_session.dart';
import '../session/local_adoption.dart' show localAdoptionResultProvider;
import '../sync/delivery_policy.dart';
import '../sync/ledger_payloads.dart';
import '../sync/record_signing.dart';
import '../sync/sync_engine.dart';

/// What [claimLinkParticipants] wrote for one group (to relay).
class LinkSelfClaim {
  final String groupId;
  final MemberModel claim;

  /// The signed meta that made the group mixed (null: it was already).
  final GroupModel? meta;

  const LinkSelfClaim({required this.groupId, required this.claim, this.meta});
}

/// Writes the pending signed self-claims of [db] for [mxid] — see the
/// library doc. Returns what was written (nothing when [crypto] has no key
/// yet — the markers stay).
Future<List<LinkSelfClaim>> claimLinkParticipants({
  required AppDatabase db,
  required String mxid,
  required RecordCrypto? crypto,
  bool Function()? isAlive,
  int Function()? clock,
}) async {
  bool alive() => !db.isClosed && (isAlive?.call() ?? true);
  if (crypto == null || crypto.identity == null || !mxid.startsWith('@')) {
    return const [];
  }
  final settings = SettingsDao(db);
  final link = LinkDao(db);
  final groups = GroupsDao(db);
  final members = MembersDao(db);
  final out = <LinkSelfClaim>[];
  for (final groupId in await settings.linkSelfClaimsPending()) {
    if (!alive()) break;
    final channel = await link.getChannel(groupId);
    final meta = await groups.getGroup(groupId);
    final me = channel?.myParticipantId;
    final people = await members.getMembers(groupId);
    final current = people.where((m) => m.userId == me).firstOrNull;
    final already = claimedBy(people, mxid);
    final skip =
        channel == null ||
        meta == null ||
        current == null ||
        !current.isActive ||
        (current.matrixId != null && current.matrixId != mxid) ||
        (already != null && already.isActive && already.userId != me) ||
        meta.isLocked;
    if (skip) {
      await settings.clearLinkSelfClaimPending(groupId);
      continue;
    }
    final now = clock?.call();
    final claim = current.matrixId == mxid && current.sig?.user == mxid
        ? current
        : await signMember(
            crypto,
            MemberModel(
              groupId: groupId,
              userId: current.userId,
              displayName: current.displayName,
              matrixId: mxid,
              status: current.status,
              updatedAt: nextLwwClock(current.updatedAt, now: now),
              // G74: the same person claiming its own participant.
              payment: current.payment,
            ),
          );
    GroupModel? signedMeta;
    if (meta.sig == null) {
      signedMeta = await signGroupMeta(
        crypto,
        meta.nextVersion(
          updatedAt: nextLwwClock(meta.updatedAt, now: now),
          link: GroupLink(epoch: channel.epoch, secret: channel.secret),
          lockedAt: null,
        ),
      );
    }
    if (!alive()) break;
    await db.transaction(() async {
      // The claim first: the meta's signer must claim a participant.
      if (!identical(claim, current)) {
        await members.upsertMemberLww(memberCompanion(claim));
      }
      if (signedMeta != null) {
        await groups.upsertGroupLww(groupCompanion(signedMeta));
      }
      await settings.clearLinkSelfClaimPending(groupId);
    });
    debugPrint(
      '[link] $groupId: claimed our participant for $mxid'
      '${signedMeta == null ? '' : ' (now shared with Matrix too)'}',
    );
    out.add(LinkSelfClaim(groupId: groupId, claim: claim, meta: signedMeta));
  }
  return out;
}

/// G53 (Leo 2026-10-22, round 3) — **confirm an invite on the link**: over
/// the link path a claim of a participant is only accepted as the claimed
/// account's own (signed by it). A Matrix invite ("Invite by Matrix ID",
/// signed by the inviter) therefore never reaches the devices that see the
/// group only by link (they refuse it as `claim_not_own`). So the
/// invitee's device, bridging a **mixed** group (signed meta with `link`),
/// writes one version of its own participant signed by itself — name,
/// status and payment details kept, `nextLwwClock` — when no version
/// claimed by [mxid] and signed by [mxid] is known here (stored or in the
/// G48 history). Returns it (to relay), or null when nothing was needed /
/// possible (no key yet: the next bridging run tries again). [crypto] is
/// only asked when a confirmation is due.
Future<MemberModel?> confirmOwnLinkClaim({
  required AppDatabase db,
  required String groupId,
  required String mxid,
  required Future<RecordCrypto?> Function() crypto,
  int Function()? clock,
}) async {
  if (!mxid.startsWith('@')) return null;
  final meta = await GroupsDao(db).getGroup(groupId);
  if (meta == null || meta.sig == null || meta.link == null) return null;
  final members = MembersDao(db);
  final current = claimedBy(await members.getMembers(groupId), mxid);
  if (current == null || !current.isActive || current.matrixId != mxid) {
    return null;
  }
  bool own(MemberModel m) => m.matrixId == mxid && m.sig?.user == mxid;
  if (own(current)) return null;
  final history = await HistoryDao(
    db,
  ).entriesForRecord(groupId, RecordKind.member, current.userId);
  if (history.any((e) => e.member != null && own(e.member!))) return null;
  final key = await crypto();
  if (key == null || key.identity == null || db.isClosed) return null;
  final claim = await signMember(
    key,
    MemberModel(
      groupId: groupId,
      userId: current.userId,
      displayName: current.displayName,
      matrixId: mxid,
      status: current.status,
      updatedAt: nextLwwClock(current.updatedAt, now: clock?.call()),
      payment: current.payment,
    ),
  );
  if (db.isClosed) return null;
  await members.upsertMemberLww(memberCompanion(claim));
  debugPrint('[link] $groupId: confirmed our claim with our own signature');
  return claim;
}

/// Relays [claims] over Matrix to each group's active Matrix members (self
/// included — our other devices): the signed meta first, then the claim.
/// Best-effort (anti-entropy repairs a lost message).
Future<void> relayLinkSelfClaims(
  List<LinkSelfClaim> claims, {
  required MembersDao members,
  required LedgerTransport transport,
  bool Function()? isAlive,
}) async {
  for (final c in claims) {
    if (isAlive != null && !isAlive()) return;
    try {
      final targets = (await members.activeClaimedMatrixIds(c.groupId)).toSet();
      if (targets.isEmpty) continue;
      if (c.meta case final meta?) {
        await transport.sendToUsers(
          targets,
          groupMetaEventType,
          groupMetaPayload(meta),
        );
      }
      await transport.sendToUsers(
        targets,
        memberEventType,
        memberPayload(c.claim),
      );
    } catch (e) {
      debugPrint('[link] relaying the claim of ${c.groupId} failed: $e');
    }
  }
}

/// How long [linkSelfClaimProvider] waits for the device key.
final linkSelfClaimKeyWaitProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 2),
);

/// G53 step 3: runs the pending signed self-claims of the open account DB
/// once its device key is ready (every DB open — so a claim that waited for
/// the key, or a crash, is retried), relays them and pokes the groups.
/// Watched app-wide by `LedgerSyncHost`; never throws.
final linkSelfClaimProvider = Provider<void>((ref) {
  // Re-run once an adoption finished (it writes the markers).
  ref.watch(localAdoptionResultProvider);
  final mxid = ref.watch(accountUserIdProvider);
  if (mxid == null || ref.watch(localModeActiveProvider)) return;
  final db = ref.watch(appDatabaseProvider);
  if (db.isSignedOutPlaceholder || db.isClosed) return;
  final settings = SettingsDao(db);
  final transport = withDeliveryPolicy(
    ref.read(ledgerTransportProvider.future),
    settings,
  )..ignore();
  final keyWait = ref.read(linkSelfClaimKeyWaitProvider);
  final engine = ref.read(syncEngineProvider);
  var disposed = false;
  ref.onDispose(() => disposed = true);
  bool alive() => !disposed && !db.isClosed;

  Future<void> run() async {
    try {
      if ((await settings.linkSelfClaimsPending()).isEmpty) return;
      final t = await transport.timeout(keyWait);
      final deadline = DateTime.now().add(keyWait);
      while (t.crypto.identity == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!alive()) return;
      }
      if (!alive()) return;
      final claims = await claimLinkParticipants(
        db: db,
        mxid: mxid,
        crypto: t.crypto,
        isAlive: alive,
      );
      if (claims.isEmpty || !alive()) return;
      await relayLinkSelfClaims(
        claims,
        members: MembersDao(db),
        transport: t,
        isAlive: alive,
      );
      for (final c in claims) {
        if (alive()) engine.pokeGroup(c.groupId);
      }
    } catch (e) {
      if (alive()) debugPrint('[link] self-claims failed (will retry): $e');
    }
  }

  unawaited(run());
});
