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
