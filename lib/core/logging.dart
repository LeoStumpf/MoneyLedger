import 'package:flutter/foundation.dart';

/// A [DebugPrintCallback] that drops every message.
void _silentDebugPrint(String? message, {int? wrapWidth}) {}

/// G44: release builds log nothing through [debugPrint] — the app's logs
/// name MXIDs, homeservers, group ids and errors, and logcat is readable by
/// anyone with adb (and by bug-report tools). Debug / profile builds keep
/// logging (`[bg]`, `[g6]`, `[watchdog]` … stay available for `adb logcat`).
///
/// Call it first thing in every isolate entry point (`main()`, the
/// WorkManager headless dispatcher) — [debugPrint] is a per-isolate global.
/// [release] defaults to [kReleaseMode]; tests pass it explicitly.
/// Returns whether [debugPrint] was silenced.
bool silenceDebugPrintInRelease({bool release = kReleaseMode}) {
  if (!release) return false;
  debugPrint = _silentDebugPrint;
  return true;
}
