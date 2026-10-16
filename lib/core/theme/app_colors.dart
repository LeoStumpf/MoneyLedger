/// MoneyLedger's colour tokens (G17). Every colour the UI uses comes from the
/// [ColorScheme] built in `app_theme.dart` or from [LedgerColors] — widgets
/// never hard-code `Colors.*`.
library;

import 'package:flutter/material.dart';

/// Brand colours ("Paper & ink", G42) — keep in sync with
/// `tool/brand/render_icons.py` (launcher icon, splash) and the Android/web
/// launch backgrounds.
abstract final class BrandColors {
  /// Ink: text, the primary (filled) buttons, the app icon's background.
  static const ink = Color(0xFF1D1A16);

  /// Paper: the light background and the icon's bars.
  static const paper = Color(0xFFF6F2EA);

  /// The single accent: the icon's orange bar piece.
  static const orange = Color(0xFFE0703A);

  /// Rust: the accent as a text / button colour (AA on paper and white).
  static const rust = Color(0xFFB84E1C);

  /// Petrol: "you get money back".
  static const petrol = Color(0xFF1F5F7A);

  /// Scaffold backgrounds (also the native launch screen colours).
  static const lightSurface = paper;
  static const darkSurface = Color(0xFF15130F);
}

/// Semantic money colours + the avatar palette, as a [ThemeExtension] so they
/// switch with light / dark mode. Read with `context.ledgerColors`.
///
/// * [positive] — "you are owed" / "you lent" / "gets back" (petrol blue).
/// * [negative] — "you owe" / "you borrowed" (rust — distinct from the error
///   red, and not alarming for an ordinary debt). Blue vs. orange also differ
///   in lightness, so they stay apart for red-green colour blindness.
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
    positive: BrandColors.petrol,
    negative: BrandColors.rust,
    positiveContainer: Color(0xFFD6E7EE),
    onPositiveContainer: Color(0xFF0B3445),
    negativeContainer: Color(0xFFF6DDCD),
    onNegativeContainer: Color(0xFF6E2A0B),
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
    positive: Color(0xFF8CC4DB),
    negative: Color(0xFFF0905E),
    positiveContainer: Color(0xFF1D4152),
    onPositiveContainer: Color(0xFFD3E9F2),
    negativeContainer: Color(0xFF5A2A12),
    onNegativeContainer: Color(0xFFFFD9C4),
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
  }) => LedgerColors(
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
    List<Color> l(List<Color> a, List<Color> b) => [
      for (var i = 0; i < a.length; i++) c(a[i], b[i % b.length]),
    ];
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
