import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'large_text.dart';

/// G65: the small caps-style heading above a group of settings tiles (app
/// settings page, group settings page). [danger] colours it with the
/// scheme's error colour (leave / delete).
class SettingsSectionHeader extends StatelessWidget {
  final String text;
  final bool danger;
  const SettingsSectionHeader(this.text, {super.key, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.page,
        Insets.xl,
        Insets.page,
        Insets.xs,
      ),
      child: Semantics(
        header: true,
        child: WordSafeText(
          text.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: danger ? scheme.error : scheme.secondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

/// G79: text that wraps at word boundaries only. When a single word is wider
/// than the available width (e.g. "WIEDERHERSTELLUNGSPUNKTE" in caps at 200 %
/// font on a 360 dp phone) the whole text is scaled down until that word
/// fits on one line, instead of being broken mid-word.
class WordSafeText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const WordSafeText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final max = constraints.maxWidth;
        var factor = 1.0;
        if (max.isFinite && max > 0) {
          final effective = DefaultTextStyle.of(context).style.merge(style);
          final direction = Directionality.of(context);
          final words = text.split(RegExp(r'\s+'))
            ..removeWhere((w) => w.isEmpty);
          double widest(TextScaler scaler) {
            var widest = 0.0;
            for (final word in words) {
              final w = measureTextWidth(
                word,
                effective,
                scaler,
                direction: direction,
              );
              if (w > widest) widest = w;
            }
            return widest;
          }

          // Letter spacing doesn't scale with the text scaler, so shrink in
          // a few steps until the widest word fits.
          var w = widest(scaler);
          for (var i = 0; i < 6 && w > max; i++) {
            factor *= max / w * 0.98;
            w = widest(ScaledTextScaler(scaler, factor));
          }
        }
        return Text(
          text,
          style: style,
          textScaler: factor < 1 ? ScaledTextScaler(scaler, factor) : scaler,
        );
      },
    );
  }
}
