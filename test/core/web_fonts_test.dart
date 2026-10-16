/// G43: the web build fetches no font from Google — it serves the engine's
/// Roboto itself and brings web-only fallback fonts; Android is untouched.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/theme/web_fonts.dart';

void main() {
  group('loadWebOnlyFonts', () {
    test('off the web: nothing is loaded', () async {
      final asked = <String>[];
      await loadWebOnlyFonts(
        isWeb: false,
        load: (a) async {
          asked.add(a);
          return ByteData(0);
        },
      );
      expect(asked, isEmpty);
    });

    test('on the web: both fallback fonts, failures swallowed', () async {
      final asked = <String>[];
      await loadWebOnlyFonts(
        isWeb: true,
        load: (a) async {
          asked.add(a);
          throw StateError('no such asset');
        },
      );
      expect(
        asked,
        unorderedEquals([kSasEmojiFontAsset, kWebSymbolsFontAsset]),
      );
    });
  });

  test('the SAS emoji use the bundled subset only on the web', () {
    expect(sasEmojiFontFamily(isWeb: true), kSasEmojiFontFamily);
    expect(sasEmojiFontFamily(isWeb: false), isNull);
  });

  group('build setup', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    test('the font files exist', () {
      for (final f in [
        kSasEmojiFontAsset,
        kSasEmojiLicenseAsset,
        kWebSymbolsFontAsset,
        kWebSymbolsLicenseAsset,
        'web/fonts/roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2',
        'web/fonts/roboto/LICENSE.txt',
      ]) {
        expect(File(f).existsSync(), isTrue, reason: f);
      }
    });

    test('the fallback fonts are web-only assets, no font family declared '
        '(Android keeps its system fonts)', () {
      for (final asset in [
        kSasEmojiFontAsset,
        kSasEmojiLicenseAsset,
        kWebSymbolsFontAsset,
        kWebSymbolsLicenseAsset,
      ]) {
        expect(
          pubspec,
          contains('- path: $asset\n      platforms: [web]'),
          reason: asset,
        );
      }
      expect(RegExp(r'^  fonts:', multiLine: true).hasMatch(pubspec), isFalse);
    });

    test('the bootstrap keeps the engine font downloads on our origin', () {
      final boot = File('web/flutter_bootstrap.js').readAsStringSync();
      expect(boot, contains('fontFallbackBaseUrl: "fonts/"'));
      expect(boot, isNot(contains('gstatic.com/s/"')));
    });

    test('build.sh and CI build without the CDN and check it', () {
      for (final f in ['build.sh', '.github/workflows/ci.yml']) {
        final s = File(f).readAsStringSync();
        expect(s, contains('build web --release --no-web-resources-cdn'));
        expect(s, contains('tool/web/check_web_build.sh'));
      }
    });
  });
}
