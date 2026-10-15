import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../core/sync/left_groups.dart';
import '../../core/sync/ledger_payloads.dart';
import '../../core/sync/sync_health.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../expenses/expenses_provider.dart';
import '../onboarding/onboarding_provider.dart';

part 'group_provider.g.dart';

@riverpod
Stream<List<GroupModel>> ledgerGroups(Ref ref) {
  return ref.watch(groupsDaoProvider).watchAllGroups();
}

@riverpod
Stream<List<MemberModel>> groupMembers(Ref ref, String groupId) {
  return ref.watch(membersDaoProvider).watchMembers(groupId);
}

/// This device's own Matrix ID (empty until the transport/client is ready).
@riverpod
String currentUserId(Ref ref) =>
    ref.watch(ledgerTransportProvider).value?.userId ?? '';

/// The participant in [groupId] that this device's account has claimed, if any
/// — i.e. "who am I in this group". Its `userId` is the participant id to use
/// as `paid_by` / split key for the current user (equals the MXID for a
/// from-scratch user, a UUID once they've claimed a pre-existing local slot).
@riverpod
Future<MemberModel?> currentParticipant(Ref ref, String groupId) {
  final myId = ref.watch(currentUserIdProvider);
  if (myId.isEmpty) return Future.value(null);
  return ref.watch(membersDaoProvider).memberByMatrixId(groupId, myId);
}

/// participant id → display label for [groupId]. Falls back to the Matrix id
/// (or the raw participant id) when a participant has no name yet, so the UI
/// never shows a blank. Watches the members stream, so renames/claims reflect
/// live.
@riverpod
Map<String, String> participantNames(Ref ref, String groupId) {
  final members =
      ref.watch(groupMembersProvider(groupId)).value ?? const <MemberModel>[];
  return {
    for (final m in members)
      m.userId: m.displayName.isNotEmpty
          ? m.displayName
          : (m.matrixId ?? m.userId)
  };
}

/// Everything one group/member mutation needs, captured **before the first
/// await** (G23 — same pattern as `ExpenseAdder`'s `_WriteContext`, G19): the
/// account DB + DAOs, the transport and this device's MXID. A mutation thus
/// always targets the account that was active when the user acted, and `ref`
/// is never touched after an await (the auto-dispose notifier may be disposed
/// mid-flight, e.g. when the page that triggered it is popped).
class _GroupWriteContext {
  _GroupWriteContext(Ref ref)
      : db = ref.read(appDatabaseProvider),
        groups = ref.read(groupsDaoProvider),
        members = ref.read(membersDaoProvider),
        expenses = ref.read(expensesDaoProvider),
        settings = ref.read(settingsDaoProvider),
        health = ref.read(syncHealthProvider.notifier),
        transport = ref.read(ledgerTransportProvider.future) {
    // Not every mutation awaits the transport (e.g. a solo-group delete);
    // don't let an unused transport failure surface as an unhandled error.
    transport.ignore();
  }

  final AppDatabase db;
  final GroupsDao groups;
  final MembersDao members;
  final ExpensesDao expenses;
  final SettingsDao settings;
  final SyncHealth health;
  final Future<LedgerTransport> transport;

  Future<String> myMxid() async => (await transport).userId;

  Future<Map<String, dynamic>> buildBootstrap(String groupId) async =>
      buildBootstrapContent(
        groupId,
        await groups.getGroup(groupId),
        await members.getMembers(groupId),
        // Tombstones included: the new member must learn about deletions too,
        // or they would re-gossip dead records via anti-entropy.
        await expenses.getAllExpensesForGroup(groupId),
        await expenses.getAllSettlementsForGroup(groupId),
      );
}

/// Runs [body] with a freshly captured [_GroupWriteContext]: loading → result,
/// where the final state is only set while the notifier is still mounted.
Future<void> _runGroupWrite(
  Ref ref,
  void Function(AsyncValue<void>) setState,
  Future<void> Function(_GroupWriteContext w) body,
) async {
  final w = _GroupWriteContext(ref);
  setState(const AsyncLoading());
  final result = await AsyncValue.guard(() => body(w));
  if (ref.mounted) setState(result);
}

