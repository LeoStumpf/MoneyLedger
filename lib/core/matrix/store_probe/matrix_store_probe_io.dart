import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../matrix_store_name.dart';

/// Whether `<app support>/money_ledger_matrix.sqlite` exists (G79).
Future<bool> matrixStoreExists() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/$kMatrixStoreName.sqlite').exists();
}
