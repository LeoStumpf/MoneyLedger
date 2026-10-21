import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/expenses/expenses_provider.dart';
import '../../features/groups/group_provider.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../../models/sync_state_model.dart';
import 'record_validation.dart' show isValidMxid;

part 'sync_status_provider.g.dart';

/// Whether a group's ledger is provably replicated to every active peer, and at
/// what point each peer was last known to be in sync. Derived purely from the
/// `PeerSyncStates` written by the anti-entropy engine (a matching digest from a
/// peer at time T proves they had every record that existed at T).
class GroupSyncStatus {
  /// Active peers (self excluded) not yet known to hold our newest record.
  final Set<String> pendingPeers;

  /// The smallest `lastInSyncAt` over all active peers; `null` when the group
  /// has no peers (solo group — nothing can be pending).
  final int? minPeerInSyncAt;

  /// G68: when each peer (MXID — our own account too, for our other
  /// devices) was last proven in sync (ms epoch) — the sync sheet's rows.
  final Map<String, int> peerInSyncAt;

  /// G68: the newest record clock of the group (a peer in sync at or after
  /// it has everything).
  final int maxRecordUpdatedAt;

  const GroupSyncStatus({
    required this.pendingPeers,
    required this.minPeerInSyncAt,
    this.peerInSyncAt = const {},
    this.maxRecordUpdatedAt = 0,
  });

  /// True once every active peer has acknowledged our latest record (or there
  /// are no peers at all).
  bool get synced => pendingPeers.isEmpty;

  /// Whether a record with [recordUpdatedAt] is not yet provably replicated to
  /// every active peer. With no peers, nothing is pending.
  bool isRecordPending(int recordUpdatedAt) =>
      minPeerInSyncAt != null && recordUpdatedAt > minPeerInSyncAt!;
}

/// Pure status computation (plain Dart, unit-testable without a DB).
@visibleForTesting
GroupSyncStatus computeSyncStatus({
  required String selfId,
  required List<MemberModel> members,
  required Map<String, int> peerInSyncAt,
  required int maxRecordUpdatedAt,
}) {
  // Peers are the *claimed* participants reachable by Matrix account, minus
  // self; pure-local participants can't sync, so they never count as pending.
  final activePeers = [
    for (final m in members)
      if (m.isActive && isValidMxid(m.matrixId) && m.matrixId != selfId)
        m.matrixId!,
  ];
  if (activePeers.isEmpty) {
    return GroupSyncStatus(
      pendingPeers: const {},
      minPeerInSyncAt: null,
      peerInSyncAt: peerInSyncAt,
      maxRecordUpdatedAt: maxRecordUpdatedAt,
    );
  }
  final pending = <String>{};
  int? minInSync;
  for (final p in activePeers) {
    final at = peerInSyncAt[p] ?? 0;
    if (at < maxRecordUpdatedAt) pending.add(p);
    minInSync = (minInSync == null || at < minInSync) ? at : minInSync;
  }
  return GroupSyncStatus(
    pendingPeers: pending,
    minPeerInSyncAt: minInSync,
    peerInSyncAt: peerInSyncAt,
    maxRecordUpdatedAt: maxRecordUpdatedAt,
  );
}

@riverpod
Stream<List<PeerSyncStateModel>> peerSyncStates(Ref ref, String groupId) =>
    ref.watch(syncStatesDaoProvider).watchSyncStates(groupId);

@riverpod
Stream<List<ExpenseModel>> allExpensesForGroup(Ref ref, String groupId) =>
    ref.watch(expensesDaoProvider).watchAllExpensesForGroup(groupId);

@riverpod
Stream<List<SettlementModel>> allSettlementsForGroup(Ref ref, String groupId) =>
    ref.watch(expensesDaoProvider).watchAllSettlementsForGroup(groupId);

/// Reactive sync status for one group: recomputes whenever members, peer sync
/// state, or any record (including tombstones) changes.
@riverpod
GroupSyncStatus groupSyncStatus(Ref ref, String groupId) {
  final self = ref.watch(currentUserIdProvider);
  final members =
      ref.watch(groupMembersProvider(groupId)).value ?? const <MemberModel>[];
  final syncStates =
      ref.watch(peerSyncStatesProvider(groupId)).value ??
      const <PeerSyncStateModel>[];
  final expenses =
      ref.watch(allExpensesForGroupProvider(groupId)).value ??
      const <ExpenseModel>[];
  final settlements =
      ref.watch(allSettlementsForGroupProvider(groupId)).value ??
      const <SettlementModel>[];
  final groups = ref.watch(ledgerGroupsProvider).value ?? const <GroupModel>[];

  var maxUpdated = 0;
  for (final g in groups) {
    if (g.roomId == groupId && g.updatedAt > maxUpdated) {
      maxUpdated = g.updatedAt;
    }
  }
  for (final m in members) {
    if (m.updatedAt > maxUpdated) maxUpdated = m.updatedAt;
  }
  for (final e in expenses) {
    if (e.updatedAt > maxUpdated) maxUpdated = e.updatedAt;
  }
  for (final s in settlements) {
    if (s.updatedAt > maxUpdated) maxUpdated = s.updatedAt;
  }

  return computeSyncStatus(
    selfId: self,
    members: members,
    peerInSyncAt: {for (final s in syncStates) s.userId: s.lastInSyncAt},
    maxRecordUpdatedAt: maxUpdated,
  );
}
