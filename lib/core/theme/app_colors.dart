/// MoneyLedger's colour tokens (G17). Every colour the UI uses comes from the
/// [ColorScheme] built in `app_theme.dart` or from [LedgerColors] — widgets
/// never hard-code `Colors.*`.
library;

import 'package:flutter/material.dart';

/// Brand colours — keep in sync with `tool/brand/render_icons.py` (launcher
/// icon, splash) and the Android/web launch backgrounds.
abstract final class BrandColors {
  /// The seed of both colour schemes: a deep "ledger" teal.
  static const seed = Color(0xFF0E7D6C);

  /// Logo gradient (top-left → bottom-right) and the coin's light half.
  static const gradientStart = Color(0xFF17A58D);
  static const gradientEnd = Color(0xFF0A5E54);
  static const mint = Color(0xFF9DEBD3);

  /// Scaffold backgrounds (also the native launch screen colours).
  static const lightSurface = Color(0xFFF3F8F6);
  static const darkSurface = Color(0xFF0E1513);
}

/// Semantic money colours + the avatar palette, as a [ThemeExtension] so they
/// switch with light / dark mode. Read with `context.ledgerColors`.
///
/// * [positive] — "you are owed" / "you lent" / "gets back" (green).
/// * [negative] — "you owe" / "you borrowed" (warm red-orange — distinct from
///   the error red, and not alarming for an ordinary debt).
/// * The `*Container` variants are tinted backgrounds for chips / badges with
///   [onPositiveContainer] / [onNegativeContainer] text.
///
/// Light values keep ≥ 4.5:1 contrast on the light surfaces, dark values on
/// the dark surfaces (WCAG AA for normal text).
@immutable
class LedgerColors extends ThemeExtension<LedgerColors> {
  const LedgerColors({
    required this.positive,
    required this.negative,
    required this.positiveContainer,
    required this.onPositiveContainer,
    required this.negativeContainer,
    required this.onNegativeContainer,
    required this.avatarBackgrounds,
    required this.avatarForegrounds,
  });

  final Color positive;
  final Color negative;
  final Color positiveContainer;
  final Color onPositiveContainer;
  final Color negativeContainer;
  final Color onNegativeContainer;

  /// Deterministic avatar colours (index = hash of the participant id).
  final List<Color> avatarBackgrounds;
  final List<Color> avatarForegrounds;

  static const light = LedgerColors(
    positive: Color(0xFF167A48),
    negative: Color(0xFFC03B12),
    positiveContainer: Color(0xFFD9F3E3),
    onPositiveContainer: Color(0xFF0B4F2D),
    negativeContainer: Color(0xFFFCE3D9),
    onNegativeContainer: Color(0xFF7A2306),
    avatarBackgrounds: [
      Color(0xFFCDEFE6), // teal
      Color(0xFFD8E6FB), // blue
      Color(0xFFF7DCE8), // pink
      Color(0xFFFBE7C6), // amber
      Color(0xFFE3DDF8), // violet
      Color(0xFFD5EFCF), // green
      Color(0xFFFADBD3), // coral
      Color(0xFFD6ECF2), // cyan
    ],
    avatarForegrounds: [
      Color(0xFF0A5E54),
      Color(0xFF1E4C8F),
      Color(0xFF8A2457),
      Color(0xFF7A4B00),
      Color(0xFF4A3593),
      Color(0xFF2F6A1F),
      Color(0xFF8C2F1A),
      Color(0xFF0F5868),
    ],
  );

  static const dark = LedgerColors(
    positive: Color(0xFF72D99E),
    negative: Color(0xFFFF9F7E),
    positiveContainer: Color(0xFF113C27),
    onPositiveContainer: Color(0xFFB4F0CC),
    negativeContainer: Color(0xFF4B1F12),
    onNegativeContainer: Color(0xFFFFD2C2),
    avatarBackgrounds: [
      Color(0xFF184A42),
      Color(0xFF213A60),
      Color(0xFF552440),
      Color(0xFF4E3812),
      Color(0xFF362C63),
      Color(0xFF26461F),
      Color(0xFF5A2A1F),
      Color(0xFF173F4A),
    ],
    avatarForegrounds: [
      Color(0xFFA6EBDB),
      Color(0xFFC0D6FA),
      Color(0xFFF6C1DA),
      Color(0xFFF7D9A1),
      Color(0xFFD5CBFA),
      Color(0xFFC0E9B3),
      Color(0xFFF8C5B7),
      Color(0xFFB3E3EF),
    ],
  );

  /// Colour for a signed amount from "my" point of view: > 0 positive,
  /// < 0 negative, 0 → [neutral].
  Color forSign(int cents, Color neutral) =>
      cents > 0 ? positive : (cents < 0 ? negative : neutral);

  @override
  LedgerColors copyWith({
    Color? positive,
    Color? negative,
    Color? positiveContainer,
    Color? onPositiveContainer,
    Color? negativeContainer,
    Color? onNegativeContainer,
    List<Color>? avatarBackgrounds,
    List<Color>? avatarForegrounds,
  }) =>
      LedgerColors(
        positive: positive ?? this.positive,
        negative: negative ?? this.negative,
        positiveContainer: positiveContainer ?? this.positiveContainer,
        onPositiveContainer: onPositiveContainer ?? this.onPositiveContainer,
        negativeContainer: negativeContainer ?? this.negativeContainer,
        onNegativeContainer: onNegativeContainer ?? this.onNegativeContainer,
        avatarBackgrounds: avatarBackgrounds ?? this.avatarBackgrounds,
        avatarForegrounds: avatarForegrounds ?? this.avatarForegrounds,
      );

  @override
  LedgerColors lerp(LedgerColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<Color> l(List<Color> a, List<Color> b) =>
        [for (var i = 0; i < a.length; i++) c(a[i], b[i % b.length])];
    return LedgerColors(
      positive: c(positive, other.positive),
      negative: c(negative, other.negative),
      positiveContainer: c(positiveContainer, other.positiveContainer),
      onPositiveContainer: c(onPositiveContainer, other.onPositiveContainer),
      negativeContainer: c(negativeContainer, other.negativeContainer),
      onNegativeContainer: c(onNegativeContainer, other.onNegativeContainer),
      avatarBackgrounds: l(avatarBackgrounds, other.avatarBackgrounds),
      avatarForegrounds: l(avatarForegrounds, other.avatarForegrounds),
    );
  }
}

extension LedgerColorsX on BuildContext {
  /// The [LedgerColors] of the current theme (light values if a test pumps a
  /// bare `ThemeData` without the extension).
  LedgerColors get ledgerColors =>
      Theme.of(this).extension<LedgerColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? LedgerColors.dark
          : LedgerColors.light);
}
