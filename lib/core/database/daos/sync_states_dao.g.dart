// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_states_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncStatesDaoMixin on DatabaseAccessor<AppDatabase> {
  $PeerSyncStatesTable get peerSyncStates => attachedDatabase.peerSyncStates;
  SyncStatesDaoManager get managers => SyncStatesDaoManager(this);
}

class SyncStatesDaoManager {
  final _$SyncStatesDaoMixin _db;
  SyncStatesDaoManager(this._db);
  $$PeerSyncStatesTableTableManager get peerSyncStates =>
      $$PeerSyncStatesTableTableManager(
        _db.attachedDatabase,
        _db.peerSyncStates,
      );
}
