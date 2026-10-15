import 'package:drift/wasm.dart';

/// Web: ask drift which databases exist (OPFS is always listed; passing
/// [name] makes drift also probe IndexedDB for it).
Future<bool> databaseExists(String name) async {
  final probe = await WasmDatabase.probe(
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
    databaseName: name,
  );
  return probe.existingDatabases.any((db) => db.$2 == name);
}
