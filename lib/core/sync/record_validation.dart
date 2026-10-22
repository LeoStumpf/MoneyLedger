import 'dart:convert';

import '../../models/exchange_rates.dart';
import '../../models/expense_category.dart';
import '../../models/expense_date.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../link/link_uri.dart' show decodeLinkSecret;

/// Content rules every expense / payment must satisfy (G18 review) — plain
/// Dart, shared by the inbound gate (`RecordGate` refuses violations as
/// `invalid_record`), the CSV import and the input forms.

/// Upper bound of an amount: 10^13 cents (≈ 100 billion in any currency).
/// Keeps every sum of amounts far below 2^53 (exact in JS doubles too).
const kMaxAmountCents = 10000000000000;

/// Whether [cents] is a storable amount: at least one cent, at most
/// [kMaxAmountCents].
bool isValidAmountCents(int cents) => cents >= 1 && cents <= kMaxAmountCents;

/// The `{participantId: cents}` split in [splitsJson], or null when it is
/// not a JSON object of non-empty string keys and non-negative int values.
Map<String, int>? tryParseSplit(String splitsJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(splitsJson);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final out = <String, int>{};
  for (final MapEntry(:key, :value) in decoded.entries) {
    if (key is! String || key.isEmpty || value is! int || value < 0) {
      return null;
    }
    out[key] = value;
  }
  return out;
}

/// Why [e] is not a valid expense version, or null when it is: the amount is
/// out of range, there is no payer, or the split isn't a non-empty
/// `{participant: cents}` map summing exactly to the amount; G49: a `date`
/// that isn't an acceptable calendar day ([recordDateProblem]; [now] is
/// for tests).
String? expenseProblem(ExpenseModel e, {DateTime? now}) {
  if (!isValidAmountCents(e.amountCents)) return 'amount ${e.amountCents}';
  if (e.paidBy.isEmpty) return 'no payer';
  if (e.currency.isEmpty) return 'no currency';
  final split = tryParseSplit(e.splitsJson);
  if (split == null || split.isEmpty) return 'malformed split';
  final sum = split.values.fold<int>(0, (a, b) => a + b);
  if (sum != e.amountCents) return 'split sums to $sum, not ${e.amountCents}';
  final date = e.date;
  if (date != null) return recordDateProblem(date, now: now);
  return null;
}

/// Why [s] is not a valid payment version, or null when it is: the amount
/// is out of range, a side is missing, or someone pays themselves; G60: a
/// `date` that isn't an acceptable calendar day ([recordDateProblem]).
String? settlementProblem(SettlementModel s, {DateTime? now}) {
  if (!isValidAmountCents(s.amountCents)) return 'amount ${s.amountCents}';
  if (s.currency.isEmpty) return 'no currency';
  if (s.fromUser.isEmpty || s.toUser.isEmpty) return 'missing participant';
  if (s.fromUser == s.toUser) return 'payment to oneself';
  final date = s.date;
  if (date != null) return recordDateProblem(date, now: now);
  return null;
}

/// Why [g] is not a valid group-meta version, or null when it is (G47): its
/// custom categories break the bounds — more than [kMaxCustomCategories], an
/// id that isn't `c:…` (≤ [kMaxCustomCategoryIdLength]) or appears twice, a
/// name that isn't trimmed / 1 … [kMaxCategoryNameLength] long
/// ([isValidCategoryName]), or an icon outside [kCustomCategoryIcons].
String? groupMetaProblem(GroupModel g) {
  // G53: the link state — a link with a positive epoch and a canonical
  // 32-byte secret; a non-negative lock time.
  final link = g.link;
  if (link != null) {
    if (link.epoch < 1) return 'link epoch ${link.epoch}';
    try {
      decodeLinkSecret(link.secret);
    } catch (_) {
      return 'link secret';
    }
  }
  final lockedAt = g.lockedAt;
  if (lockedAt != null && lockedAt < 0) return 'locked_at $lockedAt';
  final fxProblem = exchangeRatesProblem(g.exchangeRates);
  if (fxProblem != null) return fxProblem;
  final cats = g.categories;
  if (cats.length > kMaxCustomCategories) {
    return '${cats.length} categories';
  }
  final ids = <String>{};
  for (final c in cats) {
    if (!isCustomCategoryId(c.id) ||
        c.id.length <= kCustomCategoryPrefix.length ||
        c.id.length > kMaxCustomCategoryIdLength) {
      return 'category id "${c.id}"';
    }
    if (!ids.add(c.id)) return 'duplicate category ${c.id}';
    if (!isValidCategoryName(c.name)) return 'category name of ${c.id}';
    if (!kCustomCategoryIcons.contains(c.icon)) {
      return 'category icon "${c.icon}"';
    }
  }
  return null;
}

/// G73: why [fx] isn't a valid `exchange_rates` value (null = valid or
/// absent): the base isn't a currency code, there is no rate or more than
/// [kMaxExchangeRates], a rate names an invalid code or the base itself, or
/// a value isn't a canonical positive decimal ([isValidRate]).
String? exchangeRatesProblem(ExchangeRates? fx) {
  if (fx == null) return null;
  if (!isCurrencyCode(fx.base)) return 'exchange rate base "${fx.base}"';
  if (fx.rates.isEmpty) return 'no exchange rates';
  if (fx.rates.length > kMaxExchangeRates) {
    return '${fx.rates.length} exchange rates';
  }
  for (final MapEntry(key: code, value: rate) in fx.rates.entries) {
    if (!isCurrencyCode(code) || code == fx.base) {
      return 'exchange rate currency "$code"';
    }
    if (!isValidRate(rate)) return 'exchange rate of $code';
  }
  return null;
}

/// Whether [id] is a syntactically valid Matrix user ID (G18 review):
/// `@localpart:server` — a non-empty localpart without `:` / whitespace, a
/// non-empty server name (may carry a port / IPv6 literal) without
/// whitespace, at most 255 characters. Local mode's pseudo account
/// (`local:self`) is **not** one.
bool isValidMxid(String? id) =>
    id != null && id.length <= 255 && _mxidPattern.hasMatch(id);

final _mxidPattern = RegExp(r'^@[^\s:]+:[^\s]+$');

/// Why [m] is not a valid participant version, or null when it is: a claim
/// ([MemberModel.matrixId]) that isn't a valid MXID ([isValidMxid]) — e.g.
/// local mode's pseudo account planted by a peer, which would otherwise be
/// taken for "me" by a local-mode restore / adoption, or reach the device-key
/// lookup as a replication target. [allowLocalClaim]: a claim by local
/// mode's pseudo account ([kLocalClaimId]) is fine — local mode's own backup.
String? memberProblem(MemberModel m, {bool allowLocalClaim = false}) {
  final claim = m.matrixId;
  if (claim == null || isValidMxid(claim)) return null;
  if (allowLocalClaim && claim == kLocalClaimId) return null;
  return 'invalid matrix id';
}

/// Local mode's pseudo account (`kLocalAccountId` in `app_session.dart`,
/// repeated here to keep this file plain Dart; a test pins them equal).
const kLocalClaimId = 'local:self';
