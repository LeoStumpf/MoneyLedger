import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// G32: pins the "no Android auto-backup" policy. The app data holds the
/// ledger databases and the Matrix session incl. its crypto keys; PRIVACY.md
/// and the in-app privacy text say they are not backed up. The way this
/// breaks is someone tidying the XML, so it is checked textually.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final appTag = RegExp(
    r'<application\b[^>]*>',
    dotAll: true,
  ).firstMatch(manifest)!.group(0)!;

  test('auto backup is off on every Android version', () {
    expect(appTag, contains('android:allowBackup="false"'));
    expect(appTag, contains('android:fullBackupContent="false"'));
    expect(
      appTag,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      reason: 'Android 12+ ignores allowBackup for its transfer paths',
    );
  });

  test('the extraction rules exclude every domain on both paths', () {
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    expect(rules, isNot(contains('<include')));
    for (final path in ['cloud-backup', 'device-transfer']) {
      final section = RegExp(
        '<$path>(.*?)</$path>',
        dotAll: true,
      ).firstMatch(rules)!.group(1)!;
      final excluded = RegExp(
        r'<exclude domain="(\w+)"',
      ).allMatches(section).map((m) => m.group(1)).toSet();
      expect(
        excluded,
        containsAll(<String>['root', 'file', 'database', 'sharedpref']),
        reason: '$path leaves a domain backed up',
      );
    }
  });

  test('G44: no encrypted dependency-info blob in the APK / bundle', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final block = RegExp(
      r'dependenciesInfo\s*\{([^}]*)\}',
    ).firstMatch(gradle)?.group(1);
    expect(block, isNotNull, reason: 'F-Droid flags the AGP blob');
    expect(block, contains('includeInApk = false'));
    expect(block, contains('includeInBundle = false'));
  });
}
