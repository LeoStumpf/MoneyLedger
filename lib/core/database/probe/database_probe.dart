/// Platform-specific "does a drift database called `name` already exist?"
/// check, used to adopt the legacy single-file ledger without creating an
/// empty one as a side effect of probing.
library;

export 'database_probe_io.dart'
    if (dart.library.js_interop) 'database_probe_web.dart';
