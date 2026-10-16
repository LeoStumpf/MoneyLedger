import 'package:drift/wasm.dart';

Future<WasmProbeResult> _probe(String name) => WasmDatabase.probe(
  sqlite3Uri: Uri.parse('sqlite3.wasm'),
  driftWorkerUri: Uri.parse('drift_worker.js'),
  databaseName: name,
);

/// Web: ask drift which databases exist (OPFS is always listed; passing
/// [name] makes drift also probe IndexedDB for it).
Future<bool> databaseExists(String name) async {
  final probe = await _probe(name);
  return probe.existingDatabases.any((db) => db.$2 == name);
}

/// Web: deletes every stored copy of the database [name] (G36). The database
/// must be closed.
Future<void> deleteDatabase(String name) async {
  final probe = await _probe(name);
  for (final db in probe.existingDatabases.where((db) => db.$2 == name)) {
    await probe.deleteDatabase(db);
  }
}
