#!/usr/bin/env python3
"""Renders MoneyLedger's brand assets from one geometry (G17).

The logo is a coin split in two along a diagonal — two shares of one amount —
on a teal squircle. This script writes the SVG sources to assets/brand/ and
renders every PNG the platforms need (Android launcher incl. adaptive +
monochrome layers, Android pre-12 splash logo, web favicon / PWA icons incl.
maskable, iOS AppIcon set, the in-app logo).

    python3 tool/brand/render_icons.py      # from the repo root

Needs `cairosvg` (pip install cairosvg). Re-run after changing the geometry;
the outputs are committed, so builds never need it.
"""
import io
import math
import os
import sys

import cairosvg

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# Brand palette — keep in sync with lib/core/theme/app_colors.dart.
BG_TOP = '#17A58D'
BG_BOTTOM = '#0A5E54'
MINT = '#9DEBD3'
WHITE = '#FFFFFF'


def mark(cx, cy, r, gap, upper=WHITE, lower=MINT, rim=BG_BOTTOM):
    """The split coin: a coin cut in two along a vertical line, the halves
    pulled apart by [gap] and shifted against each other — two shares of one
    amount. Each half keeps a section of the coin's inner rim so it reads as
    money, not as a pie chart. [rim] None = no rim (monochrome layer: the rim
    is cut out instead)."""
    shift = r * 0.12
    ring_r = r * 0.70
    ring_w = r * 0.075
    out = []
    for side, fill, dy in ((-1, upper, -shift), (1, lower, shift)):
        x = cx + side * gap / 2
        top = cy - r + dy
        bot = cy + r + dy
        sweep = 0 if side < 0 else 1
        out.append(f'<path fill="{fill}" d="M {x:.2f} {top:.2f} '
                   f'A {r} {r} 0 0 {sweep} {x:.2f} {bot:.2f} Z"/>')
        # Inner rim: a half ring concentric with the half disc.
        rt = cy - ring_r + dy
        rb = cy + ring_r + dy
        if rim is not None:
            out.append(f'<path fill="none" stroke="{rim}" stroke-opacity="0.28" '
                       f'stroke-width="{ring_w:.2f}" d="M {x:.2f} {rt:.2f} '
                       f'A {ring_r} {ring_r} 0 0 {sweep} {x:.2f} {rb:.2f}"/>')
    return ''.join(out)


def squircle_bg(size, radius):
    return (f'<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
            f'<stop offset="0" stop-color="{BG_TOP}"/>'
            f'<stop offset="1" stop-color="{BG_BOTTOM}"/></linearGradient></defs>'
            f'<rect width="{size}" height="{size}" rx="{radius}" fill="url(#bg)"/>')


def svg(body, size=1024):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" '
            f'height="{size}" viewBox="0 0 {size} {size}">{body}</svg>')


# 1024 canvas everywhere; the mark's radius depends on the safe zone.
FULL = svg(squircle_bg(1024, 232) + mark(512, 512, 300, 56))
# Edge-to-edge square (maskable web icon, iOS — the OS rounds it). The
# maskable safe zone is a centred circle of 80 % → keep the mark well inside.
SQUARE = svg(squircle_bg(1024, 0) + mark(512, 512, 250, 38))
# Android adaptive layers: 108 dp canvas, 66 dp safe circle (r = 0.305).
ADAPTIVE_FG = svg(mark(512, 512, 238, 36))
ADAPTIVE_BG = svg(squircle_bg(1024, 0))
MONO = svg(mark(512, 512, 238, 36, upper=WHITE, lower=WHITE, rim=None))
# Splash / in-app: the mark alone, transparent.
MARK = svg(mark(512, 512, 420, 76))


def png(src, size, path):
    path = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cairosvg.svg2png(bytestring=src.encode(), write_to=path,
                     output_width=size, output_height=size)


def main():
    brand = os.path.join(ROOT, 'assets', 'brand')
    os.makedirs(brand, exist_ok=True)
    for name, src in [('logo.svg', FULL), ('logo_square.svg', SQUARE),
                      ('logo_mark.svg', MARK),
                      ('adaptive_foreground.svg', ADAPTIVE_FG),
                      ('adaptive_background.svg', ADAPTIVE_BG),
                      ('monochrome.svg', MONO)]:
        with open(os.path.join(brand, name), 'w') as f:
            f.write(src + '\n')

    # In-app logo (login, splash, about, onboarding).
    png(FULL, 512, 'assets/brand/logo_512.png')

    # Android launcher (legacy square-ish icon) + adaptive layers.
    res = 'android/app/src/main/res'
    for density, scale in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2),
                           ('xxhdpi', 3), ('xxxhdpi', 4)]:
        png(FULL, round(48 * scale), f'{res}/mipmap-{density}/ic_launcher.png')
        layer = round(108 * scale)
        png(ADAPTIVE_FG, layer,
            f'{res}/mipmap-{density}/ic_launcher_foreground.png')
        png(ADAPTIVE_BG, layer,
            f'{res}/mipmap-{density}/ic_launcher_background.png')
        png(MONO, layer, f'{res}/mipmap-{density}/ic_launcher_monochrome.png')
        # Pre-Android-12 launch screen logo (96 dp, centred on the theme bg).
        png(FULL, round(96 * scale), f'{res}/drawable-{density}/splash_logo.png')

    # Web.
    png(FULL, 32, 'web/favicon.png')
    png(FULL, 192, 'web/icons/Icon-192.png')
    png(FULL, 512, 'web/icons/Icon-512.png')
    png(SQUARE, 192, 'web/icons/Icon-maskable-192.png')
    png(SQUARE, 512, 'web/icons/Icon-maskable-512.png')

    # iOS (unsupported target, but keep the generated project consistent).
    ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for fname in os.listdir(os.path.join(ROOT, ios)):
        if not fname.endswith('.png'):
            continue
        # Icon-App-20x20@2x.png → 20 * 2
        spec = fname[len('Icon-App-'):-len('.png')]
        pts, mult = spec.split('@')
        size = round(float(pts.split('x')[0]) * float(mult.rstrip('x')))
        png(SQUARE, size, f'{ios}/{fname}')
    print('ok')


if __name__ == '__main__':
    sys.exit(main())
