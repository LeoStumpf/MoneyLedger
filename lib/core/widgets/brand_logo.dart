import 'package:flutter/material.dart';

/// The MoneyLedger logo (G17) — the split coin on a teal squircle, rendered
/// from `assets/brand/logo.svg` by `tool/brand/render_icons.py`.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/brand/logo_512.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        // Widget tests without the asset bundle still lay out.
        errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
      );
}
