/// Fast convergence proof for the sync-status UI (G29). Plain Dart.
///
/// Rule 4 of `SyncEngine` marks a peer in sync only when a full digest
/// round-trip matches — after a peer's own change that costs the poke
/// debounce plus two relay hops (several seconds each on a public
/// homeserver), so the peer showed as "Waiting for …" although we already
/// held exactly its state. An **inbound record** can prove the same thing
/// earlier: if, at our last proven sync point with peer P, P held everything
/// we had, and every record we hold that is newer than that point is one P
/// itself sent us (at exactly the revision we store), then P holds every
/// record we hold — P is in sync, no round-trip needed.
///
/// Conservative by construction: any newer record P is not known to hold
/// (our own local write, something gossiped by a third member, a bootstrap,
/// a clamped clock) blocks the proof, and the regular digest exchange decides.
library;

import '../../models/expense_model.dart';
import '../matrix/ledger_transport.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';

/// Record keys used by [LocalRecordClocks] / [PeerConvergenceTracker].
String groupMetaKey() => 'g';
String memberKey(String participantId) => 'm:$participantId';
String expenseKey(String id) => 'e:$id';
String settlementKey(String id) => 's:$id';

/// Every record of one group as `key → updatedAt` (tombstones included).
Map<String, int> localRecordClocks({
  required GroupModel? group,
  required List<MemberModel> members,
  required List<ExpenseModel> expenses,
  required List<SettlementModel> settlements,
}) =>
    {
      if (group != null) groupMetaKey(): group.updatedAt,
      for (final m in members) memberKey(m.userId): m.updatedAt,
      for (final e in expenses) expenseKey(e.id): e.updatedAt,
      for (final s in settlements) settlementKey(s.id): s.updatedAt,
    };

/// Whether the peer provably holds every record in [local]: everything up to
/// [inSyncAt] was proven by an earlier sync, and every record newer than that
/// is in [heldByPeer] at exactly the revision we store.
bool peerHoldsEverything({
  required Map<String, int> local,
  required int inSyncAt,
  required Map<String, int> heldByPeer,
}) {
  for (final e in local.entries) {
    if (e.value <= inSyncAt) continue;
    if (heldByPeer[e.key] != e.value) return false;
  }
  return true;
}

/// Remembers, per (group, peer MXID), which record revisions that peer sent us
/// — i.e. records the peer is known to hold. In memory only: after a restart
/// the regular digest exchange proves convergence instead.
class PeerConvergenceTracker {
  final Map<String, Map<String, Map<String, int>>> _held = {};

  /// Notes that [peer] sent us record [key] at revision [updatedAt].
  void noteHeld(String groupId, String peer, String key, int updatedAt) {
    final byKey = (_held[groupId] ??= {})[peer] ??= {};
    final prev = byKey[key];
    if (prev == null || updatedAt > prev) byKey[key] = updatedAt;
  }

  /// The records [peer] is known to hold in [groupId] (read-only view).
  Map<String, int> heldBy(String groupId, String peer) =>
      _held[groupId]?[peer] ?? const {};

  /// Drops entries already covered by a sync point at [inSyncAt] (bounds the
  /// memory to records newer than the last proof).
  void prune(String groupId, String peer, int inSyncAt) =>
      _held[groupId]?[peer]?.removeWhere((_, v) => v <= inSyncAt);
}

/// The record key + revision an inbound record payload of [type] carries, or
/// null for payloads that aren't a single record (bootstrap, digest, …).
({String key, int updatedAt})? inboundRecordRevision(
    String type, Map<String, dynamic> content) {
  final at = content['updated_at'];
  if (at is! int) return null;
  if (type == expenseEventType || type == settlementEventType) {
    final id = content['id'] as String?;
    if (id == null) return null;
    return (
      key: type == expenseEventType ? expenseKey(id) : settlementKey(id),
      updatedAt: at
    );
  }
  if (type == groupMetaEventType) return (key: groupMetaKey(), updatedAt: at);
  if (type == memberEventType) {
    final pid =
        content['participant_id'] as String? ?? content['user'] as String?;
    if (pid == null) return null;
    return (key: memberKey(pid), updatedAt: at);
  }
  return null;
}
