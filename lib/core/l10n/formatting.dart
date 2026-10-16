/// Locale-aware number / money / date formatting and lenient amount parsing
/// (G12). Pure Dart (`package:intl` only) so it is unit-testable.
///
/// The CSV backup deliberately does **not** use these — it stays in machine
/// format (dot decimals, ISO dates); see `features/backup/ledger_csv.dart`.
library;

import 'package:intl/intl.dart';

/// [cents] of [currency] for display, e.g. `€1,234.50` (en) / `1.234,50 €`
/// (de). Every currency is stored in hundredths (also JPY), so two decimals
/// are always shown. A letter "symbol" (e.g. `CHF`) is kept apart from the
/// digits with a no-break space (`CHF 3.00`, not `CHF3.00`).
String formatMoney(int cents, String currency, String locale) {
  final f = NumberFormat.simpleCurrency(
    locale: locale,
    name: currency,
    decimalDigits: 2,
  );
  final text = f.format(cents / 100);
  final symbol = f.currencySymbol;
  if (!RegExp(r'^[A-Za-z]+$').hasMatch(symbol)) return text;
  return text.replaceFirstMapped(
    RegExp('${RegExp.escape(symbol)}(?=\\d)'),
    (m) => '${m[0]}\u00a0',
  );
}

/// [cents] as a plain decimal for an editable amount field — no grouping, no
/// symbol, the locale's decimal separator: `1234.50` (en) / `1234,50` (de).
String formatAmountInput(int cents, String locale) =>
    NumberFormat('0.00', locale).format(cents / 100);

/// A percentage value for display, e.g. `33.3` / `33,3`.
String formatDecimal(num value, String locale) =>
    NumberFormat.decimalPattern(locale).format(value);

/// A short localized date: `Jun 13, 2026` (en) / `13. Juni 2026` (de).
/// Needs the locale's date symbols — loaded by the Flutter localization
/// delegates in the app (and in widget tests that use them).
String formatDate(int msEpoch, String locale) => DateFormat.yMMMd(
  locale,
).format(DateTime.fromMillisecondsSinceEpoch(msEpoch));

/// A short localized date + time (G48): `Jun 13, 2026 14:05` (en) /
/// `13. Juni 2026 14:05` (de).
String formatDateTime(int msEpoch, String locale) => DateFormat.yMMMd(
  locale,
).add_Hm().format(DateTime.fromMillisecondsSinceEpoch(msEpoch));

/// A day header for a dated list (G17): `Wed, Oct 15` (en) / `Mi., 15. Okt.`
/// (de) within [now]'s year, with the year otherwise. "Today" / "Yesterday"
/// are decided by the caller ([calendarDaysAgo]).
String formatDayHeader(int msEpoch, String locale, {DateTime? now}) {
  final d = DateTime.fromMillisecondsSinceEpoch(msEpoch);
  final n = now ?? DateTime.now();
  return (d.year == n.year
          ? DateFormat.MMMEd(locale)
          : DateFormat.yMMMEd(locale))
      .format(d);
}

/// Whole calendar days between [msEpoch]'s local date and [now]'s (0 = same
/// day, 1 = yesterday; negative for the future). DST-safe.
int calendarDaysAgo(int msEpoch, {DateTime? now}) {
  final d = DateTime.fromMillisecondsSinceEpoch(msEpoch);
  final n = now ?? DateTime.now();
  return DateTime.utc(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
}

/// Parses a user-typed decimal number, accepting both `,` and `.` as the
/// decimal separator regardless of locale:
///  * `12.5`, `12,5` → 12.5
///  * both present → the **last** one is the decimal separator and the other
///    is grouping: `1.234,50` / `1,234.50` → 1234.5
///  * one kind repeated → grouping: `1.234.567` → 1234567
///  * spaces / `'` (Swiss grouping) are ignored.
///  * G18 review: with a [locale], a **lone** occurrence of that locale's
///    grouping separator followed by exactly three digits is grouping — `de`:
///    `1.234` → 1234 (en: `1.234` stays 1.234; `en`: `1,234` → 1234).
/// Grouping must be well-formed (first group 1–3 digits, then groups of
/// exactly 3): `12,34.5` → null. Returns null for anything else (letters,
/// empty, `1,2.3,4`, non-finite).
double? parseLocalizedDecimal(String input, {String? locale}) {
  var s = input.trim().replaceAll(RegExp("[\\s  ']"), '');
  if (s.isEmpty) return null;
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    final decimal = lastComma > lastDot ? ',' : '.';
    final grouping = decimal == ',' ? '.' : ',';
    // The decimal separator must occur once, after every grouping separator.
    if (s.indexOf(decimal) != s.lastIndexOf(decimal)) return null;
    final at = s.indexOf(decimal);
    if (!_wellGrouped(s.substring(0, at), grouping)) return null;
    s = s.replaceAll(grouping, '').replaceAll(decimal, '.');
  } else {
    final sep = lastComma >= 0 ? ',' : (lastDot >= 0 ? '.' : null);
    if (sep != null) {
      final count = sep.allMatches(s).length;
      final lone = count == 1;
      final asGrouping =
          !lone ||
          (locale != null &&
              sep == _groupingSeparator(locale) &&
              RegExp(r'^-?\d+$').hasMatch(s.substring(0, s.indexOf(sep))) &&
              RegExp(r'^\d{3}$').hasMatch(s.substring(s.indexOf(sep) + 1)));
      if (asGrouping) {
        if (!_wellGrouped(s, sep)) return null;
        s = s.replaceAll(sep, '');
      } else {
        s = s.replaceAll(sep, '.');
      }
    }
  }
  if (!RegExp(r'^-?(\d+\.?\d*|\.\d+)$').hasMatch(s)) return null;
  final v = double.tryParse(s);
  return v != null && v.isFinite ? v : null;
}

/// Whether [intPart] uses [sep] as well-formed thousands grouping: no
/// separator at all, or a first group of 1–3 digits followed by groups of
/// exactly 3 (`1,234,567`; not `12,34`).
bool _wellGrouped(String intPart, String sep) {
  final digits = intPart.startsWith('-') ? intPart.substring(1) : intPart;
  if (!digits.contains(sep)) return true;
  final groups = digits.split(sep);
  if (!RegExp(r'^\d{1,3}$').hasMatch(groups.first)) return false;
  return groups.skip(1).every((g) => RegExp(r'^\d{3}$').hasMatch(g));
}

/// The grouping separator of [locale] (`,` en, `.` de), or null.
String? _groupingSeparator(String locale) {
  try {
    return NumberFormat.decimalPattern(locale).symbols.GROUP_SEP;
  } catch (_) {
    return null;
  }
}

/// [parseLocalizedDecimal] in integer cents (rounded), or null. Pass the UI
/// [locale] for user input (see the `1.234` rule there).
int? parseAmountCents(String input, {String? locale}) {
  final v = parseLocalizedDecimal(input, locale: locale);
  if (v == null) return null;
  final cents = v * 100;
  // Beyond 2^53 a double can't hold whole cents (and round() would throw on
  // infinity); far above any valid amount anyway.
  if (cents.abs() > 9007199254740991) return null;
  return cents.round();
}
