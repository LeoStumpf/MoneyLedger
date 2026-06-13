import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../core/sync/ledger_payloads.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../expenses/expenses_provider.dart';

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

@riverpod
class GroupCreator extends _$GroupCreator {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Creates a group locally (roomless): a fresh UUID id, with the creator as
  /// the first active member. Nothing is sent to Matrix — members are added (and
  /// the group replicated to them) via [MemberAdder].
  Future<void> create(String name, String currency) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final groupId = const Uuid().v7();
      final now = DateTime.now().millisecondsSinceEpoch;
      final me = (await ref.read(ledgerTransportProvider.future)).userId;
      await ref.read(groupsDaoProvider).upsertGroupLww(GroupsCompanion(
            roomId: Value(groupId),
            name: Value(name),
            currency: Value(currency),
            updatedAt: Value(now),
          ));
      // The creator is the first participant, claimed by their own account
      // (participant id == their MXID, the invariant for from-scratch users).
      await ref.read(membersDaoProvider).upsertMemberLww(memberCompanion(
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
}

@riverpod
class MemberAdder extends _$MemberAdder {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Adds [userId] (a Matrix ID) to the group: records them locally, sends them
  /// the whole group as a bootstrap payload ("send my friend the database"), and
  /// notifies existing members of the new member.
  Future<void> add(String groupId, String userId, {String? displayName}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _applyAdd(groupId, userId, displayName: displayName));
  }

  Future<void> _applyAdd(String groupId, String userId,
      {String? displayName}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final memberDao = ref.read(membersDaoProvider);
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
    await memberDao.upsertMemberLww(memberCompanion(member));

    final transport = await ref.read(ledgerTransportProvider.future);

    // 1) Bootstrap the new member with the full group state + ledger.
    await transport.sendToUsers(
        {userId}, bootstrapEventType, await _buildBootstrap(groupId));

    // 2) Tell the existing active members about the new member.
    final others = (await memberDao.activeClaimedMatrixIds(groupId))
        .where((m) => m != userId)
        .toSet();
    await transport.sendToUsers(others, memberEventType, memberPayload(member));
  }

  /// Shares the whole group with a Matrix account **without** assigning them a
  /// participant — they receive the bootstrap and then pick which existing
  /// participant they are (self-claim on join, [selfClaim]). Use this to invite
  /// someone who already has a local placeholder in the ledger.
  Future<void> invite(String groupId, String matrixId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final transport = await ref.read(ledgerTransportProvider.future);
      await transport.sendToUsers(
          {matrixId}, bootstrapEventType, await _buildBootstrap(groupId));
    });
  }

  /// Adds a Tricount-style local participant: a named person with no Matrix
  /// account (a fresh UUID participant id, `matrixId == null`). They are pure
  /// ledger data — relayed to the claimed members so everyone sees them, but
  /// never a sync target until someone claims the slot.
  Future<void> addLocal(String groupId, String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final member = MemberModel(
        groupId: groupId,
        userId: const Uuid().v7(),
        displayName: name,
        matrixId: null,
        status: 'active',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await ref.read(membersDaoProvider).upsertMemberLww(memberCompanion(member));
      await _relayToClaimed(groupId, member);
    });
  }

  /// Renames a participant (LWW edit), then replicates.
  Future<void> rename(String groupId, String participantId, String name) =>
      _editParticipant(groupId, participantId,
          (m) => _copyWith(m, displayName: name));

  /// Claims a (typically local) participant for the Matrix account [matrixId]:
  /// links the account to the existing ledger identity, keeping all history.
  /// Bootstraps that account with the whole group (they may not have it yet).
  Future<void> claim(
      String groupId, String participantId, String matrixId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _applyClaim(groupId, participantId, matrixId));
  }

  Future<void> _applyClaim(
      String groupId, String participantId, String matrixId) async {
    final memberDao = ref.read(membersDaoProvider);
    final current = _find(await memberDao.getMembers(groupId), participantId);
    if (current == null) return;
    final updated = _copyWith(current, matrixId: matrixId);
    await memberDao.upsertMemberLww(memberCompanion(updated));
    final transport = await ref.read(ledgerTransportProvider.future);
    await transport.sendToUsers(
        {matrixId}, bootstrapEventType, await _buildBootstrap(groupId));
    final targets = (await memberDao.activeClaimedMatrixIds(groupId)).toSet();
    await transport.sendToUsers(
        targets, memberEventType, memberPayload(updated));
  }

  /// Claims an existing participant as **this device's own account** — the
  /// "self-claim on join" of open-points #7. Used when you've been invited to a
  /// group ([invite]) and recognise yourself as one of the existing
  /// participants; links your MXID and replicates so everyone sees the claim.
  Future<void> selfClaim(String groupId, String participantId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final me = (await ref.read(ledgerTransportProvider.future)).userId;
      await _applyClaim(groupId, participantId, me);
    });
  }

  /// Joins a group you were invited to as a brand-new participant (you are not
  /// any of the existing local people) — creates a self-participant and tells
  /// the others.
  Future<void> joinAsNew(String groupId, String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final me = (await ref.read(ledgerTransportProvider.future)).userId;
      await _applyAdd(groupId, me, displayName: name);
    });
  }

  /// Detaches the Matrix account from a participant (the "remove account" of
  /// open-points #7) — the participant and their history stay; only the claim
  /// is cleared. Relays to the remaining members and to the detached account's
  /// own device so it learns it is no longer linked.
  Future<void> unclaim(String groupId, String participantId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final memberDao = ref.read(membersDaoProvider);
      final current = _find(await memberDao.getMembers(groupId), participantId);
      if (current == null || current.matrixId == null) return;
      final detached = current.matrixId!;
      final updated = _copyWith(current, matrixId: null);
      await memberDao.upsertMemberLww(memberCompanion(updated));
      final targets = (await memberDao.activeClaimedMatrixIds(groupId)).toSet()
        ..add(detached);
      final transport = await ref.read(ledgerTransportProvider.future);
      await transport.sendToUsers(
          targets, memberEventType, memberPayload(updated));
    });
  }

  Future<void> _editParticipant(String groupId, String participantId,
      MemberModel Function(MemberModel) edit) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final memberDao = ref.read(membersDaoProvider);
      final current = _find(await memberDao.getMembers(groupId), participantId);
      if (current == null) return;
      final updated = edit(current);
      await memberDao.upsertMemberLww(memberCompanion(updated));
      await _relayToClaimed(groupId, updated);
    });
  }

  Future<void> _relayToClaimed(String groupId, MemberModel member) async {
    final transport = await ref.read(ledgerTransportProvider.future);
    final targets =
        (await ref.read(membersDaoProvider).activeClaimedMatrixIds(groupId))
            .toSet();
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

  Future<Map<String, dynamic>> _buildBootstrap(String groupId) async {
    final expDao = ref.read(expensesDaoProvider);
    return buildBootstrapContent(
      groupId,
      await ref.read(groupsDaoProvider).getGroup(groupId),
      await ref.read(membersDaoProvider).getMembers(groupId),
      // Tombstones included: the new member must learn about deletions too,
      // or they would re-gossip dead records via anti-entropy.
      await expDao.getAllExpensesForGroup(groupId),
      await expDao.getAllSettlementsForGroup(groupId),
    );
  }
}

