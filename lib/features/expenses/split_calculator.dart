/// Pure-Dart split math (Phase E). Turns a total and a per-mode set of inputs
/// into a `{participantId: cents}` map that **sums to the total exactly** via
/// largest-remainder rounding — so no cent is ever lost or invented.
///
/// No Flutter, no DB, no models — strings and ints only, fully unit-testable.
/// The resolved cents map is the single source of truth everywhere downstream
/// (DB `splitsJson`, the wire `split`, balance calc, CSV); the split *mode* and
/// raw inputs (weights/percents) are intentionally **not** persisted. On edit
/// the opening mode is inferred with [isEqualSplit].
library;

/// Splits [total] equally across [ids]. With a remainder, the leftover cents go
/// one each to the first ids (e.g. 100¢ across 3 → 34, 33, 33).
Map<String, int> splitEqually(int total, List<String> ids) =>
    distributeByWeights(total, {for (final id in ids) id: 1});

/// Splits [total] in proportion to integer [weights] (e.g. {a:2, b:1, c:1}).
/// Zero/negative weights receive nothing.
Map<String, int> splitByShares(int total, Map<String, int> weights) =>
    distributeByWeights(total, weights);

/// Splits [total] in proportion to [percents] (e.g. {a:50, b:30, c:20}). The
/// percents need not be exactly 100 — the result is proportional regardless and
/// always sums to [total]; the UI enforces the 100% rule for the user.
Map<String, int> splitByPercent(int total, Map<String, num> percents) =>
    distributeByWeights(total, percents);

/// Core largest-remainder distribution: hand out [total] cents in proportion to
/// [weights], flooring each share then giving the leftover cents one-by-one to
/// the largest fractional remainders (ties broken by insertion order, so the
/// result is deterministic). Guarantees `sum(result) == total` when total ≥ 0
/// and at least one weight is positive. Entries with a non-positive weight get
/// 0 and never receive a leftover cent. Keys preserve [weights] order.
Map<String, int> distributeByWeights(int total, Map<String, num> weights) {
  final result = {for (final id in weights.keys) id: 0};
  if (total <= 0) return result;

  final totalWeight = weights.values
      .where((w) => w > 0)
      .fold<num>(0, (a, b) => a + b);
  if (totalWeight <= 0) return result;

  // Floor each share; track the fractional remainder for leftover assignment.
  final remainders = <_Remainder>[];
  var assigned = 0;
  weights.forEach((id, weight) {
    if (weight <= 0) return;
    final exact = total * weight / totalWeight;
    final floor = exact.floor();
    result[id] = floor;
    assigned += floor;
    remainders.add(_Remainder(id, exact - floor));
  });

  // Distribute the leftover cents to the largest remainders first. The leftover
  // is always < (number of positive-weight entries), so candidates never run out.
  var leftover = total - assigned;
  remainders.sort((a, b) => b.frac.compareTo(a.frac));
  for (var i = 0; leftover > 0 && i < remainders.length; i++, leftover--) {
    result[remainders[i].id] = result[remainders[i].id]! + 1;
  }
  return result;
}

/// The amount still unassigned in **exact** mode: `total - sum(entered)`. May be
/// negative if the user has over-allocated. Zero means the split is valid.
int remainingForExact(int total, Map<String, int> entered) =>
    total - entered.values.fold(0, (a, b) => a + b);

/// True iff [map] is exactly the canonical equal split of its own total across
/// its keys — i.e. what [splitEqually] would produce. Used on edit to reopen an
/// expense in Equal mode (vs. Exact). A near-equal map with the extra cent on a
/// different person reads as not-equal, which harmlessly opens in Exact mode.
bool isEqualSplit(Map<String, int> map) {
  if (map.isEmpty) return false;
  final total = map.values.fold(0, (a, b) => a + b);
  final canonical = splitEqually(total, map.keys.toList());
  for (final id in map.keys) {
    if (map[id] != canonical[id]) return false;
  }
  return true;
}

class _Remainder {
  final String id;
  final double frac;
  _Remainder(this.id, this.frac);
}
