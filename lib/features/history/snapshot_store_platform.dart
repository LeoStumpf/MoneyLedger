/// Platform [SnapshotStore] factory: files on native, none on web.
library;

export 'snapshot_store_io.dart'
    if (dart.library.js_interop) 'snapshot_store_web.dart';