@riverpod
class GroupCreator extends _$GroupCreator {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Creates a group locally (roomless): a fresh UUID id, with the creator as
  /// the first active member. Nothing is sent to Matrix — members are added (and
  /// the group replicated to them) via [MemberAdder].
  Future<void> create(String name, String currency) =>
      _runGroupWrite(ref, (s) => state = s, (w) async {
        final groupId = const Uuid().v7();
        final now = DateTime.now().millisecondsSinceEpoch;
        final me = await w.myMxid();
        await w.groups.upsertGroupLww(GroupsCompanion(
              roomId: Value(groupId),
              name: Value(name),
              currency: Value(currency),
              updatedAt: Value(now),
            ));
        // The creator is the first participant, claimed by their own account
        // (participant id == their MXID, the invariant for from-scratch users).
        await w.members.upsertMemberLww(memberCompanion(
              MemberModel(
                groupId: groupId,
                userId: me,
                displayName: localpartOf(me),
                matrixId: me,
                status: 'active',
                updatedAt: now,
              ),
            ));
      });
}

@riverpod
class MemberAdder extends _$MemberAdder {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> _run(Future<void> Function(_GroupWriteContext w) body) =>
      _runGroupWrite(ref, (s) => state = s, body);

  /// Adds [userId] (a Matrix ID) to the group: records them locally, sends them
  /// the whole group as a bootstrap payload ("send my friend the database"), and
  /// notifies existing members of the new member.
  Future<void> add(String groupId, String userId, {String? displayName}) =>
      _run((w) => _applyAdd(w, groupId, userId, displayName: displayName));

  static Future<void> _applyAdd(
      _GroupWriteContext w, String groupId, String userId,
      {String? displayName}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Added by Matrix ID → a claimed participant (id == MXID for now).
    final member = MemberModel(
      groupId: groupId,
      userId: userId,
      displayName: (displayName != null && displayName.isNotEmpty)
          ? displayName
          : localpartOf(userId),
      matrixId: userId,
      status: 'active',
      updatedAt: now,
    );
    await w.members.upsertMemberLww(memberCompanion(member));

    final transport = await w.transport;

    // 1) Bootstrap the new member with the full group state + ledger.
    await transport.sendToUsers(
        {userId}, bootstrapEventType, await w.buildBootstrap(groupId));

    // 2) Tell the existing active members about the new member.
    final others = (await w.members.activeClaimedMatrixIds(groupId))
        .where((m) => m != userId)
        .toSet();
    await transport.sendToUsers(others, memberEventType, memberPayload(member));
  }

  /// Shares the whole group with a Matrix account **without** assigning them a
  /// participant — they receive the bootstrap and then pick which existing
  /// participant they are (self-claim on join, [selfClaim]). Use this to invite
  /// someone who already has a local placeholder in the ledger.
  Future<void> invite(String groupId, String matrixId) => _run((w) async {
        final transport = await w.transport;
        await transport.sendToUsers(
            {matrixId}, bootstrapEventType, await w.buildBootstrap(groupId));
      });

