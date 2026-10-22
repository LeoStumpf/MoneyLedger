/// G74: the user's own payment details (bank account / PayPal.me) and the
/// two things built from them when someone owes the user money — a
/// GiroCode (EPC QR code, "BCD" payload v002) and a PayPal.me link with the
/// amount. Pure Dart: no Flutter, no DB.
///
/// The details are stored device-local (per ledger, `AppSettings`
/// `payment_details`); the data class + IBAN / BIC / PayPal.me checks live
/// in `models/payment_details.dart` (G74 wire bundle: an optional signed
/// `payment` field of the member record carries them to the groups).
library;

import 'dart:convert';

import '../../core/l10n/currencies.dart';
import '../../models/payment_details.dart';

export '../../models/payment_details.dart';

/// [cents] (hundredths, as stored — G66) as a plain decimal with a dot:
/// two decimals, none for a zero-decimal currency.
String _plainAmount(int cents, String currency) {
  if (currencyDecimals(currency) == 0) return '${(cents / 100).round()}';
  return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
}

/// `https://paypal.me/<user>/<amount><CUR>` — PayPal opens the payment
/// with the amount filled in. Without a positive amount: the bare link.
String paypalMeUrl(String user, {int? cents, String? currency}) {
  final base = 'https://paypal.me/$user';
  if (cents == null || cents <= 0 || currency == null) return base;
  return '$base/${_plainAmount(cents, currency)}$currency';
}

// ── GiroCode (EPC QR) ────────────────────────────────────────────────────────

/// The EPC's limit for the whole payload (EPC069-12).
const kEpcMaxBytes = 331;

/// The highest amount a GiroCode may carry: 999 999 999.99 €.
const kEpcMaxCents = 99999999999;

/// The EPC QR ("GiroCode") payload of a SEPA credit transfer to [details]'s
/// account over [cents] euro, with [remittance] as the unstructured
/// reference (≤ 140 characters, cut to fit the 331-byte limit). Version
/// 002 (BIC optional), UTF-8. Null unless [currency] is EUR and [details]
/// has a bank account. An amount outside 0.01 … 999 999 999.99 € is left
/// out (the payer types it).
String? epcQrPayload(
  PaymentDetails details, {
  required int cents,
  required String currency,
  String? remittance,
}) {
  if (currency != 'EUR' || !details.hasBankAccount) return null;
  String clean(String s) => s.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  String cut(String s, int max) {
    final runes = s.runes.toList();
    return runes.length <= max ? s : String.fromCharCodes(runes.take(max));
  }

  var name = cut(clean(details.name!), 70);
  List<String> head() => [
    'BCD',
    '002',
    '1', // UTF-8
    'SCT',
    details.bic ?? '',
    name,
    details.iban!,
    if (cents >= 1 && cents <= kEpcMaxCents)
      'EUR${_plainAmount(cents, 'EUR')}'
    else
      '',
  ];
  var text = cut(clean(remittance ?? ''), 140);
  String build() => [
    ...head(),
    if (text.isNotEmpty) ...['', '', text],
  ].join('\n');
  while (text.isNotEmpty && utf8.encode(build()).length > kEpcMaxBytes) {
    text = cut(text, text.runes.length - 1).trimRight();
  }
  // Still too long (a name of 4-byte characters, e.g. emoji): shorten the
  // name too, but never to nothing.
  while (name.runes.length > 1 && utf8.encode(build()).length > kEpcMaxBytes) {
    name = cut(name, name.runes.length - 1).trimRight();
  }
  return build();
}
