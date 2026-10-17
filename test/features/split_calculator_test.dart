/// Pure split math (Phase E, M1): every mode must sum to the total exactly via
/// largest-remainder rounding, and `isEqualSplit` must drive edit-mode inference.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/expenses/split_calculator.dart';

int _sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

void main() {
  // G18 review (finding 16): Dart's sort isn't stable beyond 32 elements —
  // the leftover cents must still go to the first ids in insertion order.
  test('ties go by insertion order with many weighted participants', () {
    // Equal weights tie on the fractional remainder: the extra cents must go
    // to the earliest of them (failed with Dart's unstable sort, e.g. n=34,
    // total=1: the cent went to a later weight-2 participant).
    for (final n in [34, 40, 65]) {
      final weights = {for (var i = 0; i < n; i++) 'p$i': i.isEven ? 1 : 2};
      for (final total in [1, 7, 100, 999]) {
        final r = splitByShares(total, weights);
        expect(r.values.fold<int>(0, (a, b) => a + b), total);
        for (final w in [1, 2]) {
          final shares = [
            for (var i = 0; i < n; i++)
              if (weights['p$i'] == w) r['p$i']!,
          ];
          for (var i = 1; i < shares.length; i++) {
            expect(
              shares[i],
              lessThanOrEqualTo(shares[i - 1]),
              reason: 'n=$n total=$total weight=$w #$i',
            );
          }
        }
      }
    }
  });

  test('ties go by insertion order with many participants', () {
    for (final n in [33, 40, 64, 100]) {
      final ids = [for (var i = 0; i < n; i++) 'p$i'];
      final total = n * 2 + n ~/ 2; // every share 2.5 (or 2.x): equal fracs
      final r = splitEqually(total, ids);
      expect(r.values.fold<int>(0, (a, b) => a + b), total);
      final extra = total - 2 * n;
      for (var i = 0; i < n; i++) {
        expect(r['p$i'], i < extra ? 3 : 2, reason: 'n=$n, p$i');
      }
    }
  });

  group('splitEqually', () {
    test('divides evenly when it divides evenly', () {
      expect(splitEqually(900, ['a', 'b', 'c']), {
        'a': 300,
        'b': 300,
        'c': 300,
      });
    });

    test('gives the leftover cents to the first ids (100¢ ÷ 3)', () {
      final s = splitEqually(100, ['a', 'b', 'c']);
      expect(s, {'a': 34, 'b': 33, 'c': 33});
      expect(_sum(s), 100); // never loses the cent today's round() drops
    });

    test('two leftover cents go to the first two ids', () {
      final s = splitEqually(101, ['a', 'b', 'c']);
      expect(s, {'a': 34, 'b': 34, 'c': 33});
      expect(_sum(s), 101);
    });

    test('a single participant gets the whole total', () {
      expect(splitEqually(4200, ['a']), {'a': 4200});
    });

    test('sums to total across many awkward divisions', () {
      for (final total in [1, 7, 99, 100, 4201, 99999]) {
        for (final n in [1, 2, 3, 4, 7, 13]) {
          final ids = [for (var i = 0; i < n; i++) 'p$i'];
          expect(
            _sum(splitEqually(total, ids)),
            total,
            reason: 'total=$total n=$n',
          );
        }
      }
    });
  });

  group('splitByShares', () {
    test('distributes in proportion to weights', () {
      expect(splitByShares(400, {'a': 2, 'b': 1, 'c': 1}), {
        'a': 200,
        'b': 100,
        'c': 100,
      });
    });

    test('proportional with a remainder still sums exactly', () {
      final s = splitByShares(100, {'a': 2, 'b': 1}); // 66.66 / 33.33
      expect(_sum(s), 100);
      expect(s['a'], greaterThan(s['b']!));
    });

    test('zero-weight participants receive nothing and no leftover cent', () {
      final s = splitByShares(100, {'a': 1, 'b': 1, 'c': 0});
      expect(s['c'], 0);
      expect(_sum(s), 100);
    });

    test('all-zero weights yield an all-zero map (guarded)', () {
      expect(splitByShares(100, {'a': 0, 'b': 0}), {'a': 0, 'b': 0});
    });
  });

  group('splitByPercent', () {
    test('converts percentages to cents summing to total', () {
      final s = splitByPercent(1000, {'a': 50, 'b': 30, 'c': 20});
      expect(s, {'a': 500, 'b': 300, 'c': 200});
    });

    test('thirds (33/33/34) on an odd total still sum exactly', () {
      final s = splitByPercent(1000, {'a': 33, 'b': 33, 'c': 34});
      expect(_sum(s), 1000);
    });
  });

  group('edge cases', () {
    test('zero total yields all-zero', () {
      expect(splitEqually(0, ['a', 'b']), {'a': 0, 'b': 0});
    });

    test('empty ids yield an empty map', () {
      expect(splitEqually(100, <String>[]), <String, int>{});
    });
  });

  group('remainderAssignment determinism', () {
    test('the same inputs always produce the same map', () {
      final a = splitEqually(100, ['x', 'y', 'z']);
      final b = splitEqually(100, ['x', 'y', 'z']);
      expect(a, b);
    });
  });

  group('remainingForExact', () {
    test('is zero when entered amounts hit the total', () {
      expect(remainingForExact(100, {'a': 60, 'b': 40}), 0);
    });

    test('is positive when under and negative when over', () {
      expect(remainingForExact(100, {'a': 60}), 40);
      expect(remainingForExact(100, {'a': 60, 'b': 60}), -20);
    });
  });

  group('isEqualSplit', () {
    test('true for an exact even split', () {
      expect(isEqualSplit({'a': 300, 'b': 300, 'c': 300}), isTrue);
    });

    test('true for the canonical remainder split (34/33/33)', () {
      expect(isEqualSplit({'a': 34, 'b': 33, 'c': 33}), isTrue);
    });

    test('false when the extra cent sits on the wrong person', () {
      expect(isEqualSplit({'a': 33, 'b': 34, 'c': 33}), isFalse);
    });

    test('false for a genuinely unequal split', () {
      expect(isEqualSplit({'a': 50, 'b': 30, 'c': 20}), isFalse);
    });

    test('false for an empty map', () {
      expect(isEqualSplit(<String, int>{}), isFalse);
    });
  });

  group('G59 fill the rest', () {
    test('5 € with 2.50 € typed: the open person gets 2.50 €', () {
      expect(distributeRest(500, {'a': 250}, ['b']), {'b': 250});
    });

    test('the rest is spread exactly over several open rows', () {
      final r = distributeRest(1000, {'a': 1}, ['b', 'c', 'd']);
      expect(_sum(r), 999);
      expect(r, {'b': 333, 'c': 333, 'd': 333});
      // 1 cent left over two open rows → the first one gets it.
      expect(distributeRest(101, {'a': 100}, ['b', 'c']), {'b': 1, 'c': 0});
    });

    test('all blank: the whole total is split equally', () {
      final r = distributeRest(100, const {}, ['a', 'b', 'c']);
      expect(r, {'a': 34, 'b': 33, 'c': 33});
    });

    test('nothing left, over-allocated or nobody open → nothing to fill', () {
      expect(distributeRest(500, {'a': 500}, ['b']), isEmpty);
      expect(distributeRest(500, {'a': 530}, ['b']), isEmpty);
      expect(distributeRest(500, {'a': 250}, const []), isEmpty);
      expect(remainingForExact(500, {'a': 530}), -30);
    });

    test('rescale keeps the proportions and sums exactly', () {
      final r = rescaleProportionally(1000, {'a': 300, 'b': 200});
      expect(r, {'a': 600, 'b': 400});
      final odd = rescaleProportionally(100, {'a': 1, 'b': 1, 'c': 1});
      expect(_sum(odd), 100);
      expect(rescaleProportionally(100, {'a': 0, 'b': 5}), {'a': 0, 'b': 100});
    });
  });

  group('G59 mode conversion', () {
    test('equal weights → 1 share each, excluded → 0', () {
      expect(sharesFromWeights({'a': 1, 'b': 1, 'c': 0}), {
        'a': 1,
        'b': 1,
        'c': 0,
      });
      expect(sharesFromWeights({'a': 250, 'b': 250}), {'a': 1, 'b': 1});
    });

    test('cents reduce to the simplest whole shares', () {
      final s = sharesFromWeights({'a': 1500, 'b': 500});
      expect(s, {'a': 3, 'b': 1});
      // Resolving them again reproduces the cents exactly.
      expect(splitByShares(2000, s), {'a': 1500, 'b': 500});
      final odd = sharesFromWeights({'a': 333, 'b': 667});
      expect(splitByShares(1000, odd), {'a': 333, 'b': 667});
    });

    group('G61 nice shares', () {
      test('uneven cents → small shares with exactly the same cents', () {
        final s = sharesFromWeights({'a': 333, 'b': 667}, total: 1000);
        expect(s, {'a': 1, 'b': 2});
        expect(splitByShares(1000, s), {'a': 333, 'b': 667});
        // 10.00 € as 3.34 / 3.33 / 3.33 → 1 / 1 / 1.
        expect(sharesFromWeights({'a': 334, 'b': 333, 'c': 333}, total: 1000), {
          'a': 1,
          'b': 1,
          'c': 1,
        });
        // 12.34 € as 4.11 / 8.23 → 1 / 2 reproduces it.
        final t = sharesFromWeights({'a': 411, 'b': 823}, total: 1234);
        expect(t, {'a': 1, 'b': 2});
        expect(splitByShares(1234, t), {'a': 411, 'b': 823});
      });

      test('excluded stays 0, everyone involved keeps ≥ 1 share', () {
        final s = sharesFromWeights({'a': 9990, 'b': 10, 'c': 0}, total: 10000);
        // 1 share in 1000 can't be written with ≤ 20 shares → exact form.
        expect(s, {'a': 999, 'b': 1, 'c': 0});
        expect(splitByShares(10000, s), {'a': 9990, 'b': 10, 'c': 0});
      });

      test('falls back to the exact GCD form when no small one matches', () {
        // 1.01 / 0.99 € of 2.00 €: any ≤ 20 shares give other cents.
        final s = sharesFromWeights({'a': 101, 'b': 99}, total: 200);
        expect(s, {'a': 101, 'b': 99});
        // Already simple stays as it is.
        expect(sharesFromWeights({'a': 1500, 'b': 500}, total: 2000), {
          'a': 3,
          'b': 1,
        });
      });

      test('the result always resolves to the original cents', () {
        for (final total in [7, 100, 999, 1000, 4200, 12345]) {
          for (var a = 1; a < total; a += (total ~/ 13) + 1) {
            final cents = {'a': a, 'b': total - a};
            final s = sharesFromWeights(cents, total: total);
            expect(splitByShares(total, s), cents, reason: '$a / ${total - a}');
            expect(s.values.every((n) => n > 0), isTrue);
          }
        }
      });

      test('percent weights match their own resolution', () {
        final s = sharesFromWeights({'a': 33.3, 'b': 66.7}, total: 1000);
        expect(s, {'a': 1, 'b': 2});
        expect(
          splitByShares(1000, s),
          splitByPercent(1000, {'a': 33.3, 'b': 66.7}),
        );
      });

      test('without a total: the exact form as before', () {
        expect(sharesFromWeights({'a': 333, 'b': 667}), {'a': 333, 'b': 667});
      });
    });

    test('fractional weights (percents) go by hundredths', () {
      expect(sharesFromWeights({'a': 12.5, 'b': 87.5}), {'a': 1, 'b': 7});
      expect(sharesFromWeights({'a': 50, 'b': 50}), {'a': 1, 'b': 1});
      expect(sharesFromWeights({'a': 0, 'b': 0}), {'a': 0, 'b': 0});
    });

    test('percents sum to exactly 100 in hundredths', () {
      final three = percentsFromWeights({'a': 1, 'b': 1, 'c': 1});
      expect(three, {'a': 33.34, 'b': 33.33, 'c': 33.33});
      expect(
        three.values.map(percentToHundredths).fold(0, (a, b) => a + b),
        10000,
      );
      expect(percentsFromWeights({'a': 1, 'b': 1}), {'a': 50, 'b': 50});
      expect(percentsFromWeights({'a': 1500, 'b': 500, 'c': 0}), {
        'a': 75,
        'b': 25,
        'c': 0,
      });
      for (var n = 1; n <= 13; n++) {
        final p = percentsFromWeights({for (var i = 0; i < n; i++) 'p$i': 1});
        expect(
          p.values.map(percentToHundredths).fold(0, (a, b) => a + b),
          10000,
          reason: 'n=$n',
        );
      }
    });

    test('hundredths round-trip', () {
      expect(hundredthsToPercent(5000), 50);
      expect(hundredthsToPercent(5000), isA<int>());
      expect(hundredthsToPercent(3334), 33.34);
      expect(percentToHundredths(33.33), 3333);
      expect(percentToHundredths(12.5), 1250);
    });
  });

  group('G77 splitByItems', () {
    test('items split equally among their people, rest proportional', () {
      // Pizza 12 (a), Pasta 9 (b), Wine 6 (a + b + c); total 30 → rest 3.
      final r = splitByItems(3000, const [
        SplitItem(1200, ['a']),
        SplitItem(900, ['b']),
        SplitItem(600, ['a', 'b', 'c']),
      ])!;
      // Subtotals a 1400, b 1100, c 200 (sum 2700) → rest 300 in proportion.
      expect(r, {'a': 1556, 'b': 1222, 'c': 222});
      expect(_sum(r), 3000);
    });

    test('rest equally among everyone with an item', () {
      final r = splitByItems(3000, const [
        SplitItem(1200, ['a']),
        SplitItem(900, ['b']),
        SplitItem(600, ['a', 'b', 'c']),
      ], restMode: ItemRestMode.equal)!;
      expect(r, {'a': 1500, 'b': 1200, 'c': 300});
    });

    test('remainders: an item of 10.00 among 3 plus a cent rest', () {
      final r = splitByItems(1001, const [
        SplitItem(1000, ['a', 'b', 'c']),
      ])!;
      // 334 / 333 / 333, the rest cent to the largest remainder (a).
      expect(r, {'a': 335, 'b': 333, 'c': 333});
      expect(_sum(r), 1001);
      final eq = splitByItems(1002, const [
        SplitItem(1000, ['a', 'b', 'c']),
      ], restMode: ItemRestMode.equal)!;
      expect(eq, {'a': 335, 'b': 334, 'c': 333});
      expect(_sum(eq), 1002);
    });

    test('items exactly the total: no rest', () {
      expect(
        splitByItems(500, const [
          SplitItem(300, ['a']),
          SplitItem(200, ['b']),
        ]),
        {'a': 300, 'b': 200},
      );
    });

    test('0-decimal currency: whole yen per item and for the rest', () {
      // ¥1,000 among 3 + ¥200 rest (in stored hundredths, step 100).
      final r = splitByItems(
        120000,
        const [
          SplitItem(100000, ['a', 'b', 'c']),
        ],
        restMode: ItemRestMode.equal,
        step: 100,
      )!;
      expect(r, {'a': 40100, 'b': 40000, 'c': 39900});
      expect(r.values.every((c) => c % 100 == 0), isTrue);
      expect(_sum(r), 120000);
      final p = splitByItems(120000, const [
        SplitItem(100000, ['a', 'b', 'c']),
      ], step: 100)!;
      expect(p.values.every((c) => c % 100 == 0), isTrue);
      expect(_sum(p), 120000);
    });

    test('empty items / no amounts / nobody → null', () {
      expect(splitByItems(1000, const []), isNull);
      expect(
        splitByItems(1000, const [
          SplitItem(0, ['a']),
        ]),
        isNull,
      );
      expect(splitByItems(1000, const [SplitItem(500, [])]), isNull);
    });

    test(
      'a person in no item gets nothing (absent), also with an equal rest',
      () {
        final r = splitByItems(1000, const [
          SplitItem(400, ['a']),
          SplitItem(400, ['b']),
        ], restMode: ItemRestMode.equal)!;
        expect(r, {'a': 500, 'b': 500});
        expect(r.containsKey('c'), isFalse);
      },
    );

    test('an item nobody shares counts as rest', () {
      final r = splitByItems(1000, const [
        SplitItem(400, ['a']),
        SplitItem(200, ['b']),
        SplitItem(400, []),
      ])!;
      // Rest 400 (incl. the unassigned item) proportional 2 : 1.
      expect(r, {'a': 667, 'b': 333});
    });

    test('items over the total (negative rest) or no total → null', () {
      final items = const [
        SplitItem(700, ['a']),
        SplitItem(400, ['b']),
      ];
      expect(itemsSum(items), 1100);
      expect(splitByItems(1000, items), isNull);
      expect(splitByItems(0, items), isNull);
      expect(splitByItems(1100, items), {'a': 700, 'b': 400});
    });

    test('a person listed twice in an item counts once', () {
      expect(
        splitByItems(600, const [
          SplitItem(600, ['a', 'a', 'b']),
        ]),
        {'a': 300, 'b': 300},
      );
    });

    test('a cent item that does not reach someone → they are absent', () {
      final r = splitByItems(1, const [
        SplitItem(1, ['a', 'b']),
      ])!;
      expect(r, {'a': 1});
    });
  });
}
