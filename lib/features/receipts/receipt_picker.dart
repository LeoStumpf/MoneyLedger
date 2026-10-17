import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'receipt_store_platform.dart' show deletePickedFile;

/// Where a receipt photo comes from.
enum ReceiptSource { camera, gallery }

/// G78: long edge of a stored receipt photo (px) — enough to read a
/// receipt, ~200–400 KB as JPEG.
const kReceiptMaxEdge = 1600.0;

/// G78: JPEG quality of a stored receipt photo.
const kReceiptJpegQuality = 80;

/// Takes / picks one photo and returns its (downscaled, recompressed)
/// bytes, or null when the user cancelled. Injectable — tests return bytes.
typedef ReceiptPicker = Future<Uint8List?> Function(ReceiptSource source);

final receiptPickerProvider = Provider<ReceiptPicker>(
  (ref) => pickReceiptPhoto,
);

/// The real picker: `image_picker` — on Android the system camera app
/// (an intent: no CAMERA permission, the app never sees the camera) or the
/// system photo picker / file chooser (no storage permission). It scales
/// to [kReceiptMaxEdge] and recompresses to [kReceiptJpegQuality] natively;
/// its own copy in the app cache is deleted once read.
Future<Uint8List?> pickReceiptPhoto(ReceiptSource source) async {
  final file = await ImagePicker().pickImage(
    source: source == ReceiptSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    maxWidth: kReceiptMaxEdge,
    maxHeight: kReceiptMaxEdge,
    imageQuality: kReceiptJpegQuality,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  try {
    return await file.readAsBytes();
  } finally {
    try {
      await deletePickedFile(file.path);
    } catch (e) {
      debugPrint('[receipts] picker temp file not deleted: $e');
    }
  }
}
