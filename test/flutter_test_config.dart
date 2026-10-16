import 'package:drift/drift.dart';

// Runs once before every test file in this directory tree.
// sqlite3 3.x loads its native library through build hooks (bundled by
// `flutter test` itself), so Drift's NativeDatabase.memory() needs no
// DynamicLibrary override and no system-installed sqlite3.
Future<void> testExecutable(Future<void> Function() testMain) async {
  // Tests open many independent in-memory databases (one per ProviderContainer),
  // which is intentional — silence Drift's multi-instance warning.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}
