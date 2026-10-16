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

    test('always two decimals (amounts are hundredths, also for JPY)', () {
      expect(formatMoney(1234, 'JPY', 'en'), contains('12.34'));
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
