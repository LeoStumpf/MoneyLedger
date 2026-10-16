/// G43: fonts the **web** build ships itself, because it fetches none from
/// Google (`fontFallbackBaseUrl` points at our own origin, see
/// `web/flutter_bootstrap.js`; the files come from
/// `tool/fonts/make_web_fonts.py`).
///
/// - The engine's default Roboto is served from `web/fonts/` — nothing to do
///   here (no family is declared in pubspec, so Android keeps its system
///   font).
/// - Two web-only asset fonts, registered by [loadWebOnlyFonts] and used as
///   the theme's `fontFamilyFallback` on the web ([kWebFontFallback]): the 64
///   SAS verification emoji (a Noto Color Emoji subset) and symbols Roboto
///   lacks (arrows, "⋮", ✓ … — a DejaVu Sans subset).
///
/// Other characters no bundled font has (most emoji, CJK, other scripts) are
/// shown as boxes on the web — the price of not contacting Google; the engine
/// then asks our own origin for a Noto font (404). See `docs/open-points.md`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Family name of the SAS emoji subset (registered at runtime on the web).
const kSasEmojiFontFamily = 'SasEmoji';

/// Family name of the symbols subset (registered at runtime on the web).
const kWebSymbolsFontFamily = 'AppSymbols';

/// The web theme's `fontFamilyFallback` — emoji first, so the SAS emoji
/// among the dingbats (✂ ✈ ✏) stay coloured.
const kWebFontFallback = [kSasEmojiFontFamily, kWebSymbolsFontFamily];

/// The assets (pubspec: `platforms: [web]`).
const kSasEmojiFontAsset = 'assets/fonts/sas_emoji/NotoColorEmoji-SAS.ttf';
const kSasEmojiLicenseAsset = 'assets/fonts/sas_emoji/OFL.txt';
const kWebSymbolsFontAsset = 'assets/fonts/symbols/DejaVuSans-Symbols.ttf';
const kWebSymbolsLicenseAsset = 'assets/fonts/symbols/LICENSE.txt';

/// The family the SAS emoji are drawn with: the bundled subset on the web,
/// the platform's emoji font elsewhere (null).
String? sasEmojiFontFamily({bool isWeb = kIsWeb}) =>
    isWeb ? kSasEmojiFontFamily : null;

/// Registers the web-only fonts. A no-op off the web; never throws (a
/// missing font only means boxes instead of symbols / emoji — the SAS
/// dialog shows each emoji's name next to it anyway).
Future<void> loadWebOnlyFonts({
  bool isWeb = kIsWeb,
  Future<ByteData> Function(String asset)? load,
}) async {
  if (!isWeb) return;
  final read = load ?? rootBundle.load;
  Future<void> one(String family, String asset) async {
    try {
      await (FontLoader(family)..addFont(read(asset))).load();
    } catch (e) {
      debugPrint('[fonts] $family not loaded: $e');
    }
  }

  await Future.wait([
    one(kSasEmojiFontFamily, kSasEmojiFontAsset),
    one(kWebSymbolsFontFamily, kWebSymbolsFontAsset),
  ]);
}

/// Adds the web fonts' licenses to the license page (web only — Android
/// ships none of them).
void registerWebFontLicenses({bool isWeb = kIsWeb}) {
  if (!isWeb) return;
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Roboto (web)'],
      'Roboto, served with the web app as its default font.\n\n'
      'Copyright 2011 Google Inc.\n\n'
      'Licensed under the Apache License, Version 2.0 (the "License"); you '
      'may not use this file except in compliance with the License. You may '
      'obtain a copy of the License at '
      'http://www.apache.org/licenses/LICENSE-2.0\n\n'
      'Unless required by applicable law or agreed to in writing, software '
      'distributed under the License is distributed on an "AS IS" BASIS, '
      'WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or '
      'implied. See the License for the specific language governing '
      'permissions and limitations under the License.',
    );
    yield LicenseEntryWithLineBreaks([
      'Noto Color Emoji (SAS emoji subset, web)',
    ], await _text(kSasEmojiLicenseAsset, 'SIL Open Font License 1.1'));
    yield LicenseEntryWithLineBreaks([
      'DejaVu Sans (symbols subset, web)',
    ], await _text(kWebSymbolsLicenseAsset, 'Bitstream Vera license'));
  });
}

Future<String> _text(String asset, String fallback) async {
  try {
    return await rootBundle.loadString(asset);
  } catch (_) {
    return 'Licensed under the $fallback (text unavailable).';
  }
}
