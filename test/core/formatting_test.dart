/// Locale-aware formatting + lenient amount parsing (G12).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_ledger/core/l10n/formatting.dart';

const nbsp = '\u00a0';

void main() {
  group('formatMoney', () {
    test('English: symbol first, comma grouping', () {
      expect(formatMoney(123450, 'EUR', 'en'), '€1,234.50');
      expect(formatMoney(4200, 'USD', 'en'), r'$42.00');
      expect(formatMoney(5, 'GBP', 'en'), '£0.05');
    });

    test('German: symbol last, dot grouping, decimal comma', () {
      expect(formatMoney(123450, 'EUR', 'de'), '1.234,50$nbsp€');
      expect(formatMoney(4200, 'USD', 'de'), '42,00$nbsp\$');
    });

    test('letter symbols are separated from the digits', () {
      expect(formatMoney(300, 'CHF', 'en'), 'CHF${nbsp}3.00');
      expect(formatMoney(-300, 'CHF', 'en'), '-CHF${nbsp}3.00');
      expect(formatMoney(300, 'CHF', 'de'), '3,00${nbsp}CHF');
    });

    // G66: storage stays hundredths for every currency; only the display
    // follows the currency's decimals (min(ISO, 2)).
    test('0-decimal currencies show whole units (stored in hundredths)', () {
      expect(formatMoney(100000, 'JPY', 'en'), '¥1,000');
      expect(formatMoney(100000, 'JPY', 'de'), '1.000$nbsp¥');
      expect(formatMoney(1500000, 'KRW', 'en'), '₩15,000');
      expect(formatMoney(250000, 'HUF', 'de'), '2.500${nbsp}Ft');
      expect(formatMoney(-50000, 'ISK', 'en'), contains('500'));
      // A legacy non-whole amount is shown rounded, never refused.
      expect(formatMoney(1234, 'JPY', 'en'), '¥12');
    });

    test('3-decimal currencies show 2 (a thousandth isn\'t storable)', () {
      expect(formatMoney(123456, 'BHD', 'en'), contains('1,234.56'));
      expect(formatMoney(123456, 'KWD', 'de'), contains('1.234,56'));
    });

    test('unknown codes from a peer: the code + 2 decimals, no crash', () {
      expect(formatMoney(123456, 'XYZ', 'en'), 'XYZ${nbsp}1,234.56');
      expect(formatMoney(123456, 'XYZ', 'de'), '1.234,56${nbsp}XYZ');
      for (final odd in ['Bitcoin', 'ab', '€', '']) {
        expect(formatMoney(100, odd, 'en'), contains('1.00'));
      }
    });
  });

  test('formatAmountInput follows the currency (G66)', () {
    expect(formatAmountInput(100000, 'en', currency: 'JPY'), '1000');
    expect(formatAmountInput(100000, 'de', currency: 'JPY'), '1000');
    expect(formatAmountInput(123456, 'de', currency: 'BHD'), '1234,56');
    expect(formatAmountInput(123450, 'en', currency: 'EUR'), '1234.50');
    // Legacy non-whole JPY keeps its two decimals (nothing silently lost).
    expect(formatAmountInput(1234, 'en', currency: 'JPY'), '12.34');
  });

  group('parseAmountCents with a currency (G66)', () {
    test('0-decimal: rounded to whole units, still hundredths', () {
      expect(parseAmountCents('1000', locale: 'en', currency: 'JPY'), 100000);
      expect(parseAmountCents('1.000', locale: 'de', currency: 'JPY'), 100000);
      expect(parseAmountCents('1,000', locale: 'en', currency: 'JPY'), 100000);
      expect(parseAmountCents('1000,5', locale: 'de', currency: 'JPY'), 100100);
      expect(parseAmountCents('0.4', locale: 'en', currency: 'KRW'), 0);
    });

    test('2- and 3-decimal currencies: hundredths as before', () {
      expect(parseAmountCents('12,345', locale: 'de', currency: 'EUR'), 1235);
      expect(parseAmountCents('1.234', locale: 'en', currency: 'BHD'), 123);
      expect(parseAmountCents('12.50', locale: 'en', currency: 'XYZ'), 1250);
    });
  });

  test('formatAmountInput uses the locale decimal separator, no grouping', () {
    expect(formatAmountInput(123450, 'en'), '1234.50');
    expect(formatAmountInput(123450, 'de'), '1234,50');
    expect(formatAmountInput(1000, 'de'), '10,00');
  });

  test('formatDate', () async {
    await initializeDateFormatting('de');
    final ms = DateTime(2026, 6, 13, 12).millisecondsSinceEpoch;
    expect(formatDate(ms, 'en'), 'Jun 13, 2026');
    expect(formatDate(ms, 'de'), '13. Juni 2026');
  });

  group('parseAmountCents', () {
    test('dot or comma as decimal separator', () {
      expect(parseAmountCents('12.5'), 1250);
      expect(parseAmountCents('12,5'), 1250);
      expect(parseAmountCents('12,50'), 1250);
      expect(parseAmountCents(' 7 '), 700);
      expect(parseAmountCents(',5'), 50);
      expect(parseAmountCents('0.29'), 29);
    });

    test('grouping separators (both present → last one is decimal)', () {
      expect(parseAmountCents('1.234,50'), 123450);
      expect(parseAmountCents('1,234.50'), 123450);
      expect(parseAmountCents('1.234.567'), 123456700);
      expect(parseAmountCents("1'234.50"), 123450);
      expect(parseAmountCents('1 234,50'), 123450);
    });

    test('rejects garbage', () {
      expect(parseAmountCents(''), isNull);
      expect(parseAmountCents('abc'), isNull);
      expect(parseAmountCents('12€'), isNull);
      expect(parseAmountCents('1,2.3,4'), isNull);
      expect(parseAmountCents('.'), isNull);
    });

    // G18 review (finding 14).
    test("de: a lone '.' + exactly 3 digits is thousands grouping", () {
      expect(parseAmountCents('1.234', locale: 'de'), 123400);
      expect(parseAmountCents('12.345', locale: 'de'), 1234500);
      expect(parseAmountCents('1.23', locale: 'de'), 123); // decimal
      expect(parseAmountCents('1.2345', locale: 'de'), 123); // decimal
      expect(parseAmountCents('1,234', locale: 'de'), 123); // decimal comma
      expect(parseAmountCents('1.234,5', locale: 'de'), 123450);
    });

    test("en: a lone '.' stays decimal; a lone ',' + 3 digits groups", () {
      expect(parseAmountCents('1.234', locale: 'en'), 123);
      expect(parseAmountCents('1,234', locale: 'en'), 123400);
      expect(parseAmountCents('12,5', locale: 'en'), 1250);
      expect(parseAmountCents('1,234.56', locale: 'en'), 123456);
    });

    test('odd groupings are rejected', () {
      for (final bad in ['12,34.5', '1.23.456', '1234,567.8', '1,2345.6']) {
        expect(parseAmountCents(bad), isNull, reason: bad);
        expect(parseAmountCents(bad, locale: 'de'), isNull, reason: bad);
      }
      expect(parseAmountCents('1,234,567.89'), 123456789);
    });

    test('absurd lengths parse to null instead of throwing', () {
      expect(parseAmountCents('9' * 400), isNull);
    });
  });

  test('parseLocalizedDecimal (percentages)', () {
    expect(parseLocalizedDecimal('33,3'), closeTo(33.3, 1e-9));
    expect(parseLocalizedDecimal('33.3'), closeTo(33.3, 1e-9));
  });
}
