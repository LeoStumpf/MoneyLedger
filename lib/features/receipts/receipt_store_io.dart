import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'receipt_store.dart';

/// Android: `<app support>/receipts/<dbName>/`. Other native platforms
/// (desktop, the test VM): none — receipt photos are Android only (G78).
ReceiptStore? Function(String dbName)? platformReceiptStoreFactory() =>
    Platform.isAndroid ? createFileReceiptStore : null;

/// The [FileReceiptStore] of the ledger DB [dbName].
ReceiptStore createFileReceiptStore(String dbName) => FileReceiptStore(
  () async => Directory(
    [
      (await getApplicationSupportDirectory()).path,
      'receipts',
      dbName,
    ].join(Platform.pathSeparator),
  ),
);

/// The image picker's own copy in the app cache (camera shot / gallery
/// copy) — deleted once the photo is stored, so it lives in one place.
Future<void> deletePickedFile(String path) async {
  final f = File(path);
  if (await f.exists()) await f.delete();
}

/// A [ReceiptStore] in one directory (created on the first write):
/// `<expense id>.jpg` per photo.
class FileReceiptStore implements ReceiptStore {
  FileReceiptStore(this._dir);

  final Future<Directory> Function() _dir;

  static const _suffix = '.jpg';

  Future<File> _file(String expenseId) async {
    if (!isValidReceiptId(expenseId)) {
      throw ArgumentError.value(expenseId, 'expenseId');
    }
    return File(
      '${(await _dir()).path}${Platform.pathSeparator}$expenseId$_suffix',
    );
  }

  @override
  Future<Set<String>> list() async {
    final dir = await _dir();
    if (!await dir.exists()) return const {};
    final out = <String>{};
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (name.endsWith('$_suffix.tmp')) {
        // A write that never finished (process killed) — not a photo.
        await e.delete();
      } else if (name.endsWith(_suffix)) {
        out.add(name.substring(0, name.length - _suffix.length));
      }
    }
    return out;
  }

  @override
  Future<Uint8List?> read(String expenseId) async {
    final f = await _file(expenseId);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(String expenseId, Uint8List bytes) async {
    final f = await _file(expenseId);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String expenseId) async {
    final f = await _file(expenseId);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> deleteAll() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
