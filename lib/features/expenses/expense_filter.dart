/// G16: search / filter for a group's ledger list (plain Dart, unit-tested).
library;

import '../../models/expense_category.dart';
import '../../models/expense_model.dart';
import '../../models/expense_payers.dart';
import '../balance/balance_calculator.dart' show splitsOf;

/// What the expense list currently shows: a free-text [query] (description,
/// note, payer name; for payments the two names), a set of [categories]
/// (empty = any; keys of [ResolvedCategory] — a built-in wire id or a
/// custom `c:` id, G47; an expense without a category matches none of them,
/// payments never match a category filter) and [involvingMe] (I paid, I
/// share in it, or I'm one side of the payment).
class LedgerFilter {
  final String query;
  final Set<String> categories;
  final bool involvingMe;

  const LedgerFilter({
    this.query = '',
    this.categories = const {},
    this.involvingMe = false,
  });

  static const none = LedgerFilter();

  /// Whether anything is filtered at all.
  bool get isActive =>
      query.trim().isNotEmpty || categories.isNotEmpty || involvingMe;

  LedgerFilter copyWith({
    String? query,
    Set<String>? categories,
    bool? involvingMe,
  }) => LedgerFilter(
    query: query ?? this.query,
    categories: categories ?? this.categories,
    involvingMe: involvingMe ?? this.involvingMe,
  );

  /// A copy with the category key [c] toggled in [categories].
  LedgerFilter toggleCategory(String c) => copyWith(
    categories: categories.contains(c)
        ? ({...categories}..remove(c))
        : {...categories, c},
  );
}

/// Case- and accent-insensitive normal form for matching ("Café" ~ "cafe",
/// "Pastéis" ~ "pasteis"; only the common Latin-1 accents are folded).
String _fold(String s) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString();
}

/// Whether [e] passes [f]. [nameOf] resolves participant ids to display
/// names (for the payer search); [myId] is this account's participant id
/// (null = not a participant → "involving me" matches nothing).
/// [customCategories]: the group's custom categories (G47) — an id the
/// group doesn't define counts as "other".
bool expenseMatches(
  ExpenseModel e,
  LedgerFilter f, {
  required String Function(String id) nameOf,
  required String? myId,
  List<CustomCategory> customCategories = const [],
}) {
  if (f.categories.isNotEmpty) {
    final c = resolveCategory(e.category, customCategories);
    if (c == null || !f.categories.contains(c.key)) return false;
  }
  if (f.involvingMe) {
    if (myId == null) return false;
    if (!paidAmountsOf(e).containsKey(myId) && !splitsOf(e).containsKey(myId)) {
      return false;
    }
  }
  final q = _fold(f.query.trim());
  if (q.isEmpty) return true;
  return [
    e.description,
    e.note ?? '',
    // G76: every payer's name.
    for (final payer in paidAmountsOf(e).keys) nameOf(payer),
  ].any((field) => _fold(field).contains(q));
}

/// Whether payment [s] passes [f] — see [expenseMatches]; [paymentLabel] is
/// the localized word "Payment" so searching for it lists all payments.
bool settlementMatches(
  SettlementModel s,
  LedgerFilter f, {
  required String Function(String id) nameOf,
  required String? myId,
  String paymentLabel = '',
}) {
  if (f.categories.isNotEmpty) return false;
  if (f.involvingMe &&
      (myId == null || (s.fromUser != myId && s.toUser != myId))) {
    return false;
  }
  final q = _fold(f.query.trim());
  if (q.isEmpty) return true;
  return [
    nameOf(s.fromUser),
    nameOf(s.toUser),
    paymentLabel,
  ].any((field) => field.isNotEmpty && _fold(field).contains(q));
}

/// The categories used by the live [expenses], in picker order (built-in
/// ones, then the group's [custom] ones — hidden ones too while used) — the
/// filter chips offered for this group.
List<ResolvedCategory> usedCategories(
  Iterable<ExpenseModel> expenses, [
  List<CustomCategory> custom = const [],
]) {
  final used = {
    for (final e in expenses) ?resolveCategory(e.category, custom)?.key,
  };
  return [
    for (final c in ExpenseCategory.values)
      if (used.contains(c.wire)) ResolvedCategory.builtin(c),
    for (final c in custom)
      if (used.contains(c.id)) ResolvedCategory.custom(c),
  ];
}
