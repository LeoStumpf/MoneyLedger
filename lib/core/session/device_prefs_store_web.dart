import 'dart:convert';

import 'package:web/web.dart' as web;

import 'device_prefs.dart';

/// Web: one `localStorage` entry (per origin, like the ledger's OPFS /
/// IndexedDB storage).
DevicePrefsStore createPlatformDevicePrefsStore() => _LocalStorageStore();

class _LocalStorageStore implements DevicePrefsStore {
  static const _key = 'moneyledger_device_prefs';

  @override
  Future<Map<String, String>> load() async {
    final raw = web.window.localStorage.getItem(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return {};
    return {
      for (final e in decoded.entries)
        if (e.value is String) e.key: e.value as String,
    };
  }

  @override
  Future<void> save(Map<String, String> values) async =>
      web.window.localStorage.setItem(_key, jsonEncode(values));
}
