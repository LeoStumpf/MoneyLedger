#!/usr/bin/env python3
"""Builds the self-hosted web fonts (G43) — no font is fetched from Google.

1. Roboto for the Flutter web engine's default font. Without a bundled
   "Roboto" family the engine downloads Roboto Regular from
   `<fontFallbackBaseUrl>roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2`
   (default base: https://fonts.gstatic.com/s/). `web/flutter_bootstrap.js`
   points that base at `fonts/` on our own origin, so this script writes
   Roboto Regular (Flutter SDK's material_fonts copy, Apache-2.0) as woff2 at
   exactly that path under `web/fonts/`. The path is the engine's — if a
   Flutter upgrade changes it, `tool/web/check_web_build.sh` (run by build.sh
   and CI) fails and names the new path; re-run this with `--roboto-path`.

2. The 64 SAS verification emoji, subset from Noto Color Emoji (OFL-1.1),
   for the emoji-comparison dialog on the web (no emoji fallback font is
   fetched there any more). Written to `assets/fonts/sas_emoji/`.

3. Symbols Roboto lacks — arrows (our texts say "Settings → Back up"), math
   operators ("⋮"), general punctuation, geometric shapes, dingbats (✓) —
   subset from DejaVu Sans (Bitstream Vera license, DejaVu changes public
   domain). Written to `assets/fonts/symbols/`. Without it the engine would
   look for Noto Sans Symbols under fonts/, get a 404 and retry on every
   layout.

(2) and (3) are web-only assets in pubspec.yaml, registered by
`loadWebOnlyFonts()` and used as the theme's `fontFamilyFallback` on the web.

    python3 -I tool/fonts/make_web_fonts.py      # from the repo root

Needs fontTools + brotli (pip install fonttools brotli), the Flutter SDK
(FLUTTER_ROOT or `flutter` on PATH) and Noto Color Emoji (Debian:
fonts-noto-color-emoji; or pass --emoji-font) and DejaVu Sans (Debian:
fonts-dejavu-core; or pass --symbols-font). The outputs are committed, so
builds never need it.
"""
import argparse
import os
import re
import shutil
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_ROBOTO_PATH = 'roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2'


def flutter_root():
    if os.environ.get('FLUTTER_ROOT'):
        return os.environ['FLUTTER_ROOT']
    exe = shutil.which('flutter')
    if not exe:
        sys.exit('flutter not found — set FLUTTER_ROOT')
    return os.path.dirname(os.path.dirname(os.path.realpath(exe)))


def make_roboto(rel_path):
    src_dir = os.path.join(flutter_root(), 'bin', 'cache', 'artifacts', 'material_fonts')
    font = TTFont(os.path.join(src_dir, 'Roboto-Regular.ttf'))
    font.flavor = 'woff2'
    out = os.path.join(ROOT, 'web', 'fonts', rel_path)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    font.save(out)
    shutil.copy(os.path.join(src_dir, 'Roboto_LICENSE.txt'),
                os.path.join(ROOT, 'web', 'fonts', 'roboto', 'LICENSE.txt'))
    print(f'wrote {os.path.relpath(out, ROOT)} ({os.path.getsize(out)} B)')


def make_sas_emoji(emoji_font):
    table = open(os.path.join(ROOT, 'lib', 'features', 'devices', 'sas_emoji_names.dart'),
                 encoding='utf-8').read()
    emojis = re.findall(r"emoji: '([^']+)'", table)
    assert len(emojis) == 64, len(emojis)
    codepoints = sorted({ord(c) for e in emojis for c in e})
    out_dir = os.path.join(ROOT, 'assets', 'fonts', 'sas_emoji')
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, 'NotoColorEmoji-SAS.ttf')
    options = subset.Options()
    options.drop_tables += ['GSUB']  # no sequences among the 64 — keep it lean
    font = subset.load_font(emoji_font, options)
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(font)
    subset.save_font(font, out, options)
    missing = [hex(c) for c in codepoints
               if c != 0xFE0F and c not in TTFont(out).getBestCmap()]
    if missing:
        sys.exit(f'emoji missing from the subset: {missing}')
    print(f'wrote {os.path.relpath(out, ROOT)} ({os.path.getsize(out)} B)')


SYMBOL_RANGES = 'U+2000-206F,U+2190-23FF,U+25A0-25FF,U+2700-27BF'


def make_symbols(symbols_font):
    out_dir = os.path.join(ROOT, 'assets', 'fonts', 'symbols')
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, 'DejaVuSans-Symbols.ttf')
    options = subset.Options()
    options.hinting = False
    options.layout_features = []
    font = subset.load_font(symbols_font, options)
    subsetter = subset.Subsetter(options)
    unicodes = []
    for part in SYMBOL_RANGES.split(','):
        lo, hi = part[2:].split('-')
        unicodes += range(int(lo, 16), int(hi, 16) + 1)
    subsetter.populate(unicodes=unicodes)
    subsetter.subset(font)
    subset.save_font(font, out, options)
    for c in (0x2192, 0x22EE):  # used in our UI texts
        assert c in TTFont(out).getBestCmap(), hex(c)
    print(f'wrote {os.path.relpath(out, ROOT)} ({os.path.getsize(out)} B)')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--roboto-path', default=DEFAULT_ROBOTO_PATH,
                   help='engine Roboto path below fontFallbackBaseUrl')
    p.add_argument('--emoji-font',
                   default='/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf')
    p.add_argument('--symbols-font',
                   default='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
    args = p.parse_args()
    make_roboto(args.roboto_path)
    make_sas_emoji(args.emoji_font)
    make_symbols(args.symbols_font)


if __name__ == '__main__':
    main()
