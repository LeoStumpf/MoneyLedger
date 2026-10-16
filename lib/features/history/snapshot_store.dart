import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/demo/demo_mode.dart' show kOfflineDemo;
import 'snapshot_store_platform.dart';

/// G48: where the rotating snapshots of one ledger DB live. Native: the
/// directory `<app support>/snapshots/<db name>/` (`YYYY-MM-DD.json`
/// files, app-private — never leave the device, Android backup stays off,
/// G32). Web: none (see [snapshotStoreFactoryProvider]).
abstract class SnapshotStore {
  /// File names in the store (any order).
  Future<List<String>> list();
  Future<String> read(String name);

  /// Writes [name] atomically (temp file + rename).
  Future<void> write(String name, String content);
  Future<void> delete(String name);

  /// Removes the whole store (local data deleted / adopted).
  Future<void> deleteAll();
}

/// A [SnapshotStore] in memory — tests.
class InMemorySnapshotStore implements SnapshotStore {
  final files = <String, String>{};

  @override
  Future<List<String>> list() async => files.keys.toList();
  @override
  Future<String> read(String name) async =>
      files[name] ?? (throw StateError('no snapshot $name'));
  @override
  Future<void> write(String name, String content) async =>
      files[name] = content;
  @override
  Future<void> delete(String name) async => files.remove(name);
  @override
  Future<void> deleteAll() async => files.clear();
}

/// The snapshot store of the ledger DB called `dbName`, or null where there
/// are no snapshots: **web** (no file system — the in-DB version history,
/// G48, still allows resetting a group there) and the offline demo.
final snapshotStoreFactoryProvider =
    Provider<SnapshotStore? Function(String dbName)>(
      (ref) => kOfflineDemo ? (_) => null : createPlatformSnapshotStore,
    );

/// G48: local mode's ledger is gone (data deleted, or adopted into an
/// account) — its snapshots go too ([snapshots], best-effort) after
/// [deleteDb] (the DB files, G41). Returns [deleteDb]'s result.
Future<bool> deleteLedgerFilesAndSnapshots(
  Future<bool> Function() deleteDb,
  SnapshotStore? snapshots,
) async {
  final ok = await deleteDb();
  try {
    await snapshots?.deleteAll();
  } catch (e) {
    debugPrint('[history] deleting local snapshots failed: $e');
  }
  return ok;
}
