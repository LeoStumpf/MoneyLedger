/// G73: *Fetch current rate* — the one place the app asks a third party for
/// an exchange rate, and **only when the user taps the button** (never
/// automatically, never in the background). Source: **Frankfurter**
/// (`api.frankfurter.dev`, open source, free, no API key, no account, no
/// cookies; reference rates of the ECB and other central banks). The
/// request names only the two currency codes; the service sees the device's
/// IP address. Said in the rate dialog, PRIVACY.md and the in-app privacy
/// text (`privacyRates*`).
///
/// `GET https://api.frankfurter.dev/v2/rate/CHF/EUR` →
/// `{"date":"2026-10-22","base":"CHF","quote":"EUR","rate":1.0797}`; an
/// unknown / unsupported currency → 404 / 422.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../models/exchange_rates.dart';

/// The service the button asks (named in the dialog and the privacy text).
const kRateSourceHost = 'api.frankfurter.dev';

/// How long one rate request may take.
const kRateFetchTimeout = Duration(seconds: 15);

/// A fetched rate: 1 unit of the source currency = [rate] of the target
/// (canonical, see [isValidRate]), as published for [date] (ISO day).
class FetchedRate {
  final String rate;
  final String date;
  const FetchedRate({required this.rate, required this.date});
}

/// The service has no rate for this currency pair (it covers about 30
/// currencies) — the user enters it by hand.
class RateUnavailableException implements Exception {
  final String from;
  final String to;
  const RateUnavailableException(this.from, this.to);
  @override
  String toString() => 'RateUnavailableException($from → $to)';
}

/// Asks for the rate `1 from = ? to`.
typedef ExchangeRateFetcher =
    Future<FetchedRate> Function(String from, String to);

/// The fetcher the rate dialog uses (tests override it — no network).
final exchangeRateFetcherProvider = Provider<ExchangeRateFetcher>(
  (ref) => fetchFrankfurterRate,
);

/// The request URL for `1 from = ? to`.
Uri frankfurterRateUri(String from, String to) =>
    Uri.https(kRateSourceHost, '/v2/rate/$from/$to');

/// The real adapter ([client] for tests).
Future<FetchedRate> fetchFrankfurterRate(
  String from,
  String to, {
  http.Client? client,
}) async {
  if (!isCurrencyCode(from) || !isCurrencyCode(to)) {
    throw RateUnavailableException(from, to);
  }
  final c = client ?? http.Client();
  try {
    final response = await c
        .get(
          frankfurterRateUri(from, to),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(kRateFetchTimeout);
    if (response.statusCode == 404 || response.statusCode == 422) {
      throw RateUnavailableException(from, to);
    }
    if (response.statusCode != 200) {
      throw http.ClientException(
        'HTTP ${response.statusCode}',
        frankfurterRateUri(from, to),
      );
    }
    return parseFrankfurterRate(response.body, from: from, to: to);
  } finally {
    if (client == null) c.close();
  }
}

/// [body] of a `/v2/rate/{from}/{to}` answer as a [FetchedRate]. Throws a
/// [FormatException] for anything that isn't such an answer for exactly
/// this pair, [RateUnavailableException] when its rate is out of bounds.
FetchedRate parseFrankfurterRate(
  String body, {
  required String from,
  required String to,
}) {
  final json = jsonDecode(body);
  if (json is! Map ||
      json['base'] != from ||
      json['quote'] != to ||
      json['rate'] is! num ||
      json['date'] is! String) {
    throw const FormatException('unexpected exchange-rate answer');
  }
  final rate = rateFromDouble((json['rate'] as num).toDouble());
  if (rate == null) throw RateUnavailableException(from, to);
  return FetchedRate(rate: rate, date: json['date'] as String);
}
