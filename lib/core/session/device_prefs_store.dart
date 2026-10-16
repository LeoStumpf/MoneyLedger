/// Platform [DevicePrefsStore] factory: a JSON file on native, one
/// `localStorage` entry on web.
library;

export 'device_prefs_store_io.dart'
    if (dart.library.js_interop) 'device_prefs_store_web.dart';