  /// Adds a Tricount-style local participant: a named person with no Matrix
  /// account (a fresh UUID participant id, `matrixId == null`). They are pure
  /// ledger data — relayed to the claimed members so everyone sees them, but
  /// never a sync target until someone claims the slot.
  Future<void> addLocal(String groupId, String name) => _run((w) async {
        final member = MemberModel(
          groupId: groupId,
          userId: const Uuid().v7(),
          displayName: name,
          matrixId: null,
          status: 'active',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await w.members.upsertMemberLww(memberCompanion(member));
        await _relayToClaimed(w, groupId, member);
      });

  /// Renames a participant (LWW edit), then replicates.
  Future<void> rename(String groupId, String participantId, String name) =>
      _editParticipant(groupId, participantId,
          (m) => _copyWith(m, displayName: name));

  /// Claims a (typically local) participant for the Matrix account [matrixId]:
  /// links the account to the existing ledger identity, keeping all history.
  /// Bootstraps that account with the whole group (they may not have it yet).
  Future<void> claim(String groupId, String participantId, String matrixId) =>
      _run((w) => _applyClaim(w, groupId, participantId, matrixId));

  static Future<void> _applyClaim(_GroupWriteContext w, String groupId,
      String participantId, String matrixId) async {
    final current = _find(await w.members.getMembers(groupId), participantId);
    if (current == null) return;
    final updated = _copyWith(current, matrixId: matrixId);
    await w.members.upsertMemberLww(memberCompanion(updated));
    final transport = await w.transport;
    await transport.sendToUsers(
        {matrixId}, bootstrapEventType, await w.buildBootstrap(groupId));
    final targets = (await w.members.activeClaimedMatrixIds(groupId)).toSet();
    await transport.sendToUsers(
        targets, memberEventType, memberPayload(updated));
  }

  /// Claims an existing participant as **this device's own account** — the
  /// "self-claim on join" of open-points #7. Used when you've been invited to a
  /// group ([invite]) and recognise yourself as one of the existing
  /// participants; links your MXID and replicates so everyone sees the claim.
  Future<void> selfClaim(String groupId, String participantId) =>
      _run((w) async =>
          _applyClaim(w, groupId, participantId, await w.myMxid()));

  /// Joins a group you were invited to as a brand-new participant (you are not
  /// any of the existing local people) — creates a self-participant and tells
  /// the others.
  Future<void> joinAsNew(String groupId, String name) => _run((w) async =>
      _applyAdd(w, groupId, await w.myMxid(), displayName: name));

  /// Detaches the Matrix account from a participant (the "remove account" of
  /// open-points #7) — the participant and their history stay; only the claim
  /// is cleared. Relays to the remaining members and to the detached account's
  /// own device so it learns it is no longer linked.
  Future<void> unclaim(String groupId, String participantId) =>
      _run((w) async {
        final current =
            _find(await w.members.getMembers(groupId), participantId);
        if (current == null || current.matrixId == null) return;
        final detached = current.matrixId!;
        final updated = _copyWith(current, matrixId: null);
        await w.members.upsertMemberLww(memberCompanion(updated));
        final targets =
            (await w.members.activeClaimedMatrixIds(groupId)).toSet()
              ..add(detached);
        final transport = await w.transport;
        await transport.sendToUsers(
            targets, memberEventType, memberPayload(updated));
      });

  Future<void> _editParticipant(String groupId, String participantId,
          MemberModel Function(MemberModel) edit) =>
      _run((w) async {
        final current =
            _find(await w.members.getMembers(groupId), participantId);
        if (current == null) return;
        final updated = edit(current);
        await w.members.upsertMemberLww(memberCompanion(updated));
        await _relayToClaimed(w, groupId, updated);
      });

  static Future<void> _relayToClaimed(
      _GroupWriteContext w, String groupId, MemberModel member) async {
    final transport = await w.transport;
    final targets = (await w.members.activeClaimedMatrixIds(groupId)).toSet();
    if (targets.isEmpty) return;
    await transport.sendToUsers(targets, memberEventType, memberPayload(member));
  }

  static MemberModel? _find(List<MemberModel> members, String participantId) {
    for (final m in members) {
      if (m.userId == participantId) return m;
    }
    return null;
  }

  static MemberModel _copyWith(MemberModel m,
          {String? displayName, Object? matrixId = _unset}) =>
      MemberModel(
        groupId: m.groupId,
        userId: m.userId,
        displayName: displayName ?? m.displayName,
        matrixId: identical(matrixId, _unset) ? m.matrixId : matrixId as String?,
        status: m.status,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
}

/// Sentinel for [_copyWith] so `matrixId: null` (unclaim) is distinguishable
/// from "leave unchanged".
const Object _unset = Object();

/// The participant [members] has as `removed` for [userId], with a fresh LWW
/// clock — identity (name + claim) kept, so history stays attributed and the
/// relay doesn't wipe peers' copies. Null if [userId] isn't a participant.
MemberModel? _removedCopy(List<MemberModel> members, String userId, int now) {
  for (final m in members) {
    if (m.userId == userId) {
      return MemberModel(
        groupId: m.groupId,
        userId: m.userId,
        displayName: m.displayName,
        matrixId: m.matrixId,
        status: 'removed',
        updatedAt: now,
      );
    }
  }
  return null;
}

@riverpod
class MemberRemover extends _$MemberRemover {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Marks [userId] removed (last-writer-wins) and relays the change. Their
  /// expense history stays in Drift, so balances are preserved — only their
  /// membership status changes. The removed user is included in the relay so
  /// their own device updates too.
  Future<void> remove(String groupId, String userId) =>
      _runGroupWrite(ref, (s) => state = s, (w) async {
        final members = await w.members.getMembers(groupId);
        final updated = _removedCopy(
            members, userId, DateTime.now().millisecondsSinceEpoch);
        if (updated == null) return;
        await w.members.upsertMemberLww(memberCompanion(updated));
        // Relay to every claimed account, including the removed member's own
        // device so it learns of the removal.
        final targets =
            members.map((m) => m.matrixId).whereType<String>().toSet();
        final transport = await w.transport;
        await transport.sendToUsers(
            targets, memberEventType, memberPayload(updated));
      });
}

/// What the group menu offers for a group (G9) — see [groupExitKind].
enum GroupExitKind {
  /// We are an active participant and other claimed accounts are active:
  /// mark ourselves removed for everyone, then drop the group locally.
  leave,

  /// Nobody else could be affected (solo / local-only group, or we're no
  /// longer an active participant anyway): drop the group from this device.
  delete,
}

/// Pure decision behind the group menu entry: **Leave** when this account is
/// an active participant and at least one *other* claimed account is active
/// (they must learn we left); otherwise **Delete** (purely local).
GroupExitKind groupExitKind(List<MemberModel> members, String myMxid) {
  final meActive = members.any((m) => m.isActive && m.matrixId == myMxid);
  final othersClaimed = members.any(
      (m) => m.isActive && m.matrixId != null && m.matrixId != myMxid);
  return meActive && othersClaimed ? GroupExitKind.leave : GroupExitKind.delete;
}

/// Leave / delete a group (G9). Both end with the group **purged** from the
/// local DB and a device-local [LeftGroupTombstone], so a late digest or
/// bootstrap from a peer (or our own other devices) can't resurrect it — only
/// being re-added (a newer `active` member record for our MXID) brings it back.
@riverpod
class GroupExiter extends _$GroupExiter {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Leaves [groupId]: our participant is marked `removed` (LWW) and relayed
  /// to every claimed account — peers see "X left", and our own other devices
  /// learn it too — then the group is purged locally. The relay is
  /// best-effort: if it fails (offline), the tombstone keeps our removal
  /// notice and re-sends it to any peer whose digest still lists us as active
  /// (SyncEngine rule 7), so the leave still reaches everyone eventually.
  Future<void> leave(String groupId) =>
      _runGroupWrite(ref, (s) => state = s, (w) async {
        final me = await w.myMxid();
        final members = await w.members.getMembers(groupId);
        final now = DateTime.now().millisecondsSinceEpoch;
        final self = members.where((m) => m.matrixId == me).firstOrNull;
        final removed =
            self == null ? null : _removedCopy(members, self.userId, now);
        if (removed != null) {
          await w.members.upsertMemberLww(memberCompanion(removed));
          final targets =
              members.map((m) => m.matrixId).whereType<String>().toSet();
          try {
            final result = await (await w.transport)
                .sendToUsers(targets, memberEventType, memberPayload(removed));
            if (!w.db.isClosed) w.health.reportDelivery(targets, result);
          } catch (e) {
            if (!w.db.isClosed) w.health.reportFailure(e);
          }
        }
        await _purge(w, groupId,
            LeftGroupTombstone(
              leftAt: removed?.updatedAt ?? now,
              removalNotice: removed == null ? null : memberPayload(removed),
            ));
      });

  /// Deletes [groupId] from this device only — nothing is sent. Meant for
  /// solo / local-only groups (see [groupExitKind]).
  Future<void> delete(String groupId) =>
      _runGroupWrite(ref, (s) => state = s, (w) async {
        await _purge(w, groupId,
            LeftGroupTombstone(leftAt: DateTime.now().millisecondsSinceEpoch));
      });

  static Future<void> _purge(
      _GroupWriteContext w, String groupId, LeftGroupTombstone t) async {
    if (w.db.isClosed) return; // account switched meanwhile — not ours to touch
    await w.db.transaction(() async {
      await w.db.purgeGroup(groupId);
      await w.settings.markGroupLeft(groupId, t);
    });
  }
}

/// Maps a [MemberModel] to a fully-populated companion (all columns set) for an
/// LWW upsert.
MembersCompanion memberCompanion(MemberModel m) => MembersCompanion(
      groupId: Value(m.groupId),
      userId: Value(m.userId),
      displayName: Value(m.displayName),
      matrixId: Value(m.matrixId),
      status: Value(m.status),
      updatedAt: Value(m.updatedAt),
    );
