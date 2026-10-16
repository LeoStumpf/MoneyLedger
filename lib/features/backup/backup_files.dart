import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'download/web_download.dart';

/// Thin platform glue around the system file dialogs (web download / native
/// save + picker), shared by the CSV export/import and the full JSON backup
/// (G5). Not unit-tested — the building/parsing it wraps is covered by the
/// `ledger_csv`, `csv_*` and `ledger_backup` / `backup_service` tests; this is
/// manual-smoke only, like the SSO deep-link path.

/// A kind of text file the app saves and opens.
enum LedgerFileKind {
  csv('csv', 'text/csv'),
  backup('json', 'application/json');

  final String extension;
  final String mimeType;
  const LedgerFileKind(this.extension, this.mimeType);
}

/// Saves [content] as [fileName] via the system save dialog (web: a browser
/// download). Returns false when the user cancelled the dialog.
Future<bool> saveTextFile(
  String fileName,
  String content,
  LedgerFileKind kind,
) async {
  final bytes = utf8.encode(content);
  if (kIsWeb) {
    await downloadFile(fileName, bytes, kind.mimeType);
    return true;
  }
  final path = await FilePicker.platform.saveFile(
    fileName: fileName,
    bytes: bytes,
    type: FileType.custom,
    allowedExtensions: [kind.extension],
  );
  return path != null;
}

/// Prompts the user to pick a file of [kind] and returns its text, or null if
/// cancelled. Backups are picked without an extension filter: Android file
/// providers don't reliably map `.json` to a MIME type (a downloaded backup
/// may show up as `application/octet-stream`), and the parser rejects a wrong
/// file with a clear message anyway.
Future<String?> pickTextFile(LedgerFileKind kind) async {
  final filtered = kind != LedgerFileKind.backup;
  final result = await FilePicker.platform.pickFiles(
    type: filtered ? FileType.custom : FileType.any,
    allowedExtensions: filtered ? [kind.extension] : null,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final bytes = result.files.first.bytes;
  // A non-text file picked as a backup decodes to garbage the parser rejects.
  return bytes == null ? null : utf8.decode(bytes, allowMalformed: !filtered);
}
