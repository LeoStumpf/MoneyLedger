/// G74: the user's own payment details (bank account / PayPal.me) and the
/// two things built from them when someone owes the user money — a
/// GiroCode (EPC QR code, "BCD" payload v002) and a PayPal.me link with the
/// amount. Pure Dart: no Flutter, no DB.
///
/// The details are **device-local** (per ledger, `AppSettings`
/// `payment_details`): they are never synced, never in a backup / CSV /
/// snapshot, and only leave the device as a QR code on its own screen or a
/// link the user shares himself. Showing them to the others in a group
/// (the plan's synced variant) needs a wire decision — see plan.md G74.
library;

import 'dart:convert';

import '../../core/l10n/currencies.dart';

/// The user's payment details. Every field is optional; [iban] / [bic] are
/// stored normalised (no spaces, upper case), [paypalMe] as the bare user
/// name.
class PaymentDetails {
  const PaymentDetails({this.name, this.iban, this.bic, this.paypalMe});

  /// Account holder — required by a GiroCode (max. 70 characters there).
  final String? name;
  final String? iban;
  final String? bic;
  final String? paypalMe;

  static const empty = PaymentDetails();

  bool get hasBankAccount => iban != null && name != null;
  bool get hasPaypal => paypalMe != null;
  bool get isEmpty => !hasBankAccount && !hasPaypal;

  String encode() => jsonEncode({
    'name': ?name,
    'iban': ?iban,
    'bic': ?bic,
    'paypal_me': ?paypalMe,
  });

  /// Null for null / unreadable input or nothing usable.
  static PaymentDetails? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      String? s(String k) {
        final v = m[k];
        return v is String && v.trim().isNotEmpty ? v.trim() : null;
      }

      final d = PaymentDetails(
        name: s('name'),
        iban: s('iban'),
        bic: s('bic'),
        paypalMe: s('paypal_me'),
      );
      return d == empty ? null : d;
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PaymentDetails &&
      other.name == name &&
      other.iban == iban &&
      other.bic == bic &&
      other.paypalMe == paypalMe;

  @override
  int get hashCode => Object.hash(name, iban, bic, paypalMe);

  /// Never prints the account data (logs).
  @override
  String toString() =>
      'PaymentDetails(bank: $hasBankAccount, paypal: $hasPaypal)';
}

// ── IBAN / BIC ───────────────────────────────────────────────────────────────

/// IBAN lengths of the SEPA countries most users of the app are in; other
/// countries are checked by format + checksum only.
const kIbanLengths = <String, int>{
  'AD': 24,
  'AT': 20,
  'BE': 16,
  'BG': 22,
  'CH': 21,
  'CY': 28,
  'CZ': 24,
  'DE': 22,
  'DK': 18,
  'EE': 20,
  'ES': 24,
  'FI': 18,
  'FR': 27,
  'GB': 22,
  'GR': 27,
  'HR': 21,
  'HU': 28,
  'IE': 22,
  'IS': 26,
  'IT': 27,
  'LI': 21,
  'LT': 20,
  'LU': 20,
  'LV': 21,
  'MC': 27,
  'MT': 31,
  'NL': 18,
  'NO': 15,
  'PL': 28,
  'PT': 25,
  'RO': 24,
  'SE': 24,
  'SI': 19,
  'SK': 24,
  'SM': 27,
};

/// [input] without spaces / dashes, upper case.
String normalizeIban(String input) =>
    input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

/// Whether [iban] (normalised) is a well-formed IBAN with a valid mod-97
/// checksum (ISO 13616) and, for a known country, the right length.
bool isValidIban(String iban) {
  if (!RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$').hasMatch(iban)) {
    return false;
  }
  final len = kIbanLengths[iban.substring(0, 2)];
  if (len != null && iban.length != len) return false;
  final rearranged = iban.substring(4) + iban.substring(0, 4);
  var rest = 0;
  for (final unit in rearranged.codeUnits) {
    // 0-9 → 0-9, A-Z → 10-35.
    final v = unit <= 0x39 ? unit - 0x30 : unit - 0x41 + 10;
    rest = v >= 10 ? (rest * 100 + v) % 97 : (rest * 10 + v) % 97;
  }
  return rest == 1;
}

/// [iban] in groups of four ("DE89 3704 0044 …") for reading.
String formatIban(String iban) => [
  for (var i = 0; i < iban.length; i += 4)
    iban.substring(i, i + 4 > iban.length ? iban.length : i + 4),
].join(' ');

String normalizeBic(String input) =>
    input.replaceAll(RegExp(r'\s'), '').toUpperCase();

/// ISO 9362: bank (4 letters), country (2), location (2), branch (3, opt.).
bool isValidBic(String bic) =>
    RegExp(r'^[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?$').hasMatch(bic);

// ── PayPal.me ────────────────────────────────────────────────────────────────

/// The PayPal.me user name in [input] — accepts "name", "@name",
/// "paypal.me/name" and "https://www.paypal.me/name/…"; null if it isn't
/// one (letters and digits, 1 … 20 — PayPal's rule).
String? normalizePaypalMe(String input) {
  var s = input.trim();
  s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  s = s.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
  s = s.replaceFirst(RegExp(r'^paypal\.me/', caseSensitive: false), '');
  if (s.startsWith('@')) s = s.substring(1);
  final slash = s.indexOf('/');
  if (slash >= 0) s = s.substring(0, slash);
  return RegExp(r'^[A-Za-z0-9]{1,20}$').hasMatch(s) ? s : null;
}

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

  final head = [
    'BCD',
    '002',
    '1', // UTF-8
    'SCT',
    details.bic ?? '',
    cut(clean(details.name!), 70),
    details.iban!,
    if (cents >= 1 && cents <= kEpcMaxCents)
      'EUR${_plainAmount(cents, 'EUR')}'
    else
      '',
  ];
  var text = cut(clean(remittance ?? ''), 140);
  String build() => [
    ...head,
    if (text.isNotEmpty) ...['', '', text],
  ].join('\n');
  while (text.isNotEmpty && utf8.encode(build()).length > kEpcMaxBytes) {
    text = cut(text, text.runes.length - 1).trimRight();
  }
  return build();
}
