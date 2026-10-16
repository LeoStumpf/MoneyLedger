import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../../models/sync_state_model.dart';

part 'sync_states_dao.g.dart';

@DriftAccessor(tables: [PeerSyncStates])
class SyncStatesDao extends DatabaseAccessor<AppDatabase>
    with _$SyncStatesDaoMixin {
  SyncStatesDao(super.db);

  Stream<List<PeerSyncStateModel>> watchSyncStates(String groupId) =>
      (select(peerSyncStates)..where((t) => t.groupId.equals(groupId)))
          .watch()
          .map((rows) => rows.map(_toModel).toList());

  Future<List<PeerSyncStateModel>> getSyncStates(String groupId) =>
      (select(peerSyncStates)..where((t) => t.groupId.equals(groupId)))
          .get()
          .then((rows) => rows.map(_toModel).toList());

  Future<void> upsertSyncState(PeerSyncStatesCompanion state) =>
      into(peerSyncStates).insertOnConflictUpdate(state);

  /// Records that [userId] was proven to hold our whole state for [groupId]
  /// at [at] (a matching digest, or the G29 inbound-record proof). Monotonic:
  /// never moves an existing `lastInSyncAt` backwards.
  Future<void> markInSync(String groupId, String userId, int at) =>
      transaction(() async {
        final existing =
            await (select(peerSyncStates)..where(
                  (t) => t.groupId.equals(groupId) & t.userId.equals(userId),
                ))
                .getSingleOrNull();
        if (existing != null && existing.lastInSyncAt >= at) return;
        await upsertSyncState(
          PeerSyncStatesCompanion(
            groupId: Value(groupId),
            userId: Value(userId),
            lastInSyncAt: Value(at),
          ),
        );
      });

  Future<void> markDigestSent(String groupId, String userId, int at) =>
      upsertSyncState(
        PeerSyncStatesCompanion(
          groupId: Value(groupId),
          userId: Value(userId),
          lastDigestSentAt: Value(at),
        ),
      );

  /// When this device last sent a digest to anyone, for any group (ms epoch;
  /// 0 if never). The background round (G31) only broadcasts its own digests
  /// when this is older than the background period.
  Future<int> latestDigestSentAt() async {
    final latest = peerSyncStates.lastDigestSentAt.max();
    final row = await (selectOnly(
      peerSyncStates,
    )..addColumns([latest])).getSingle();
    return row.read(latest) ?? 0;
  }

  static PeerSyncStateModel _toModel(PeerSyncState s) => PeerSyncStateModel(
    groupId: s.groupId,
    userId: s.userId,
    lastInSyncAt: s.lastInSyncAt,
    lastDigestSentAt: s.lastDigestSentAt,
  );
}