/// Sentinel for [_copyWith] so `matrixId: null` (unclaim) is distinguishable
/// from "leave unchanged".
const Object _unset = Object();

@riverpod
class MemberRemover extends _$MemberRemover {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Marks [userId] removed (last-writer-wins) and relays the change. Their
  /// expense history stays in Drift, so balances are preserved — only their
  /// membership status changes. The removed user is included in the relay so
  /// their own device updates too.
  Future<void> remove(String groupId, String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final memberDao = ref.read(membersDaoProvider);
      final members = await memberDao.getMembers(groupId);
      MemberModel? current;
      for (final m in members) {
        if (m.userId == userId) {
          current = m;
          break;
        }
      }
      if (current == null) return;
      // Keep the participant's identity (name + claim) — only flip status, so
      // their history stays attributed and the relay doesn't wipe peers' copies.
      final updated = MemberModel(
        groupId: groupId,
        userId: userId,
        displayName: current.displayName,
        matrixId: current.matrixId,
        status: 'removed',
        updatedAt: now,
      );
      await memberDao.upsertMemberLww(memberCompanion(updated));
      // Relay to every claimed account, including the removed member's own
      // device so it learns of the removal.
      final targets =
          members.map((m) => m.matrixId).whereType<String>().toSet();
      final transport = await ref.read(ledgerTransportProvider.future);
      await transport.sendToUsers(
          targets, memberEventType, memberPayload(updated));
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
