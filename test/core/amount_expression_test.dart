/// G75: the amount fields' calculator — `parseAmountInput`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/l10n/formatting.dart';
import 'package:money_ledger/core/sync/record_validation.dart';

void main() {
  int? en(String s, {String currency = 'EUR'}) =>
      parseAmountInput(s, locale: 'en', currency: currency);
  int? de(String s, {String currency = 'EUR'}) =>
      parseAmountInput(s, locale: 'de', currency: currency);

  group('plain numbers are read exactly like parseAmountCents', () {
    for (final s in ['12', '12,50', '12.5', '1.234', '1,234', '-5', '', 'x']) {
      test('"$s"', () {
        for (final locale in ['en', 'de']) {
          expect(
            parseAmountInput(s, locale: locale, currency: 'EUR'),
            parseAmountCents(s, locale: locale, currency: 'EUR'),
          );
        }
      });
    }
  });

  group('expressions (EN / DE)', () {
    test('12,50+8 = 20.50 in both locales', () {
      expect(de('12,50+8'), 2050);
      expect(en('12,50+8'), 2050);
      expect(en('12.50 + 8'), 2050);
    });

    test('precedence: * and / before + and -', () {
      expect(en('2+3*4'), 1400);
      expect(en('10-4/2'), 800);
      expect(de('3*4,20'), 1260);
      expect(en('3×4.20'), 1260);
      expect(en('9÷3'), 300);
      expect(en('2·3'), 600);
    });

    test('parentheses (optional)', () {
      expect(en('(12+8)/2'), 1000);
      expect(en('2*(3+4)'), 1400);
      expect(en('((1))'), 100);
    });

    test('a sign only at the start or after "("', () {
      expect(en('-2+10'), 800);
      expect(en('10+(-2)'), 800);
      expect(en('10+-2'), isNull);
      expect(en('5*-2'), isNull);
      expect(en('--2'), isNull);
    });

    test('German grouping inside an expression: 1.234+1 = 1235', () {
      expect(de('1.234+1'), 123500);
      expect(en('1.234+1'), 223); // en: 1.234 is a decimal → 2.234 → 2.23
      expect(en('1,234+1'), 123500);
      expect(de('1.234,50+0,50'), 123500);
    });

    test('rounded to the currency step once, at the end', () {
      expect(en('10/3'), 333); // €3.33
      expect(en('20/3'), 667); // €6.67
      expect(en('1/3+1/3+1/3'), 100); // not 99
      expect(en('0.004+0.004'), 1); // 0.8 ct → 1
      expect(en('1000/3', currency: 'JPY'), 33300); // ¥333
      expect(en('1000.5+0', currency: 'JPY'), 100100); // ¥1,001
      expect(de('12,345+0'), 1235);
    });

    test('malformed → null (the field shows "invalid")', () {
      for (final s in [
        '12+',
        '+*3',
        '*3',
        '(1+2',
        '1+2)',
        '()',
        '12+abc',
        '1++2',
        '12,34.5+1',
        '1,2.3,4+1',
        '3(2)',
      ]) {
        expect(en(s), isNull, reason: s);
        expect(de(s), isNull, reason: s);
      }
    });

    test('division by zero → null', () {
      expect(en('5/0'), isNull);
      expect(en('5/(2-2)'), isNull);
      expect(de('5/0,0'), isNull);
    });

    test('results outside 1 cent … kMaxAmountCents parse, the caller '
        'refuses them', () {
      final huge = en('99999999999*10')!;
      expect(huge, greaterThan(kMaxAmountCents));
      expect(isValidAmountCents(huge), isFalse);
      expect(en('5-5'), 0);
      expect(isValidAmountCents(en('5-5')!), isFalse);
      expect(en('2-5'), -300);
      // Beyond a double's whole cents → null, never a throw.
      expect(en('9999999999999999*9999999999999999'), isNull);
    });

    test('a very long input is refused', () {
      expect(en(List.filled(150, '1').join('+')), isNull);
    });
  });
}
