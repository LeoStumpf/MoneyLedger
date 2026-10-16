/// MoneyLedger's Material 3 theme (G17, "Paper & ink" since G42): one builder
/// for light and dark, the platform's own font (no bundled or downloaded
/// fonts; on the web the engine's Roboto, served by us, plus our own fallback
/// fonts — G43, `web_fonts.dart`), component themes and the spacing / radius
/// tokens. Colours: see `app_colors.dart`.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'web_fonts.dart';

export 'app_colors.dart';

/// Spacing scale (logical px). Use these instead of ad-hoc numbers.
abstract final class Insets {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Horizontal page gutter on phones.
  static const page = 16.0;

  /// Bottom padding of a scroll view under an extended FAB (G33): the FAB
  /// (56) + its margin (16) + a gap (16), plus the system navigation inset —
  /// the Scaffold lifts the FAB above it, but a ListView with an explicit
  /// padding does not add it, so on 3-button navigation the FAB used to
  /// cover the last row.
  static double fabClearance(BuildContext context) =>
      88 + MediaQuery.paddingOf(context).bottom;
}

/// Corner radii.
abstract final class Radii {
  static const s = 10.0;
  static const m = 14.0;
  static const l = 20.0;
  static const xl = 28.0;
}

/// Max width of a page's content column on wide screens (web / tablets).
const kContentMaxWidth = 680.0;

/// Text style for money: tabular figures so amounts line up in lists.
const kTabularFigures = [FontFeature.tabularFigures()];

abstract final class AppTheme {
  /// [isWeb]: G43 — the web adds its bundled fallback fonts
  /// ([kWebFontFallback]); elsewhere the platform's fonts are untouched.
  static ThemeData light({bool isWeb = kIsWeb}) =>
      _build(Brightness.light, isWeb: isWeb);
  static ThemeData dark({bool isWeb = kIsWeb}) =>
      _build(Brightness.dark, isWeb: isWeb);

  /// Cards and filled inputs: a lighter sheet on the paper background, one
  /// step *lighter* than the background in dark mode (elevation = light).
  static Color cardColor(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFF1F1C17)
      : const Color(0xFFFFFDF8);

  /// The "ledger rule" above a summary (totals, my balance): a 2 px ink line.
  static BorderSide ledgerRule(ColorScheme scheme) =>
      BorderSide(color: scheme.onSurface, width: 2);

  static ThemeData _build(Brightness brightness, {required bool isWeb}) {
    final isDark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(
      seedColor: BrandColors.rust,
      brightness: brightness,
    );
    // "Paper & ink": ink is the primary (filled buttons, FAB, selection),
    // rust the one accent (secondary), petrol the tertiary. Every role the
    // UI reads is set explicitly — the seed only fills the rest (error …).
    final scheme = isDark
        ? base.copyWith(
            primary: const Color(0xFFF1ECE2),
            onPrimary: BrandColors.ink,
            primaryContainer: const Color(0xFF3A342B),
            onPrimaryContainer: const Color(0xFFF1ECE2),
            secondary: const Color(0xFFF0905E),
            onSecondary: const Color(0xFF2A1205),
            secondaryContainer: const Color(0xFF5A2A12),
            onSecondaryContainer: const Color(0xFFFFD9C4),
            tertiary: const Color(0xFF8CC4DB),
            onTertiary: const Color(0xFF0B2C3A),
            tertiaryContainer: const Color(0xFF1D4152),
            onTertiaryContainer: const Color(0xFFD3E9F2),
            surface: BrandColors.darkSurface,
            onSurface: const Color(0xFFF1ECE2),
            onSurfaceVariant: const Color(0xFFB3A998),
            surfaceTint: Colors.transparent,
            surfaceContainerLowest: const Color(0xFF100E0B),
            surfaceContainerLow: const Color(0xFF1B1813),
            surfaceContainer: const Color(0xFF24211B),
            surfaceContainerHigh: const Color(0xFF2C2821),
            surfaceContainerHighest: const Color(0xFF353027),
            outline: const Color(0xFF8C8374),
            outlineVariant: const Color(0xFF3D372E),
            inverseSurface: const Color(0xFFF1ECE2),
            onInverseSurface: BrandColors.ink,
            inversePrimary: BrandColors.ink,
          )
        : base.copyWith(
            primary: BrandColors.ink,
            onPrimary: BrandColors.paper,
            primaryContainer: const Color(0xFFEBE4D6),
            onPrimaryContainer: BrandColors.ink,
            secondary: BrandColors.rust,
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFFF6DDCD),
            onSecondaryContainer: const Color(0xFF6E2A0B),
            tertiary: BrandColors.petrol,
            onTertiary: Colors.white,
            tertiaryContainer: const Color(0xFFD6E7EE),
            onTertiaryContainer: const Color(0xFF0B3445),
            surface: BrandColors.lightSurface,
            onSurface: BrandColors.ink,
            onSurfaceVariant: const Color(0xFF6B6358),
            surfaceTint: Colors.transparent,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFFBF8F2),
            surfaceContainer: const Color(0xFFF1ECE2),
            surfaceContainerHigh: const Color(0xFFEBE5D9),
            surfaceContainerHighest: const Color(0xFFE5DECF),
            outline: const Color(0xFF8A8175),
            outlineVariant: const Color(0xFFDDD4C4),
            inverseSurface: BrandColors.ink,
            onInverseSurface: BrandColors.paper,
            inversePrimary: BrandColors.paper,
          );
    final ledger = isDark ? LedgerColors.dark : LedgerColors.light;

    final typography = Typography.material2021(
      platform: TargetPlatform.android,
    );
    final baseText = isDark ? typography.white : typography.black;
    final text = baseText
        .copyWith(
          displaySmall: baseText.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          headlineLarge: baseText.headlineLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          headlineMedium: baseText.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          headlineSmall: baseText.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleLarge: baseText.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: baseText.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          titleSmall: baseText.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          labelLarge: baseText.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          labelMedium: baseText.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: baseText.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        )
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          // G43: no Noto font is fetched on the web — our own fallbacks.
          fontFamilyFallback: isWeb ? kWebFontFallback : null,
        );

    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.m),
    );
    // Buttons, chips and segmented controls are pills.
    const pill = StadiumBorder();
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: Insets.xl,
      vertical: Insets.m,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [ledger],
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: Insets.l,
        titleTextStyle: text.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: AppTheme.cardColor(scheme),
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.m),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Insets.l),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        shape: rounded,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: pill,
        extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppTheme.cardColor(scheme),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.l,
          vertical: Insets.l,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.m),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.m),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.m),
          borderSide: BorderSide(color: scheme.onSurface, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.m),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.m),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: buttonPadding,
          shape: pill,
          textStyle: text.labelLarge?.copyWith(fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: buttonPadding,
          shape: pill,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.onSurface, width: 1.5),
          textStyle: text.labelLarge?.copyWith(fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: pill,
          foregroundColor: scheme.secondary,
          textStyle: text.labelLarge,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: pill,
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
        titleTextStyle: text.headlineSmall?.copyWith(fontSize: 22),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: rounded,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
        textStyle: text.bodyLarge,
      ),
      chipTheme: ChipThemeData(
        shape: pill,
        side: BorderSide(color: scheme.outline),
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        labelStyle: text.labelMedium,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: scheme.secondaryContainer,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSecondaryContainer,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.secondary,
      ),
      switchTheme: const SwitchThemeData(),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(Radii.s),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
    );
  }
}
