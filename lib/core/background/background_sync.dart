/// Platform switch for the background-sync glue (G31): the Android/native
/// implementation (WorkManager + Matrix) or the web stub (no background sync).
library;

export 'background_sync_stub.dart'
    if (dart.library.io) 'background_sync_native.dart';
