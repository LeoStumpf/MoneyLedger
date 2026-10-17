/// G69 (U19): simple statistics of a group's expenses — total spent, per
/// person paid vs. share, per category. Computed locally from the live
/// expenses (payments are transfers, not spending). Pure (no Flutter, no DB).
library;

import '../../core/sync/record_validation.dart';
import '../../models/expense_category.dart';
import '../../models/expense_model.dart';

/// What one participant paid and consumed in one currency (cents).
class PersonStat {
  final String id;
  final int paid;
  final int share;
  const PersonStat({required this.id, required this.paid, required this.share});

  @override
  bool operator ==(Object other) =>
      other is PersonStat &&
      other.id == id &&
      other.paid == paid &&
      other.share == share;

  @override
  int get hashCode => Object.hash(id, paid, share);

  @override
  String toString() => 'PersonStat($id, paid $paid, share $share)';
}

/// The expenses of one category in one currency. [category] null = no
/// category.
class CategoryStat {
  final ResolvedCategory? category;
  final int cents;
  const CategoryStat({required this.category, required this.cents});

  @override
  String toString() => 'CategoryStat(${category?.key}, $cents)';
}

/// The statistics of one currency.
class CurrencyStats {
  final String currency;

  /// Sum of the expense amounts.
  final int total;

  /// Number of expenses.
  final int count;

  /// Everyone who paid or has a share; most paid first, then largest share,
  /// then id (stable).
  final List<PersonStat> people;

  /// Largest first; equal sums keep the order the categories first appear in.
  final List<CategoryStat> categories;

  const CurrencyStats({
    required this.currency,
    required this.total,
    required this.count,
    required this.people,
    required this.categories,
  });
}

/// Statistics of [expenses] per currency (sorted by currency). Categories
/// resolve against the group's [customCategories] (G47): an unknown id
/// counts as *Other*, like in the ledger. An expense with a malformed split
/// (never accepted any more, G18) is left out entirely — like the balances.
List<CurrencyStats> groupStats(
  List<ExpenseModel> expenses, {
  List<CustomCategory> customCategories = const [],
}) {
  final totals = <String, int>{};
  final counts = <String, int>{};
  final paid = <String, Map<String, int>>{};
  final share = <String, Map<String, int>>{};
  final byCategory = <String, Map<String?, (ResolvedCategory?, int)>>{};
  for (final e in expenses) {
    final split = tryParseSplit(e.splitsJson);
    if (split == null) continue;
    final c = e.currency;
    totals[c] = (totals[c] ?? 0) + e.amountCents;
    counts[c] = (counts[c] ?? 0) + 1;
    final p = paid.putIfAbsent(c, () => {});
    p[e.paidBy] = (p[e.paidBy] ?? 0) + e.amountCents;
    final s = share.putIfAbsent(c, () => {});
    split.forEach((id, cents) => s[id] = (s[id] ?? 0) + cents);
    final category = resolveCategory(e.category, customCategories);
    final cats = byCategory.putIfAbsent(c, () => {});
    final prev = cats[category?.key];
    cats[category?.key] = (category, (prev?.$2 ?? 0) + e.amountCents);
  }
  return [
    for (final c in totals.keys.toList()..sort())
      CurrencyStats(
        currency: c,
        total: totals[c]!,
        count: counts[c]!,
        people: [
          for (final id in {...paid[c]!.keys, ...share[c]!.keys})
            PersonStat(
              id: id,
              paid: paid[c]![id] ?? 0,
              share: share[c]![id] ?? 0,
            ),
        ]..sort(_byPaidThenShare),
        categories: _sortedCategories(byCategory[c]!),
      ),
  ];
}

int _byPaidThenShare(PersonStat a, PersonStat b) {
  final p = b.paid.compareTo(a.paid);
  if (p != 0) return p;
  final s = b.share.compareTo(a.share);
  return s != 0 ? s : a.id.compareTo(b.id);
}

List<CategoryStat> _sortedCategories(
  Map<String?, (ResolvedCategory?, int)> cats,
) {
  final list = [
    for (final (i, (category, cents)) in cats.values.indexed)
      (i, CategoryStat(category: category, cents: cents)),
  ];
  // Explicit index tie-breaker: Dart's sort isn't stable.
  list.sort((a, b) {
    final c = b.$2.cents.compareTo(a.$2.cents);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final (_, s) in list) s];
}
