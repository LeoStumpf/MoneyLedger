import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'snapshot_store.dart';

/// Native: `<app support>/snapshots/<dbName>/`.
SnapshotStore? createPlatformSnapshotStore(String dbName) => FileSnapshotStore(
  () async => Directory(
    [
      (await getApplicationSupportDirectory()).path,
      'snapshots',
      dbName,
    ].join(Platform.pathSeparator),
  ),
);

/// A [SnapshotStore] in one directory (created on the first write).
class FileSnapshotStore implements SnapshotStore {
  FileSnapshotStore(this._dir);

  final Future<Directory> Function() _dir;

  Future<File> _file(String name) async {
    if (name.contains('/') || name.contains(r'\') || name.startsWith('.')) {
      throw ArgumentError.value(name, 'name');
    }
    return File('${(await _dir()).path}${Platform.pathSeparator}$name');
  }

  @override
  Future<List<String>> list() async {
    final dir = await _dir();
    if (!await dir.exists()) return const [];
    return [
      await for (final e in dir.list())
        if (e is File) e.uri.pathSegments.last,
    ];
  }

  @override
  Future<String> read(String name) async => (await _file(name)).readAsString();

  @override
  Future<void> write(String name, String content) async {
    final f = await _file(name);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String name) async {
    final f = await _file(name);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> deleteAll() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
