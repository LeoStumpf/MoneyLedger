/// Currencies (G66): the ISO-4217 list with EN/DE names, how many decimals
/// each one shows, the default currency of a device region and the order of
/// the currency picker. Pure Dart (`package:intl` data only).
///
/// **Storage rule (option A, unchanged since the first version):** every
/// amount — in every currency — is stored and sent as an integer in
/// **hundredths** of the major unit (`1234` = 12.34 EUR = 12.34 JPY). Only
/// display and input follow the currency: [currencyDecimals] =
/// min(ISO decimals, 2) (practice-based, see [kZeroDecimalCurrencies]), so JPY / KRW / ISK / HUF … show and accept whole
/// units (and are split in steps of 100, [currencyStep]); BHD / KWD / JOD /
/// OMR / TND (3 ISO decimals) show 2 — a thousandth can't be stored in
/// hundredths. Real ISO minor units would change what the stored integer
/// means for existing JPY records (signed, hashed) and between app
/// versions — see `docs/open-points.md`.
library;

import 'currency_names.dart';

export 'currency_names.dart' show kCurrencyNames;

/// Every currency the pickers offer, sorted by code.
final List<String> kCurrencyCodes = List.unmodifiable(
  kCurrencyNames.keys.toList()..sort(),
);

/// Decimals [code] is shown and typed with: 0 for the currencies in
/// [kZeroDecimalCurrencies], else 2 — also for the 3-decimal ones (BHD, KWD,
/// JOD, OMR, TND, LYD): storage is in hundredths. An unknown code → 2.
int currencyDecimals(String code) =>
    kZeroDecimalCurrencies.contains(code.toUpperCase()) ? 0 : 2;

/// Currencies shown and typed in whole units: ISO-4217 minor unit 0 (JPY,
/// KRW, ISK, CLP, VND, …) plus those whose minor unit is unused in practice
/// (CLDR shows them without decimals: HUF, IDR, COP, RSD, …). Our own list,
/// so the display doesn't change with an `intl` upgrade.
const kZeroDecimalCurrencies = {
  'AFN', 'ALL', 'BIF', 'CLP', 'COP', 'DJF', 'GNF', 'HUF', 'IDR', 'IQD', //
  'IRR', 'ISK', 'JPY', 'KMF', 'KPW', 'KRW', 'LAK', 'LBP', 'MGA', 'MMK',
  'PYG', 'RSD', 'RWF', 'SOS', 'SYP', 'UGX', 'VND', 'VUV', 'XAF', 'XOF',
  'XPF', 'YER',
};

/// The smallest amount of [code] in stored hundredths: 1 (two decimals),
/// 10 (one), 100 (whole units, e.g. JPY).
int currencyStep(String code) => switch (currencyDecimals(code)) {
  0 => 100,
  1 => 10,
  _ => 1,
};

/// [code]'s name in [locale] (`de…` → German, else English); null for a code
/// not in the table (e.g. an unknown code from a peer).
String? currencyName(String code, String locale) {
  final names = kCurrencyNames[code];
  if (names == null) return null;
  return locale.toLowerCase().startsWith('de') ? names.$2 : names.$1;
}

/// The currency of a device region (ISO-3166 alpha-2 country code, e.g.
/// `CH` → CHF, `GB` → GBP, `DE` → EUR); null when unknown / no region.
String? regionCurrency(String? countryCode) =>
    countryCode == null ? null : _regionCurrencies[countryCode.toUpperCase()];

/// The default currency for a new group: the region's ([regionCurrency]),
/// else EUR.
String defaultCurrencyFor(String? countryCode) =>
    regionCurrency(countryCode) ?? 'EUR';

/// Common currencies (Europe + typical travel), shown near the top of the
/// picker after the group's own ones.
const kCommonCurrencies = [
  'EUR', 'USD', 'GBP', 'CHF', 'JPY', 'CAD', 'AUD', 'SEK', 'NOK', 'DKK', //
  'PLN', 'CZK', 'HUF', 'THB',
];

/// The picker's "suggested" list, in this order, without duplicates:
/// [selected], the group's currency, [used] (currencies already used in the
/// group, most frequent first — pass them in that order), the [region]'s
/// currency, then [kCommonCurrencies].
List<String> suggestedCurrencies({
  String? selected,
  String? groupCurrency,
  Iterable<String> used = const [],
  String? region,
}) {
  final out = <String>[];
  void add(String? c) {
    if (c != null && c.isNotEmpty && !out.contains(c)) out.add(c);
  }

  add(selected);
  add(groupCurrency);
  used.forEach(add);
  add(regionCurrency(region));
  kCommonCurrencies.forEach(add);
  return out;
}

/// Currency codes in [currencies] ordered by how often they occur (most
/// frequent first; ties by first occurrence).
List<String> byFrequency(Iterable<String> currencies) {
  final counts = <String, int>{};
  for (final c in currencies) {
    counts[c] = (counts[c] ?? 0) + 1;
  }
  final keys = counts.keys.toList();
  final order = {for (var i = 0; i < keys.length; i++) keys[i]: i};
  keys.sort((a, b) {
    final c = counts[b]!.compareTo(counts[a]!);
    return c != 0 ? c : order[a]!.compareTo(order[b]!);
  });
  return keys;
}

