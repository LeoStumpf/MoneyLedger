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
Map<String, int> splitEqually(int total, List<String> ids, {int step = 1}) =>
    distributeByWeights(total, {for (final id in ids) id: 1}, step: step);

/// Splits [total] in proportion to integer [weights] (e.g. {a:2, b:1, c:1}).
/// Zero/negative weights receive nothing.
Map<String, int> splitByShares(
  int total,
  Map<String, int> weights, {
  int step = 1,
}) => distributeByWeights(total, weights, step: step);

/// Splits [total] in proportion to [percents] (e.g. {a:50, b:30, c:20}). The
/// percents need not be exactly 100 — the result is proportional regardless and
/// always sums to [total]; the UI enforces the 100% rule for the user.
Map<String, int> splitByPercent(
  int total,
  Map<String, num> percents, {
  int step = 1,
}) => distributeByWeights(total, percents, step: step);

/// Core largest-remainder distribution: hand out [total] cents in proportion to
/// [weights], flooring each share then giving the leftover cents one-by-one to
/// the largest fractional remainders (ties broken by insertion order, so the
/// result is deterministic). Guarantees `sum(result) == total` when total ≥ 0
/// and at least one weight is positive. Entries with a non-positive weight get
/// 0 and never receive a leftover cent. Keys preserve [weights] order.
///
/// G66: [step] is the currency's smallest amount in cents (`currencyStep`:
/// 100 for JPY & co.) — the total is handed out in whole steps, so every
/// share is a whole yen. A (legacy) total that isn't a multiple of [step] is
/// split cent-exact as before ([step] ignored), so stored splits of old
/// data reopen unchanged.
Map<String, int> distributeByWeights(
  int total,
  Map<String, num> weights, {
  int step = 1,
}) {
  if (step > 1 && total > 0 && total % step == 0) {
    return distributeByWeights(
      total ~/ step,
      weights,
    ).map((id, units) => MapEntry(id, units * step));
  }
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
///
/// G66: [step] as in [distributeByWeights] (an equal JPY split is in whole
/// yen; the cent-exact form is accepted too, for splits stored before).
bool isEqualSplit(Map<String, int> map, {int step = 1}) {
  if (map.isEmpty) return false;
  if (step > 1 && isEqualSplit(map)) return true;
  final total = map.values.fold(0, (a, b) => a + b);
  final canonical = splitEqually(total, map.keys.toList(), step: step);
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
  List<String> open, {
  int step = 1,
}) {
  final rest = remainingForExact(total, fixed);
  if (rest <= 0 || open.isEmpty) return const {};
  return splitEqually(rest, open, step: step);
}

/// G59: [amounts] scaled proportionally so they sum to [total] exactly
/// (largest remainder). Entries ≤ 0 stay 0. Empty input or no positive amount →
/// every entry 0 (the caller only offers this when something was typed).
Map<String, int> rescaleProportionally(
  int total,
  Map<String, int> amounts, {
  int step = 1,
}) => distributeByWeights(total, amounts, step: step);

/// G59: the simplest whole-number shares with the same proportions as
/// [weights] — all equal positive weights → 1 each; whole weights (e.g. cents
/// 1500 / 500) are divided by their GCD (→ 3 / 1); fractional weights (e.g.
/// percents 12.5 / 87.5) are taken in hundredths first. Non-positive weights
/// → 0. Resolving the result against the same total reproduces the original
/// cents exactly when the weights were cents.
///
/// G61: with a [total] > 0, uneven amounts no longer give big numbers
/// (3.33 / 6.67 € → 333 / 667): the smallest "nice" shares summing to at most
/// [kMaxNiceShares] are preferred when they resolve against [total] to
/// **exactly** the same cents as [weights] do (here 1 / 2). Every positive
/// weight keeps ≥ 1 share (nobody drops out). Else the exact GCD form.
Map<String, int> sharesFromWeights(
  Map<String, num> weights, {
  int total = 0,
  int step = 1,
}) {
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
  final exact = {for (final e in weights.entries) e.key: scaled(e.value) ~/ g};
  if (total <= 0) return exact;
  final exactSum = exact.values.fold(0, (a, b) => a + b);
  final target = distributeByWeights(total, weights, step: step);
  for (
    var sum = positive.length;
    sum < exactSum && sum <= kMaxNiceShares;
    sum++
  ) {
    final candidate = distributeByWeights(sum, weights);
    final keepsEveryone = weights.entries.every(
      (e) => e.value <= 0 || candidate[e.key]! > 0,
    );
    if (keepsEveryone &&
        _sameSplit(distributeByWeights(total, candidate, step: step), target)) {
      return candidate;
    }
  }
  return exact;
}

/// G61: the largest share sum [sharesFromWeights] tries before falling back
/// to the exact (GCD) form.
const kMaxNiceShares = 20;

bool _sameSplit(Map<String, int> a, Map<String, int> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

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

/// G77: how the rest of an itemized receipt (total − items: tax, tip, what
/// wasn't itemized) is shared.
enum ItemRestMode {
  /// In proportion to each person's item subtotal (the default — tax and a
  /// tip usually scale with what one had).
  proportional,

  /// Equally among everyone who shares at least one item.
  equal,
}

/// G77: one receipt line — [cents] split equally among [people]
/// (participant ids, in the order given). An item with no people counts
/// towards the rest (not assigned to anyone).
class SplitItem {
  final int cents;
  final List<String> people;
  const SplitItem(this.cents, this.people);
}

/// G77: the sum of every item with a positive amount (with or without
/// people) — what the receipt total must at least be.
int itemsSum(List<SplitItem> items) =>
    items.where((i) => i.cents > 0).fold(0, (a, i) => a + i.cents);

/// G77: an itemized split of [total] — each item (amount > 0, ≥ 1 person) is
/// split equally among its people (largest remainder, [step] as in
/// [distributeByWeights]); the rest (`total − assigned items`, incl. items
/// nobody shares) is spread per [restMode]. The result is an Exact split that
/// **sums to [total] exactly**; people who end with 0 (in no item, or a
/// cent item that didn't reach them) are absent. Keys follow each person's
/// first appearance in [items].
///
/// Null when there is nothing to split this way: [total] ≤ 0, the items
/// exceed the total ([itemsSum] > [total] — "X too much"), or no item with
/// an amount has anyone.
Map<String, int>? splitByItems(
  int total,
  List<SplitItem> items, {
  ItemRestMode restMode = ItemRestMode.proportional,
  int step = 1,
}) {
  if (total <= 0 || itemsSum(items) > total) return null;
  final subtotal = <String, int>{};
  var assigned = 0;
  for (final item in items) {
    if (item.cents <= 0 || item.people.isEmpty) continue;
    assigned += item.cents;
    splitEqually(
      item.cents,
      item.people.toSet().toList(),
      step: step,
    ).forEach((id, c) => subtotal[id] = (subtotal[id] ?? 0) + c);
  }
  if (subtotal.isEmpty) return null;
  final rest = total - assigned;
  if (rest > 0) {
    final extra = switch (restMode) {
      ItemRestMode.proportional =>
        // Every assigned item gives someone ≥ 1 cent, so a weight is > 0.
        distributeByWeights(rest, subtotal, step: step),
      ItemRestMode.equal => splitEqually(
        rest,
        subtotal.keys.toList(),
        step: step,
      ),
    };
    extra.forEach((id, c) => subtotal[id] = subtotal[id]! + c);
  }
  subtotal.removeWhere((_, c) => c <= 0);
  return subtotal;
}

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
