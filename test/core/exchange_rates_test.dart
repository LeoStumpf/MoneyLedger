/// G73: rate strings (canonical decimals), input normalisation, fetched
/// doubles and the exact cent conversion.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/models/exchange_rates.dart';

void main() {
  test('isValidRate accepts canonical positive decimals only', () {
    for (final ok in ['1', '0.5', '1.0797', '31315', '0.0000000001']) {
      expect(isValidRate(ok), isTrue, reason: ok);
    }
    for (final bad in [
      '', '0', '0.0', '1.', '.5', '1.50', '01', '-1', '1e3', '1,5', //
      '1234567890', '0.00000000001',
    ]) {
      expect(isValidRate(bad), isFalse, reason: bad);
    }
  });

  test('normalizeRateInput reads , and . and trims zeros', () {
    expect(normalizeRateInput(' 1,0797 '), '1.0797');
    expect(normalizeRateInput('1.50'), '1.5');
    expect(normalizeRateInput('007'), '7');
    expect(normalizeRateInput(',5'), '0.5');
    expect(normalizeRateInput('2.'), '2');
    for (final bad in ['', '0', '0,00', 'abc', '1.2.3', '1,234.5', '-1', '.']) {
      expect(normalizeRateInput(bad), isNull, reason: bad);
    }
    expect(normalizeRateInput('0.12345678901'), isNull); // 11 decimals
  });

  test('rateFromDouble', () {
    expect(rateFromDouble(1.0797), '1.0797');
    expect(rateFromDouble(31315), '31315');
    expect(rateFromDouble(0.0000458), '0.0000458');
    expect(rateFromDouble(0), isNull);
    expect(rateFromDouble(double.nan), isNull);
    expect(rateFromDouble(1e12), isNull);
  });

  test('convertCents rounds half away from zero, exactly', () {
    expect(convertCents(10000, '1.0797'), 10797);
    expect(convertCents(1, '0.5'), 1); // 0.5 → 1
    expect(convertCents(-1, '0.5'), -1);
    expect(convertCents(3, '0.5'), 2); // 1.5 → 2
    // ¥1,000 (stored ×100 like every currency) → €5.81.
    expect(convertCents(100000, '0.005812'), 581);
    // No float / overflow trouble at the amount bound.
    expect(convertCents(10000000000000, '31315'), 313150000000000000);
  });

  test('fromJson: absent → null, malformed → an invalid entry', () {
    expect(ExchangeRates.fromJson(null), isNull);
    expect(ExchangeRates.fromJson('x')!.base, '');
    final fx = ExchangeRates.fromJson({
      'base': 'EUR',
      'rates': {'USD': '0.9', 'CHF': '1.1'},
    })!;
    expect(fx.rates.keys, ['CHF', 'USD']); // sorted
    expect(fx.settle, isFalse);
    expect(fx.copyWith(rates: const {}), isNull);
    expect(fx.copyWith(settle: true)!.settle, isTrue);
  });
}
