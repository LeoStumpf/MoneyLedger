import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Native: drift_flutter stores `<name>.sqlite` in the app documents dir.
Future<bool> databaseExists(String name) async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}${Platform.pathSeparator}$name.sqlite').exists();
}

/// Native: deletes `<name>.sqlite` and its journal / WAL side files (G36).
/// The database must be closed.
Future<void> deleteDatabase(String name) async {
  final dir = await getApplicationDocumentsDirectory();
  final base = '${dir.path}${Platform.pathSeparator}$name.sqlite';
  for (final suffix in const ['', '-journal', '-wal', '-shm']) {
    final f = File('$base$suffix');
    if (await f.exists()) await f.delete();
  }
}
