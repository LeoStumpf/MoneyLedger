import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

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

/// Where a save went: [path] is what the platform reported (Android: the
/// saved document's path, see `savedFileDisplayName`; web: null — a browser
/// download has no path).
class SavedFile {
  final String? path;
  const SavedFile(this.path);
}

/// Saves [content] as [fileName] via the system save dialog (web: a browser
/// download). Returns null when the user cancelled the dialog.
Future<SavedFile?> saveTextFile(
  String fileName,
  String content,
  LedgerFileKind kind,
) async {
  final saved = await FilePicker.saveFile(
    fileName: fileName,
    bytes: utf8.encode(content),
    mimeType: kind.mimeType,
  );
  // Web (file_picker's default download mode) triggers a browser download and
  // always returns null — there is no dialog to cancel.
  if (kIsWeb) return const SavedFile(null);
  if (saved == null) return null;
  debugPrint('[backup] saved to $saved');
  return SavedFile(saved.path);
}

/// Prompts the user to pick a file of [kind] and returns its text, or null if
/// cancelled. Backups are picked without an extension filter: Android file
/// providers don't reliably map `.json` to a MIME type (a downloaded backup
/// may show up as `application/octet-stream`), and the parser rejects a wrong
/// file with a clear message anyway.
Future<String?> pickTextFile(LedgerFileKind kind) async {
  final filtered = kind != LedgerFileKind.backup;
  final file = await FilePicker.pickFile(
    type: filtered ? FileType.custom : FileType.any,
    allowedExtensions: filtered ? [kind.extension] : null,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  // A non-text file picked as a backup decodes to garbage the parser rejects.
  return utf8.decode(bytes, allowMalformed: !filtered);
}
