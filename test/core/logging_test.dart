import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/logging.dart';

void main() {
  late DebugPrintCallback original;
  setUp(() => original = debugPrint);
  tearDown(() => debugPrint = original);

  test('debug / profile builds keep debugPrint', () {
    expect(silenceDebugPrintInRelease(release: false), isFalse);
    expect(identical(debugPrint, original), isTrue);
  });

  test('release builds drop every debugPrint message', () {
    final printed = <String?>[];
    debugPrint = (message, {wrapWidth}) => printed.add(message);
    expect(silenceDebugPrintInRelease(release: true), isTrue);
    debugPrint('[bg] @alice:example.org on https://matrix.example.org');
    debugPrint(null, wrapWidth: 80);
    expect(printed, isEmpty);
  });

  test('defaults to kReleaseMode (tests run in debug: no-op)', () {
    expect(silenceDebugPrintInRelease(), kReleaseMode);
  });
}
