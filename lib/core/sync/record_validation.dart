import 'dart:convert';

import '../../models/expense_model.dart';

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
/// `{participant: cents}` map summing exactly to the amount.
String? expenseProblem(ExpenseModel e) {
  if (!isValidAmountCents(e.amountCents)) return 'amount ${e.amountCents}';
  if (e.paidBy.isEmpty) return 'no payer';
  if (e.currency.isEmpty) return 'no currency';
  final split = tryParseSplit(e.splitsJson);
  if (split == null || split.isEmpty) return 'malformed split';
  final sum = split.values.fold<int>(0, (a, b) => a + b);
  if (sum != e.amountCents) return 'split sums to $sum, not ${e.amountCents}';
  return null;
}

/// Why [s] is not a valid payment version, or null when it is: the amount
/// is out of range, a side is missing, or someone pays themselves.
String? settlementProblem(SettlementModel s) {
  if (!isValidAmountCents(s.amountCents)) return 'amount ${s.amountCents}';
  if (s.currency.isEmpty) return 'no currency';
  if (s.fromUser.isEmpty || s.toUser.isEmpty) return 'missing participant';
  if (s.fromUser == s.toUser) return 'payment to oneself';
  return null;
}
