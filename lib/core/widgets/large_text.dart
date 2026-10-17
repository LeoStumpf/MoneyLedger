import 'package:flutter/widgets.dart';

/// DEV-I (G71 device pass): true when the system font size makes body text
/// at least 1.3× its normal size (Android "Font size" near the maximum —
/// 200 % is ~1.6–2× with Android 14's non-linear scaling).
///
/// Rows that put a name and an amount side by side switch to a stacked
/// layout then: at 360 dp the side-by-side version ellipsized both (names
/// cut to one letter, amounts without their currency).
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) >= 16 * 1.3;

/// DEV-I: a fixed-width input cell ([base] dp at the normal font size) that
/// grows with the system font size, up to [max] dp — so a value like
/// "617,28 EUR" or the currency code stays visible at 200 %.
double scaledCellWidth(BuildContext context, double base, double max) {
  final f = MediaQuery.textScalerOf(context).scale(16) / 16;
  return (base * f).clamp(base, max);
}

/// G79: the single-line width of [text] in [style] (with [scaler], the
/// system font size) — to decide whether something fits before laying it
/// out (word-safe headers, app-bar titles, the exact-amount cell's suffix).
double measureTextWidth(
  String text,
  TextStyle? style,
  TextScaler scaler, {
  TextDirection direction = TextDirection.ltr,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textScaler: scaler,
    textDirection: direction,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// G79: [base] (the system font size) times [factor] — shrinks one text to
/// fit without ignoring the user's font size elsewhere.
class ScaledTextScaler extends TextScaler {
  final TextScaler base;
  final double factor;
  const ScaledTextScaler(this.base, this.factor);

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is ScaledTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// G79: an app-bar title that stays readable at 360 dp in German ("Ausgabe
/// bearbeiten" next to two actions was "Ausgabe bearbe…"): one line if it
/// fits, else scaled down to at most [minScale]; still too long → two lines
/// at [minScale] (one line, ellipsized, at a large font size — two lines
/// wouldn't fit the toolbar).
class AppBarTitle extends StatelessWidget {
  final String text;
  final double minScale;
  const AppBarTitle(this.text, {super.key, this.minScale = 0.8});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final style = DefaultTextStyle.of(context).style;
        final max = constraints.maxWidth;
        if (!max.isFinite || max <= 0) {
          return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
        }
        final width = measureTextWidth(
          text,
          style,
          scaler,
          direction: Directionality.of(context),
        );
        if (width <= max) {
          return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
        }
        final factor = max / width * 0.99;
        if (factor >= minScale) {
          return Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: ScaledTextScaler(scaler, factor),
          );
        }
        return Text(
          text,
          maxLines: isLargeText(context) ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          textScaler: ScaledTextScaler(scaler, minScale),
        );
      },
    );
  }
}
