/// G73: "settle up in {base}" — expenses and payments in currencies with a
/// fixed rate are converted for the balances; others stay separate.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/exchange_rate_fetcher.dart';
import 'package:money_ledger/features/balance/settle_currency.dart';
import 'package:money_ledger/models/exchange_rates.dart';
import 'package:money_ledger/models/expense_model.dart';

ExpenseModel _e(String id, int cents, String cur, String by, Map split) =>
    ExpenseModel(
      id: id,
      roomId: 'g',
      description: id,
      amountCents: cents,
      currency: cur,
      paidBy: by,
      splitsJson: jsonEncode(split),
      createdAt: 1,
    );

void main() {
  final expenses = [
    _e('e1', 10000, 'EUR', 'a', {'a': 5000, 'b': 5000}),
    _e('e2', 10000, 'CHF', 'b', {'a': 3334, 'b': 3333, 'c': 3333}),
    _e('e3', 1000, 'USD', 'c', {'a': 500, 'c': 500}),
  ];
  const settlements = [
    SettlementModel(
      id: 's1',
      roomId: 'g',
      amountCents: 1000,
      currency: 'CHF',
      fromUser: 'a',
      toUser: 'b',
      createdAt: 2,
    ),
  ];

  test('off / no rates: the ledger is returned unchanged', () {
    for (final fx in [
      null,
      ExchangeRates(base: 'EUR', rates: const {'CHF': '1.1'}),
    ]) {
      final l = ledgerForSettling(expenses, settlements, fx);
      expect(identical(l.expenses, expenses), isTrue);
      expect(settlesConverted(fx, ['CHF']), isFalse);
    }
  });

  test('on: CHF converted to EUR, USD (no rate) stays separate', () {
    final fx = ExchangeRates(
      base: 'EUR',
      rates: const {'CHF': '1.1'},
      settle: true,
    );
    expect(settlesConverted(fx, ['EUR', 'CHF']), isTrue);
    expect(settlesConverted(fx, ['EUR', 'USD']), isFalse);
    final l = ledgerForSettling(expenses, settlements, fx);
    final e2 = l.expenses[1];
    expect(e2.currency, 'EUR');
    expect(e2.amountCents, 11000);
    final split = (jsonDecode(e2.splitsJson) as Map).cast<String, int>();
    expect(split.values.fold<int>(0, (a, b) => a + b), 11000);
    expect(split, {'a': 3668, 'b': 3666, 'c': 3666}); // largest remainder
    expect(l.expenses[2].currency, 'USD');
    expect(l.settlements.single.amountCents, 1100);
    expect(l.settlements.single.currency, 'EUR');

    final debts = calculateDebts(l.expenses, l.settlements);
    expect(debts.map((d) => d.currency).toSet(), {'EUR', 'USD'});
    // EUR nets: a +5000 −3668 +1100 = 2432, b −5000 +7334 −1100 = 1234,
    // c −3666 → c pays a and b; each currency still nets to zero.
    final eur = netBalances(l.expenses, l.settlements)['EUR']!;
    expect(eur.values.fold<int>(0, (a, b) => a + b), 0);
    expect(eur, {'a': 2432, 'b': 1234, 'c': -3666});
  });

  group('Frankfurter answer', () {
    test('parses a /v2/rate answer for exactly this pair', () {
      final r = parseFrankfurterRate(
        '{"date":"2026-10-22","base":"CHF","quote":"EUR","rate":1.0797}',
        from: 'CHF',
        to: 'EUR',
      );
      expect(r.rate, '1.0797');
      expect(r.date, '2026-10-22');
      expect(
        () => parseFrankfurterRate(
          '{"date":"2026-10-22","base":"USD","quote":"EUR","rate":1}',
          from: 'CHF',
          to: 'EUR',
        ),
        throwsFormatException,
      );
    });

    test('the request names only the two currencies', () async {
      Uri? asked;
      final client = MockClient((req) async {
        asked = req.url;
        return http.Response(
          '{"date":"2026-10-21","base":"CHF","quote":"IDR","rate":21813}',
          200,
        );
      });
      final r = await fetchFrankfurterRate('CHF', 'IDR', client: client);
      expect(r.rate, '21813');
      expect(asked.toString(), 'https://api.frankfurter.dev/v2/rate/CHF/IDR');
    });

    test('an unsupported currency → RateUnavailableException', () async {
      final client = MockClient(
        (_) async => http.Response('{"status":422}', 422),
      );
      expect(
        fetchFrankfurterRate('XAF', 'EUR', client: client),
        throwsA(isA<RateUnavailableException>()),
      );
      expect(
        fetchFrankfurterRate('x', 'EUR', client: client),
        throwsA(isA<RateUnavailableException>()),
      );
    });

    test('a server error is an http error (shown as a network error)', () {
      final client = MockClient((_) async => http.Response('', 503));
      expect(
        fetchFrankfurterRate('CHF', 'EUR', client: client),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  test('a converted amount beyond kMaxAmountCents stays unconverted', () {
    final fx = ExchangeRates(
      base: 'IDR',
      rates: const {'EUR': '999999999'},
      settle: true,
    );
    final big = _e('big', 10000000000000, 'EUR', 'a', {
      'a': 5000000000000,
      'b': 5000000000000,
    });
    final small = _e('small', 100, 'EUR', 'a', {'a': 50, 'b': 50});
    const pay = SettlementModel(
      id: 'p',
      roomId: 'g',
      amountCents: 10000000000000,
      currency: 'EUR',
      fromUser: 'b',
      toUser: 'a',
      createdAt: 3,
    );
    final l = ledgerForSettling([big, small], [pay], fx);
    expect(identical(l.expenses[0], big), isTrue);
    expect(l.expenses[1].currency, 'IDR');
    expect(l.expenses[1].amountCents, 99999999900);
    expect(identical(l.settlements.single, pay), isTrue);
  });
}