/// Whether [code] matches the search [query] in [locale]: code prefix, or a
/// word of its name (both languages) starting with it — case- and
/// accent-insensitive. An empty query matches everything.
bool currencyMatches(String code, String query, String locale) {
  final q = foldForSearch(query.trim());
  if (q.isEmpty) return true;
  if (foldForSearch(code).startsWith(q)) return true;
  final names = kCurrencyNames[code];
  if (names == null) return false;
  for (final name in [names.$1, names.$2]) {
    final n = foldForSearch(name);
    if (n.startsWith(q) || n.contains(' $q') || n.contains('-$q')) {
      return true;
    }
  }
  return false;
}

/// Lower case with the common Latin accents folded ("Złoty" ~ "zloty").
String foldForSearch(String s) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿłśźżćńęąőű';
  const to = 'aaaaaaceeeeiiiinooooouuuuyylszzcneaou';
  final out = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString();
}

const _eur = 'EUR';

/// Country → currency (ISO 3166 alpha-2 → ISO 4217) for the region default.
const _regionCurrencies = <String, String>{
  // Euro area + countries using the euro.
  'AT': _eur, 'BE': _eur, 'CY': _eur, 'DE': _eur, 'EE': _eur, 'ES': _eur,
  'FI': _eur, 'FR': _eur, 'GR': _eur, 'HR': _eur, 'IE': _eur, 'IT': _eur,
  'LT': _eur, 'LU': _eur, 'LV': _eur, 'MT': _eur, 'NL': _eur, 'PT': _eur,
  'SI': _eur, 'SK': _eur, 'AD': _eur, 'MC': _eur, 'SM': _eur, 'VA': _eur,
  'ME': _eur, 'XK': _eur, 'GP': _eur, 'MQ': _eur, 'GF': _eur, 'RE': _eur,
  'YT': _eur, 'PM': _eur, 'BL': _eur, 'MF': _eur, 'AX': _eur,
  // Rest of Europe.
  'CH': 'CHF', 'LI': 'CHF', 'GB': 'GBP', 'IM': 'GBP', 'JE': 'GBP',
  'GG': 'GBP', 'GI': 'GIP', 'SE': 'SEK', 'NO': 'NOK', 'SJ': 'NOK',
  'DK': 'DKK', 'FO': 'DKK', 'GL': 'DKK', 'IS': 'ISK', 'PL': 'PLN',
  'CZ': 'CZK', 'HU': 'HUF', 'RO': 'RON', 'BG': 'BGN', 'RS': 'RSD',
  'BA': 'BAM', 'MK': 'MKD', 'AL': 'ALL', 'MD': 'MDL', 'UA': 'UAH',
  'BY': 'BYN', 'RU': 'RUB', 'TR': 'TRY', 'GE': 'GEL', 'AM': 'AMD',
  'AZ': 'AZN',
  // Americas.
  'US': 'USD', 'PR': 'USD', 'EC': 'USD', 'SV': 'USD', 'PA': 'PAB',
  'CA': 'CAD', 'MX': 'MXN', 'BR': 'BRL', 'AR': 'ARS', 'CL': 'CLP',
  'CO': 'COP', 'PE': 'PEN', 'UY': 'UYU', 'PY': 'PYG', 'BO': 'BOB',
  'VE': 'VES', 'CR': 'CRC', 'GT': 'GTQ', 'HN': 'HNL', 'NI': 'NIO',
  'DO': 'DOP', 'CU': 'CUP', 'JM': 'JMD', 'TT': 'TTD', 'BS': 'BSD',
  'BB': 'BBD', 'HT': 'HTG',
  // Asia + Pacific.
  'JP': 'JPY', 'CN': 'CNY', 'HK': 'HKD', 'MO': 'MOP', 'TW': 'TWD',
  'KR': 'KRW', 'IN': 'INR', 'PK': 'PKR', 'BD': 'BDT', 'LK': 'LKR',
  'NP': 'NPR', 'TH': 'THB', 'VN': 'VND', 'ID': 'IDR', 'MY': 'MYR',
  'SG': 'SGD', 'PH': 'PHP', 'KH': 'KHR', 'LA': 'LAK', 'MM': 'MMK',
  'MN': 'MNT', 'KZ': 'KZT', 'UZ': 'UZS', 'KG': 'KGS', 'AU': 'AUD',
  'NZ': 'NZD', 'FJ': 'FJD', 'MV': 'MVR',
  // Middle East + Africa.
  'IL': 'ILS', 'AE': 'AED', 'SA': 'SAR', 'QA': 'QAR', 'BH': 'BHD',
  'KW': 'KWD', 'OM': 'OMR', 'JO': 'JOD', 'LB': 'LBP', 'EG': 'EGP',
  'MA': 'MAD', 'TN': 'TND', 'DZ': 'DZD', 'ZA': 'ZAR', 'NG': 'NGN',
  'KE': 'KES', 'TZ': 'TZS', 'UG': 'UGX', 'GH': 'GHS', 'ET': 'ETB',
  'SN': 'XOF', 'CI': 'XOF', 'CM': 'XAF', 'NA': 'NAD', 'BW': 'BWP',
  'MU': 'MUR', 'RW': 'RWF',
};
