import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

// Runs once before every test file in this directory tree.
// Points the sqlite3 package at the native library bundled by the build hooks
// so Drift's NativeDatabase.memory() works without a system-installed sqlite3.
Future<void> testExecutable(Future<void> Function() testMain) async {
  final libPath = _findSqlite3();
  if (libPath != null) {
    open.overrideForAll(() => DynamicLibrary.open(libPath));
  }
  await testMain();
}

String? _findSqlite3() {
  // Prefer the library bundled by the build hooks (populated by `flutter pub get`)
  final bundled = '.dart_tool/hooks_runner/shared/sqlite3/build/download-1630fa31/libsqlite3.so';
  if (File(bundled).existsSync()) return bundled;
  // Fall back to system sqlite3 (present on most Linux distros)
  return null;
}
