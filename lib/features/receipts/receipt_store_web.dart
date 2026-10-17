import 'receipt_store.dart';

/// Web: no receipt photos (G78 decision — Android only).
ReceiptStore? Function(String dbName)? platformReceiptStoreFactory() => null;

/// Web: the picker's file needs no cleanup (never offered there anyway).
Future<void> deletePickedFile(String path) async {}
