import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// G38: the Android app id is permanent once uploaded to Play — pin it, the
/// Kotlin package of `MainActivity` and the background-sync names that
/// follow it.
void main() {
  const appId = 'io.github.leostumpf.moneyledger';

  test('namespace and applicationId are the app id', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('namespace = "$appId"'));
    expect(gradle, contains('applicationId = "$appId"'));
  });

  test('MainActivity lives in the app id package', () {
    final activity = File(
      'android/app/src/main/kotlin/io/github/leostumpf/moneyledger/'
      'MainActivity.kt',
    );
    expect(activity.existsSync(), isTrue);
    expect(activity.readAsStringSync(), startsWith('package $appId\n'));
  });

  test('no reference to the old app id is left in the app', () {
    for (final dir in ['android/app/src', 'lib']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File) continue;
        if (!RegExp(r'\.(kt|kts|xml|dart|java|pro)$').hasMatch(f.path)) {
          continue;
        }
        expect(
          f.readAsStringSync(),
          isNot(contains('app.moneyledger')),
          reason: f.path,
        );
      }
    }
  });
}
