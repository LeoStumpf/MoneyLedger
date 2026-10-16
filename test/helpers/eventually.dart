import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Polls [condition] on the **real** event loop until it holds — the
/// load-independent replacement for "wait a fixed 50 ms and hope the Drift
/// write finished" (G15). In a widget test call it inside
/// `tester.runAsync` and pass [tester] so each round also pumps a frame
/// (e.g. to build a dialog shown after an async lookup). Fails the test after
/// [timeout] (a generous bound — only reached when the condition never holds).
Future<void> eventually(
  FutureOr<bool> Function() condition, {
  WidgetTester? tester,
  Duration timeout = const Duration(seconds: 10),
  String? reason,
}) async {
  final sw = Stopwatch()..start();
  while (true) {
    if (tester != null) await tester.pump();
    if (await condition()) return;
    if (sw.elapsed > timeout) {
      fail(
        'condition not met within $timeout${reason == null ? '' : ': $reason'}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}
