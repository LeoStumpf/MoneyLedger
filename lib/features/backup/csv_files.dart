import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// Thin platform glue around the system file dialogs (web download / native
/// save + picker). Not unit-tested — the CSV building/parsing it wraps is
/// covered by `ledger_csv`, `csv_export` and `csv_import` tests; this is
/// manual-smoke only, like the SSO deep-link path.

/// Saves [content] as a `.csv` via the system save dialog (web: downloads it).
Future<void> saveCsvFile(String fileName, String content) async {
  await FilePicker.platform.saveFile(
    fileName: fileName,
    bytes: utf8.encode(content),
    type: FileType.custom,
    allowedExtensions: const ['csv'],
  );
}

/// Prompts the user to pick a `.csv` and returns its text, or null if cancelled.
Future<String?> pickCsvText() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['csv'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final bytes = result.files.first.bytes;
  return bytes == null ? null : utf8.decode(bytes);
}
