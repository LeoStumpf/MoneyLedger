/// G69: share plain text through the system share sheet (`share_plus`,
/// BSD-3) — Android's chooser, the browser's Web Share API. Nothing goes
/// through a server of ours; the user picks the app. G52 reuses it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Hands [text] to the system share sheet. Returns false when there is
/// none (e.g. a desktop browser without the Web Share API — share_plus
/// throws there, its mailto fallback is off).
typedef TextSharer = Future<bool> Function(String text, {String? subject});

Future<bool> shareTextViaSystem(String text, {String? subject}) async {
  try {
    // On the web a finished share reports `unavailable` too; only a throw
    // means "no share sheet".
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    return true;
  } catch (e) {
    debugPrint('[share] system share unavailable: $e');
    return false;
  }
}

/// Test seam: widget tests override it with a recorder.
final textSharerProvider = Provider<TextSharer>((ref) => shareTextViaSystem);

/// The outcome of [shareOrCopy].
enum ShareOutcome { shared, copied }

/// Shares [text] — or, with no share sheet, copies it to the clipboard so
/// the user can paste it (the caller says so in a snackbar).
Future<ShareOutcome> shareOrCopy(
  TextSharer sharer,
  String text, {
  String? subject,
}) async {
  if (await sharer(text, subject: subject)) return ShareOutcome.shared;
  await Clipboard.setData(ClipboardData(text: text));
  return ShareOutcome.copied;
}
