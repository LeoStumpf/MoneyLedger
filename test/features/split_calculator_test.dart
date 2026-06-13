/// Pure split math (Phase E, M1): every mode must sum to the total exactly via
/// largest-remainder rounding, and `isEqualSplit` must drive edit-mode inference.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/expenses/split_calculator.dart';

int _sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

void main() {
  group('splitEqually', () {
    test('divides evenly when it divides evenly', () {
      expect(splitEqually(900, ['a', 'b', 'c']), {'a': 300, 'b': 300, 'c': 300});
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
          expect(_sum(splitEqually(total, ids)), total,
              reason: 'total=$total n=$n');
        }
      }
    });
  });

  group('splitByShares', () {
    test('distributes in proportion to weights', () {
      expect(splitByShares(400, {'a': 2, 'b': 1, 'c': 1}),
          {'a': 200, 'b': 100, 'c': 100});
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
}
