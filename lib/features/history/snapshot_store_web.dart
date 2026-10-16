import 'snapshot_store.dart';

/// Web: no snapshots (G48 decision — see `snapshotStoreFactoryProvider`).
SnapshotStore? createPlatformSnapshotStore(String dbName) => null;
