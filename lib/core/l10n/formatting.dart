/// Locale-aware number / money / date formatting and lenient amount parsing
/// (G12). Pure Dart (`package:intl` only) so it is unit-testable.
///
/// The CSV backup deliberately does **not** use these — it stays in machine
/// format (dot decimals, ISO dates); see `features/backup/ledger_csv.dart`.
library;

import 'package:intl/intl.dart';

import 'currencies.dart';

/// [cents] of [currency] for display, e.g. `€1,234.50` (en) / `1.234,50 €`
/// (de), `¥1,000` (JPY).
///
/// **G66 rule:** every currency is *stored* in hundredths of its major unit
/// (also JPY: `100000` = ¥1,000) — the wire / DB integer never depends on
/// the currency. Only display and input follow it: [currencyDecimals] =
/// min(ISO decimals, 2) — JPY / KRW / ISK / HUF … show 0 decimals (a legacy
/// non-whole amount like `1234` JPY shows rounded, `¥12`), BHD / KWD / JOD /
/// OMR / TND (3 ISO decimals) show 2, an unknown code (e.g. from a newer
/// peer) shows its code and 2 decimals. A letter "symbol" (e.g. `CHF`) is
/// kept apart from the digits with a no-break space (`CHF 3.00`, not
/// `CHF3.00`).
String formatMoney(int cents, String currency, String locale) {
  final NumberFormat f;
  try {
    f = NumberFormat.simpleCurrency(
      locale: locale,
      name: currency,
      decimalDigits: currencyDecimals(currency),
    );
  } catch (_) {
    // Never crash on an odd code from a peer: the plain number + the code.
    return '${NumberFormat('#,##0.00', locale).format(cents / 100)}'
        '\u00a0$currency';
  }
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
/// With a [currency] it uses that currency's decimals (G66: JPY `1000`); a
/// legacy amount that isn't a whole step of it (`1234` JPY) keeps two
/// decimals (`12.34`), so nothing is silently rounded in a prefilled field.
String formatAmountInput(int cents, String locale, {String? currency}) {
  final decimals = currency == null || cents % currencyStep(currency) != 0
      ? 2
      : currencyDecimals(currency);
  return NumberFormat(
    decimals == 0 ? '0' : '0.${'0' * decimals}',
    locale,
  ).format(cents / 100);
}

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

/// [parseLocalizedDecimal] in integer cents (stored hundredths, rounded), or
/// null. Pass the UI [locale] for user input (see the `1.234` rule there).
/// G66: with a [currency], the value is rounded to that currency's decimals
/// ([currencyStep]) — `1000.5` JPY → `100100` (¥1,001), `12.345` EUR →
/// `1235` as before.
int? parseAmountCents(String input, {String? locale, String? currency}) {
  final v = parseLocalizedDecimal(input, locale: locale);
  if (v == null) return null;
  final cents = v * 100;
  // Beyond 2^53 a double can't hold whole cents (and round() would throw on
  // infinity); far above any valid amount anyway.
  if (cents.abs() > 9007199254740991) return null;
  final step = currency == null ? 1 : currencyStep(currency);
  return step == 1 ? cents.round() : (cents / step).round() * step;
}

/// G75: the amount fields' calculator — [input] may be a small expression
/// (`12,50+8`, `3*4,20`, `100/3`, `(12+8)/2`) with `+ - * /` (also `×`,
/// `÷`, `·`), the usual precedence and optional parentheses. Each number is
/// read like [parseAmountCents] reads a whole field ([parseLocalizedDecimal]
/// with [locale] — `,` and `.`, `1.234` = 1234 in German), the **result**
/// is rounded to the [currency]'s step once (`10/3` EUR → `333`, JPY → whole
/// yen). Without an operator it is exactly [parseAmountCents]. Null for
/// anything malformed (`12+`, `+*3`, `(1+2`, letters), a division by zero or
/// a non-finite result. The range (1 cent … `kMaxAmountCents`) is the
/// caller's check, as for [parseAmountCents].
int? parseAmountInput(String input, {String? locale, String? currency}) {
  final s = input.replaceAll(RegExp("[\\s  ]"), '');
  // A leading minus alone is the plain number's sign (refused as < 1 cent).
  if (!s.contains(RegExp(r'[+*/×÷·()]')) && s.lastIndexOf('-') <= 0) {
    return parseAmountCents(input, locale: locale, currency: currency);
  }
  final v = _AmountExpression(s, locale).parse();
  if (v == null || !v.isFinite) return null;
  final cents = v * 100;
  if (cents.abs() > 9007199254740991) return null;
  final step = currency == null ? 1 : currencyStep(currency);
  return step == 1 ? cents.round() : (cents / step).round() * step;
}

/// Recursive descent over `expr := term (('+'|'-') term)*`,
/// `term := factor (('*'|'/') factor)*`,
/// `factor := '(' expr ')' | number`, plus one sign (`+`/`-`) only at the
/// very start or right after `(` — `1++2` / `5*-2` are typos, not amounts.
class _AmountExpression {
  _AmountExpression(this._s, this._locale);

  final String _s;
  final String? _locale;
  int _i = 0;

  static final _numberChar = RegExp(r"[0-9.,']");

  /// Nesting / length guard — a pasted novel isn't an amount.
  static const _maxLength = 200;

  double? parse() {
    if (_s.isEmpty || _s.length > _maxLength) return null;
    final v = _expr(0);
    return (v == null || _i != _s.length) ? null : v;
  }

  String? get _peek => _i < _s.length ? _s[_i] : null;

  double? _expr(int depth) {
    var v = _term(depth, first: true);
    while (v != null && (_peek == '+' || _peek == '-')) {
      final op = _s[_i++];
      final r = _term(depth);
      if (r == null) return null;
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double? _term(int depth, {bool first = false}) {
    var v = first ? _signed(depth) : _factor(depth);
    while (v != null && const {'*', '/', '×', '÷', '·'}.contains(_peek)) {
      final op = _s[_i++];
      final r = _factor(depth);
      if (r == null) return null;
      if (op == '/' || op == '÷') {
        if (r == 0) return null;
        v = v / r;
      } else {
        v = v * r;
      }
    }
    return v;
  }

  /// A signed operand: allowed where an expression starts.
  double? _signed(int depth) {
    final c = _peek;
    if (c == '+' || c == '-') {
      _i++;
      final v = _factor(depth);
      return v == null ? null : (c == '-' ? -v : v);
    }
    return _factor(depth);
  }

  double? _factor(int depth) {
    if (depth > 20) return null;
    final c = _peek;
    if (c == '(') {
      _i++;
      final v = _expr(depth + 1);
      if (v == null || _peek != ')') return null;
      _i++;
      return v;
    }
    final start = _i;
    while (_i < _s.length && _numberChar.hasMatch(_s[_i])) {
      _i++;
    }
    if (_i == start) return null;
    return parseLocalizedDecimal(_s.substring(start, _i), locale: _locale);
  }
}
