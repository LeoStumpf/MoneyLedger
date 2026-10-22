/// G74: a person's payment details (bank account / PayPal.me) and their
/// checks — pure Dart. Stored device-local (`AppSettings`
/// `payment_details`) and, since the G74 wire bundle, carried as the
/// optional signed `payment` field of the member record (only when set).
library;

import 'dart:convert';

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

  String encode() => jsonEncode(toJson());

  /// The wire / stored form: only the fields that are set.
  Map<String, Object?> toJson() => {
    'name': ?name,
    'iban': ?iban,
    'bic': ?bic,
    'paypal_me': ?paypalMe,
  };

  /// G74: the member payload's `payment` value — null when absent; a
  /// present but malformed value (not an object of string fields, unknown
  /// keys, nothing set) reads as [invalid] so the content rules refuse the
  /// version instead of silently dropping the field (it is signed).
  static PaymentDetails? fromWire(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map || raw.isEmpty) return invalid;
    const keys = {'name', 'iban', 'bic', 'paypal_me'};
    if (!raw.keys.every(keys.contains) ||
        !raw.values.every((v) => v is String)) {
      return invalid;
    }
    return PaymentDetails(
      name: raw['name'] as String?,
      iban: raw['iban'] as String?,
      bic: raw['bic'] as String?,
      paypalMe: raw['paypal_me'] as String?,
    );
  }

  /// Stands in for a malformed wire value (refused by `paymentProblem`).
  static const invalid = PaymentDetails(name: '');

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
  // PayPal's own share links end in "?country.x=DE&locale.x=de_DE".
  final end = s.indexOf(RegExp(r'[/?#]'));
  if (end >= 0) s = s.substring(0, end);
  return RegExp(r'^[A-Za-z0-9]{1,20}$').hasMatch(s) ? s : null;
}
