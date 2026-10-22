/// G73 (U18): a group's **fixed, hand-entered exchange rates** — part of the
/// signed group meta (wire `exchange_rates`, only when set, like G47's
/// `categories`):
///
/// ```json
/// "exchange_rates": {"base": "EUR", "rates": {"CHF": "1.0797"}, "settle": true}
/// ```
///
/// [rates] maps a currency code to what **one unit** of it is worth in
/// [base], as a canonical decimal string (canonical JSON has no floats; see
/// [isValidRate]). [settle] = "settle up in [base]": balances and suggested
/// payments convert every currency with a rate into [base] (a currency
/// without one stays separate). `settle` is on the wire only when true.
class ExchangeRates {
  final String base;

  /// Currency → rate (1 unit = rate × [base]), sorted by code.
  final Map<String, String> rates;
  final bool settle;

  ExchangeRates({
    required this.base,
    required Map<String, String> rates,
    this.settle = false,
  }) : rates = Map.unmodifiable({
         for (final c in rates.keys.toList()..sort()) c: rates[c]!,
       });

  Map<String, Object?> toJson() => {
    'base': base,
    'rates': {for (final e in rates.entries) e.key: e.value},
    if (settle) 'settle': true,
  };

  /// [raw] as found on the wire / in the DB; null when absent. A present
  /// but malformed value parses to an **invalid** entry (empty base) so the
  /// content rules refuse the version instead of silently dropping it.
  static ExchangeRates? fromJson(Object? raw) {
    if (raw == null) return null;
    if (raw is Map) {
      final base = raw['base'];
      final rates = raw['rates'];
      final settle = raw['settle'];
      if (base is String &&
          rates is Map &&
          rates.keys.every((k) => k is String) &&
          rates.values.every((v) => v is String) &&
          (settle == null || settle is bool) &&
          raw.keys.every(const {'base', 'rates', 'settle'}.contains)) {
        return ExchangeRates(
          base: base,
          rates: {for (final e in rates.entries) e.key as String: e.value},
          settle: settle == true,
        );
      }
    }
    return ExchangeRates(base: '', rates: const {});
  }

  /// A copy with [rates] / [settle] replaced; null when no rate is left
  /// (the meta then carries no `exchange_rates` at all).
  ExchangeRates? copyWith({Map<String, String>? rates, bool? settle}) {
    final next = rates ?? this.rates;
    if (next.isEmpty) return null;
    return ExchangeRates(
      base: base,
      rates: next,
      settle: settle ?? this.settle,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExchangeRates &&
      other.base == base &&
      other.settle == settle &&
      other.rates.length == rates.length &&
      rates.entries.every((e) => other.rates[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    base,
    settle,
    Object.hashAll([for (final e in rates.entries) '${e.key}=${e.value}']),
  );

  @override
  String toString() => 'ExchangeRates($base, $rates, settle: $settle)';
}

/// At most this many rates per group (content rule).
const kMaxExchangeRates = 50;

/// Digits allowed before / after the decimal point of a rate.
const kMaxRateIntegerDigits = 9;
const kMaxRateFractionDigits = 10;

final _ratePattern = RegExp(r'^(0|[1-9][0-9]{0,8})(\.[0-9]{0,9}[1-9])?$');
final _currencyCodePattern = RegExp(r'^[A-Z]{3}$');

/// Whether [code] looks like an ISO-4217 code (three capital letters).
bool isCurrencyCode(String code) => _currencyCodePattern.hasMatch(code);

/// Whether [rate] is a **canonical** positive decimal: no sign, no leading
/// zeros, no trailing fraction zeros, ≤ [kMaxRateIntegerDigits] digits
/// before and ≤ [kMaxRateFractionDigits] after the point, and not zero.
bool isValidRate(String rate) =>
    _ratePattern.hasMatch(rate) && rate.replaceAll(RegExp('[0.]'), '') != '';

/// [input] as typed (`,` or `.` as the decimal point, no grouping) as a
/// canonical rate ([isValidRate]), or null when it isn't a positive number
/// within the bounds.
String? normalizeRateInput(String input) {
  final s = input.trim().replaceAll(',', '.');
  final m = RegExp(r'^([0-9]*)(?:\.([0-9]*))?$').firstMatch(s);
  if (m == null || s.isEmpty || s == '.') return null;
  var intPart = (m.group(1) ?? '').replaceFirst(RegExp('^0+'), '');
  var frac = (m.group(2) ?? '').replaceFirst(RegExp(r'0+$'), '');
  if (intPart.isEmpty) intPart = '0';
  if (frac.length > kMaxRateFractionDigits) return null;
  final out = frac.isEmpty ? intPart : '$intPart.$frac';
  return isValidRate(out) ? out : null;
}

/// A fetched floating-point rate as a canonical rate string (rounded to
/// [kMaxRateFractionDigits] decimals), or null when it is out of bounds.
String? rateFromDouble(double value) {
  if (!value.isFinite || value <= 0) return null;
  return normalizeRateInput(value.toStringAsFixed(kMaxRateFractionDigits));
}

/// [cents] (hundredths of the source currency) converted at [rate] to
/// hundredths of the target, rounded half away from zero. Exact integer
/// math (BigInt) — no float, no overflow, same result on every platform.
int convertCents(int cents, String rate) {
  final dot = rate.indexOf('.');
  final digits = dot < 0 ? rate : rate.replaceFirst('.', '');
  final scale = dot < 0 ? 0 : rate.length - dot - 1;
  final num = BigInt.parse(digits);
  final den = BigInt.from(10).pow(scale);
  final product = BigInt.from(cents.abs()) * num;
  final rounded = (product * BigInt.two + den) ~/ (den * BigInt.two);
  final result = rounded.toInt();
  return cents < 0 ? -result : result;
}
