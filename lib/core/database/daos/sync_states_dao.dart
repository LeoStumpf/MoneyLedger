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

  /// Records that a digest from [userId] matched our state for [groupId].
  Future<void> markInSync(String groupId, String userId, int at) =>
      upsertSyncState(PeerSyncStatesCompanion(
        groupId: Value(groupId),
        userId: Value(userId),
        lastInSyncAt: Value(at),
      ));

  Future<void> markDigestSent(String groupId, String userId, int at) =>
      upsertSyncState(PeerSyncStatesCompanion(
        groupId: Value(groupId),
        userId: Value(userId),
        lastDigestSentAt: Value(at),
      ));

  static PeerSyncStateModel _toModel(PeerSyncState s) => PeerSyncStateModel(
        groupId: s.groupId,
        userId: s.userId,
        lastInSyncAt: s.lastInSyncAt,
        lastDigestSentAt: s.lastDigestSentAt,
      );
}
