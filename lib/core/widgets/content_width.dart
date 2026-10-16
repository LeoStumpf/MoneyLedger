import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Centres [child] and caps its width at [maxWidth] (G17) — phone layouts
/// are unaffected, wide windows (web, tablets) get a readable column instead
/// of edge-to-edge rows.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = kContentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}
