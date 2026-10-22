import 'dart:convert';

import 'expense_model.dart';

/// G76 — several people paid one expense.
///
/// On the wire (and in the signed body / G27 hash) a multi-payer expense
/// carries an optional `payers: {participantId: cents}` map and an **empty**
/// `paid_by`; a single-payer expense keeps the pre-G76 shape (`paid_by` =
/// the payer, no `payers`). The empty `paid_by` is deliberate: a pre-G76
/// build refuses such a version as "no payer" (`invalid_record`) — on the
/// signed **and** the unsigned link path — instead of reading one person as
/// the payer of everything.

/// Most payers of one expense (bounds the wire size; a split has no bound
/// either, but a payer map larger than the group is nonsense).
const kMaxPayers = 100;

/// The `{participantId: cents}` map in [json], or null when it is not a
/// JSON object of non-empty string keys and int values.
Map<String, int>? tryParsePayers(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final out = <String, int>{};
  for (final MapEntry(:key, :value) in decoded.entries) {
    if (key is! String || key.isEmpty || value is! int) return null;
    out[key] = value;
  }
  return out;
}

/// Who paid how much of [e]: `{paidBy: amount}` for a single payer, the
/// parsed `payers` map for several (empty when malformed or no payer —
/// such a version never passes the content rules).
Map<String, int> paidAmountsOf(ExpenseModel e) {
  final json = e.payersJson;
  if (json == null) {
    return e.paidBy.isEmpty ? const {} : {e.paidBy: e.amountCents};
  }
  return tryParsePayers(json) ?? const {};
}

/// Whether several people paid [e] (G76).
bool hasSeveralPayers(ExpenseModel e) => e.payersJson != null;

/// Whether [participant] paid (part of) [e].
bool paidByParticipant(ExpenseModel e, String participant) =>
    (paidAmountsOf(e)[participant] ?? 0) > 0;

/// The model fields for [payers] (`{participant: cents}`): people at 0 are
/// dropped; one payer left → the pre-G76 shape (`paidBy` = them, no
/// `payersJson`); several → `paidBy` `''` + the map. Null when nobody paid.
({String paidBy, String? payersJson})? payerFields(Map<String, int> payers) {
  final paying = {
    for (final e in payers.entries)
      if (e.value > 0) e.key: e.value,
  };
  if (paying.isEmpty) return null;
  if (paying.length == 1) {
    return (paidBy: paying.keys.single, payersJson: null);
  }
  return (paidBy: '', payersJson: jsonEncode(paying));
}
