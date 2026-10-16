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
    remainders.add(_Remainder(id, exact - floor, remainders.length));
  });

  // Distribute the leftover cents to the largest remainders first. The leftover
  // is always < (number of positive-weight entries), so candidates never run out.
  var leftover = total - assigned;
  // Dart's sort isn't stable (> 32 elements) — the index makes "ties broken
  // by insertion order" actually hold.
  remainders.sort((a, b) {
    final c = b.frac.compareTo(a.frac);
    return c != 0 ? c : a.index.compareTo(b.index);
  });
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

/// G59: [total] minus the [fixed] amounts, spread **equally** over the [open]
/// ids (largest remainder — sums to the rest exactly). Empty when nothing is
/// left (rest ≤ 0) or nobody is open. Used for "fill the rest" in Exact mode
/// (cents) and Percent mode (hundredths of a percent, see [percentToHundredths]).
Map<String, int> distributeRest(
  int total,
  Map<String, int> fixed,
  List<String> open,
) {
  final rest = remainingForExact(total, fixed);
  if (rest <= 0 || open.isEmpty) return const {};
  return splitEqually(rest, open);
}

/// G59: [amounts] scaled proportionally so they sum to [total] exactly
/// (largest remainder). Entries ≤ 0 stay 0. Empty input or no positive amount →
/// every entry 0 (the caller only offers this when something was typed).
Map<String, int> rescaleProportionally(int total, Map<String, int> amounts) =>
    distributeByWeights(total, amounts);

/// G59: the simplest whole-number shares with the same proportions as
/// [weights] — all equal positive weights → 1 each; whole weights (e.g. cents
/// 1500 / 500) are divided by their GCD (→ 3 / 1); fractional weights (e.g.
/// percents 12.5 / 87.5) are taken in hundredths first. Non-positive weights
/// → 0. Resolving the result against the same total reproduces the original
/// cents exactly when the weights were cents.
Map<String, int> sharesFromWeights(Map<String, num> weights) {
  final positive = [
    for (final w in weights.values)
      if (w > 0) w,
  ];
  if (positive.isEmpty) return {for (final id in weights.keys) id: 0};
  final whole = positive.every((w) => w == w.roundToDouble());
  int scaled(num w) => w <= 0 ? 0 : (whole ? w.round() : (w * 100).round());
  var g = 0;
  for (final w in positive) {
    g = _gcd(g, scaled(w));
  }
  if (g <= 0) g = 1;
  return {for (final e in weights.entries) e.key: scaled(e.value) ~/ g};
}

/// G59: percentages (in hundredths, summing to exactly 100 %) proportional to
/// [weights] — e.g. three equal weights → 33.34 / 33.33 / 33.33. Non-positive
/// weights → 0. Converts with [hundredthsToPercent] for display.
Map<String, num> percentsFromWeights(Map<String, num> weights) =>
    distributeByWeights(
      10000,
      weights,
    ).map((id, h) => MapEntry(id, hundredthsToPercent(h)));

/// G59: a percent value in whole hundredths (33.33 → 3333).
int percentToHundredths(num percent) => (percent * 100).round();

/// G59: hundredths back to a percent — an int when whole (5000 → 50),
/// else a double (3334 → 33.34).
num hundredthsToPercent(int hundredths) =>
    hundredths % 100 == 0 ? hundredths ~/ 100 : hundredths / 100;

int _gcd(int a, int b) {
  while (b != 0) {
    final t = a % b;
    a = b;
    b = t;
  }
  return a.abs();
}

class _Remainder {
  final String id;
  final double frac;
  final int index;
  _Remainder(this.id, this.frac, this.index);
}
