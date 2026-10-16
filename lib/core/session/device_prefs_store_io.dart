import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'device_prefs.dart';

/// Native: `device_prefs.json` in the app support directory (next to the
/// Matrix store; excluded from Android backups like all app data, G32).
DevicePrefsStore createPlatformDevicePrefsStore() => FileDevicePrefsStore(
  () async => File(
    '${(await getApplicationSupportDirectory()).path}'
    '${Platform.pathSeparator}device_prefs.json',
  ),
);

/// A [DevicePrefsStore] backed by one small JSON file. Writes go to a
/// temporary file that is then renamed over the real one, so a crash never
/// leaves a half-written file.
class FileDevicePrefsStore implements DevicePrefsStore {
  FileDevicePrefsStore(this._file);

  final Future<File> Function() _file;

  @override
  Future<Map<String, String>> load() async {
    final f = await _file();
    if (!await f.exists()) return {};
    final decoded = jsonDecode(await f.readAsString());
    if (decoded is! Map<String, dynamic>) return {};
    return {
      for (final e in decoded.entries)
        if (e.value is String) e.key: e.value as String,
    };
  }

  @override
  Future<void> save(Map<String, String> values) async {
    final f = await _file();
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(values), flush: true);
    await tmp.rename(f.path);
  }
}
