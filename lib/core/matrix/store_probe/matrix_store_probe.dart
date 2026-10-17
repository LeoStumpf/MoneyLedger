/// G79: "is there a Matrix SDK store on this device?" — without creating one.
/// Native: the store file `buildMatrixClient` opens; web: always false (the
/// store is IndexedDB; a web session from before the welcome existed shows
/// the welcome once — signing in again restores it).
library;

export 'matrix_store_probe_io.dart'
    if (dart.library.js_interop) 'matrix_store_probe_web.dart';
