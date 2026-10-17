/// Platform [ReceiptStore] factory: files on Android, none elsewhere.
library;

export 'receipt_store_io.dart'
    if (dart.library.js_interop) 'receipt_store_web.dart';
