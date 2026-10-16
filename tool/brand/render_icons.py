#!/usr/bin/env python3
"""Renders MoneyLedger's brand assets from one geometry (G17, G42).

The logo ("Paper & ink", G42) is a split equals sign: two bars, each cut into
a long and a short piece, the cuts on opposite sides — split differently,
equal in the end. Paper-coloured bars on an ink squircle, one piece in the
orange accent. This script writes the SVG sources to assets/brand/ and
renders every PNG the platforms need (Android launcher incl. adaptive +
monochrome layers, Android pre-12 splash logo, web favicon / PWA icons incl.
maskable, iOS AppIcon set, the in-app logo) plus the Play Store listing
graphics in docs/store/ (512 px icon, 1024x500 feature graphic).

    python3 tool/brand/render_icons.py      # from the repo root

Needs `cairosvg` (pip install cairosvg). Re-run after changing the geometry;
the outputs are committed, so builds never need it.
"""
import os
import sys

import cairosvg

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# Brand palette — keep in sync with lib/core/theme/app_colors.dart.
INK = '#1D1A16'
PAPER = '#F6F2EA'
ORANGE = '#E0703A'
RUST = '#B84E1C'
PETROL = '#1F5F7A'
MUTED = '#6B6358'
RULE = '#DDD4C4'

# The mark in its own units: 58 wide, 32 high (two 13-high bars, 6 apart).
# (x, y, w) per piece; the third piece (bottom left) is the accent.
_PIECES = [(0, 0, 36), (40, 0, 18), (0, 19, 18), (22, 19, 36)]
_BAR_H = 13
_MARK_W = 58
_MARK_H = 32


def mark(cx, cy, width, bar=PAPER, accent=ORANGE):
    """The split equals sign centred on (cx, cy), [width] px wide."""
    k = width / _MARK_W
    x0 = cx - width / 2
    y0 = cy - _MARK_H * k / 2
    h = _BAR_H * k
    out = []
    for i, (x, y, w) in enumerate(_PIECES):
        fill = accent if i == 2 else bar
        out.append(f'<rect x="{x0 + x * k:.2f}" y="{y0 + y * k:.2f}" '
                   f'width="{w * k:.2f}" height="{h:.2f}" rx="{h / 2:.2f}" '
                   f'fill="{fill}"/>')
    return ''.join(out)


def squircle_bg(size, radius, color=INK):
    return f'<rect width="{size}" height="{size}" rx="{radius}" fill="{color}"/>'


def svg(body, size=1024, height=None):
    height = height or size
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" '
            f'height="{height}" viewBox="0 0 {size} {height}">{body}</svg>')


# 1024 canvas everywhere; the mark's width depends on the safe zone.
FULL = svg(squircle_bg(1024, 232) + mark(512, 512, 560))
# Edge-to-edge square (maskable web icon, iOS — the OS rounds it). The
# maskable safe zone is a centred circle of 80 % → keep the mark well inside.
SQUARE = svg(squircle_bg(1024, 0) + mark(512, 512, 470))
# Android adaptive layers: 108 dp canvas, 66 dp safe circle (r = 0.305).
ADAPTIVE_FG = svg(mark(512, 512, 500))
ADAPTIVE_BG = svg(squircle_bg(1024, 0))
MONO = svg(mark(512, 512, 500, bar='#FFFFFF', accent='#FFFFFF'))
# The mark alone, transparent, in ink (for light backgrounds).
MARK = svg(mark(512, 512, 900, bar=INK, accent=ORANGE))


def _text(x, y, text, size, weight=700, fill=INK, spacing=0):
    return (f'<text x="{x}" y="{y}" font-family="sans-serif" '
            f'font-size="{size}" font-weight="{weight}" fill="{fill}" '
            f'letter-spacing="{spacing}">{text}</text>')


def feature_graphic():
    """Play Store feature graphic, 1024x500 ("Paper & ink", canvas B)."""
    body = [f'<rect width="1024" height="500" fill="{PAPER}"/>']
    # Ledger lines.
    for y in range(39, 500, 40):
        body.append(f'<rect x="0" y="{y}" width="1024" height="1" '
                    f'fill="#E6DDCD"/>')
    # Logo + name.
    body.append(f'<g transform="translate(72 96) scale(0.0547)">'
                f'{squircle_bg(1024, 240)}{mark(512, 512, 560)}</g>')
    body.append(_text(142, 136, 'MoneyLedger', 28, 800))
    # Headline + sub line.
    body.append(_text(72, 222, 'Wer schuldet wem?', 50, 800, spacing=-1))
    body.append(_text(72, 280, 'Geklärt.', 50, 800, RUST, spacing=-1))
    body.append(_text(72, 336, 'Ausgaben fair teilen – ohne Server,', 21,
                      500, MUTED))
    body.append(_text(72, 366, 'Ende-zu-Ende-verschlüsselt, Open Source.', 21,
                      500, MUTED))
    # The receipt: the group's suggested payments.
    rows = [('David → Anna', '128,77 €'), ('Chiara → Anna', '118,37 €'),
            ('Ben → Anna', '47,48 €')]
    card = ['<rect x="0" y="0" width="300" height="270" rx="6" fill="#FFFFFF"/>',
            _text(26, 44, 'LISBON TRIP · AUSGLEICH', 12, 800, MUTED, 1)]
    for i, (who, amount) in enumerate(rows):
        y = 92 + i * 50
        card.append(_text(26, y, who, 17, 600))
        card.append(f'<text x="274" y="{y}" text-anchor="end" '
                    f'font-family="sans-serif" font-size="17" '
                    f'font-weight="800" fill="{INK}">{amount}</text>')
        line = (f'<rect x="26" y="{y + 18}" width="248" height="2" '
                f'fill="{INK}"/>' if i == 2 else
                f'<line x1="26" y1="{y + 18}" x2="274" y2="{y + 18}" '
                f'stroke="#C9BFAE" stroke-dasharray="4 4"/>')
        card.append(line)
    card.append(_text(26, 244, 'Danach', 15, 700, MUTED))
    card.append(f'<text x="274" y="244" text-anchor="end" '
                f'font-family="sans-serif" font-size="21" font-weight="800" '
                f'fill="{PETROL}">alle bei 0,00 €</text>')
    body.append('<g transform="translate(672 95) rotate(3)">'
                '<rect x="4" y="14" width="300" height="270" rx="6" '
                'fill="#1D1A16" opacity="0.10"/>' + ''.join(card) + '</g>')
    return svg(''.join(body), 1024, 500)


def png(src, size, path, height=None):
    path = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cairosvg.svg2png(bytestring=src.encode(), write_to=path,
                     output_width=size, output_height=height or size)


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
    # Play Store listing (docs/store/, not bundled with the app).
    png(SQUARE, 512, 'docs/store/icon_512.png')
    fg = feature_graphic()
    with open(os.path.join(ROOT, 'docs', 'store', 'feature_graphic.svg'),
              'w') as f:
        f.write(fg + '\n')
    png(fg, 1024, 'docs/store/feature_graphic.png', height=500)
    print('ok')


if __name__ == '__main__':
    sys.exit(main())
