/// G66: currency list, decimals per currency (storage stays hundredths),
/// region default, picker order + search, split steps and the CSV round
/// trip for 0- and 3-decimal currencies.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/l10n/currencies.dart';
import 'package:money_ledger/features/backup/ledger_csv.dart';
import 'package:money_ledger/features/expenses/split_calculator.dart';
import 'package:money_ledger/features/expenses/split_editor.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

void main() {
  group('currency table', () {
    test('active ISO-4217 codes with EN + DE names, no funds / test codes', () {
      expect(kCurrencyCodes.length, greaterThan(140));
      for (final c in ['EUR', 'CZK', 'HUF', 'PLN', 'DKK', 'SEK', 'THB']) {
        expect(kCurrencyCodes, contains(c));
      }
      for (final c in ['XXX', 'XTS', 'XAU', 'CHE', 'HRK', 'USN']) {
        expect(kCurrencyCodes, isNot(contains(c)));
      }
      expect(kCurrencyCodes, orderedEquals([...kCurrencyCodes]..sort()));
      expect(currencyName('CHF', 'en'), 'Swiss Franc');
      expect(currencyName('CHF', 'de'), 'Schweizer Franken');
      expect(currencyName('JPY', 'de'), 'Japanischer Yen');
      expect(currencyName('XYZ', 'en'), isNull);
    });

    test('decimals: min(ISO, 2); step in stored hundredths', () {
      expect(currencyDecimals('EUR'), 2);
      expect(currencyDecimals('JPY'), 0);
      expect(currencyDecimals('KRW'), 0);
      expect(currencyDecimals('ISK'), 0);
      expect(currencyDecimals('HUF'), 0);
      for (final c in ['BHD', 'KWD', 'JOD', 'OMR', 'TND']) {
        expect(currencyDecimals(c), 2, reason: c);
      }
      expect(currencyDecimals('XYZ'), 2); // unknown → 2
      expect(currencyStep('EUR'), 1);
      expect(currencyStep('JPY'), 100);
      expect(currencyStep('BHD'), 1);
    });
  });

  group('region default', () {
    test('country → currency, fallback EUR', () {
      expect(defaultCurrencyFor('CH'), 'CHF');
      expect(defaultCurrencyFor('GB'), 'GBP');
      expect(defaultCurrencyFor('DE'), 'EUR');
      expect(defaultCurrencyFor('AT'), 'EUR');
      expect(defaultCurrencyFor('US'), 'USD');
      expect(defaultCurrencyFor('JP'), 'JPY');
      expect(defaultCurrencyFor('se'), 'SEK');
      expect(defaultCurrencyFor(null), 'EUR');
      expect(defaultCurrencyFor('ZZ'), 'EUR');
      expect(regionCurrency('ZZ'), isNull);
    });
  });

  group('picker order + search', () {
    test('selected, group, used (by frequency), region, common', () {
      final list = suggestedCurrencies(
        selected: 'THB',
        groupCurrency: 'EUR',
        used: byFrequency(['CHF', 'EUR', 'CZK', 'CZK', 'EUR', 'CZK']),
        region: 'GB',
      );
      expect(list.take(5), ['THB', 'EUR', 'CZK', 'CHF', 'GBP']);
      expect(list.toSet().length, list.length); // no duplicates
      expect(list, containsAll(kCommonCurrencies));
    });

    test('an unknown selected code is kept', () {
      expect(suggestedCurrencies(selected: 'XYZ').first, 'XYZ');
    });

    test('search: code prefix or a word of the EN / DE name, accents', () {
      bool m(String code, String q, [String l = 'en']) =>
          currencyMatches(code, q, l);
      expect(m('CZK', 'cz'), isTrue);
      expect(m('CZK', 'koruna'), isTrue);
      expect(m('CZK', 'krone', 'de'), isTrue);
      expect(m('PLN', 'zloty'), isTrue); // "Złoty" (de) / "Zloty" (en)
      expect(m('CHF', 'franken'), isTrue); // German name, English UI
      expect(m('CHF', 'dollar'), isFalse);
      expect(m('USD', ''), isTrue);
      final dollars = kCurrencyCodes.where((c) => m(c, 'dollar')).toList();
      expect(dollars, containsAll(['USD', 'CAD', 'AUD', 'NZD']));
    });
  });

  group('splits in whole units (0-decimal currency)', () {
    test('¥1,000 / 3 → 334 / 333 / 333 yen (in hundredths)', () {
      final s = splitEqually(100000, ['a', 'b', 'c'], step: 100);
      expect(s, {'a': 33400, 'b': 33300, 'c': 33300});
      expect(s.values.reduce((a, b) => a + b), 100000);
    });

    test('shares / percent / rest / rescale stay whole yen', () {
      final shares = splitByShares(100000, {'a': 2, 'b': 1}, step: 100);
      expect(shares, {'a': 66700, 'b': 33300});
      final pct = splitByPercent(100000, {'a': 50, 'b': 50}, step: 100);
      expect(pct.values.every((v) => v % 100 == 0), isTrue);
      final rest = distributeRest(100000, {'a': 10000}, ['b', 'c'], step: 100);
      expect(rest, {'b': 45000, 'c': 45000});
      final scaled = rescaleProportionally(100000, {
        'a': 100,
        'b': 200,
      }, step: 100);
      expect(scaled.values.reduce((a, b) => a + b), 100000);
      expect(scaled.values.every((v) => v % 100 == 0), isTrue);
    });

    test('a legacy non-whole total is split cent-exact as before', () {
      expect(splitEqually(1234, ['a', 'b'], step: 100), {'a': 617, 'b': 617});
      expect(isEqualSplit({'a': 617, 'b': 617}, step: 100), isTrue);
      expect(
        isEqualSplit({'a': 33400, 'b': 33300, 'c': 33300}, step: 100),
        isTrue,
      );
    });

    test('SplitPlan resolves with its step', () {
      const plan = SplitPlan(
        mode: SplitMode.equal,
        included: ['a', 'b', 'c'],
        step: 100,
      );
      final r = plan.resolve(100000);
      expect(r.isValid, isTrue);
      expect(r.shares['a'], 33400);
    });
  });

  group('CSV round trip (G66)', () {
    const group = GroupModel(
      roomId: 'g1',
      name: 'Trip',
      currency: 'JPY',
      updatedAt: 1000,
    );
    MemberModel m(String id, String name) => MemberModel(
      groupId: 'g1',
      userId: id,
      displayName: name,
      status: 'active',
      updatedAt: 1,
    );
    final members = [m('pa', 'Alex'), m('pb', 'Sam')];
    ExpenseModel e(
      String id,
      String cur,
      int amount,
      Map<String, int> split,
    ) => ExpenseModel(
      id: id,
      roomId: 'g1',
      description: 'X',
      amountCents: amount,
      currency: cur,
      paidBy: 'pa',
      splitsJson:
          '{${split.entries.map((x) => '"${x.key}":${x.value}').join(',')}}',
      createdAt: 1760000000000,
      updatedAt: 1760000050000,
    );

    test('JPY: whole units in the sheet, hundredths after import', () {
      final csv = buildGroupCsv(group, members, [
        e('e1', 'JPY', 100000, {'pa': 50000, 'pb': 50000}),
      ]);
      expect(csv, contains(',1000,'));
      expect(csv, contains(',500,'));
      expect(csv, isNot(contains('1000.00')));
      final r = parseGroupCsv(csv).rows.single;
      expect(r.currency, 'JPY');
      expect(r.amountCents, 100000);
      expect(r.sharesByName, {'Alex': 50000, 'Sam': 50000});
    });

    test('BHD: 2 decimals; legacy non-whole JPY stays lossless', () {
      final csv = buildGroupCsv(group, members, [
        e('e1', 'BHD', 123456, {'pa': 61728, 'pb': 61728}),
        e('e2', 'JPY', 1234, {'pa': 617, 'pb': 617}),
      ]);
      expect(csv, contains('1234.56'));
      expect(csv, contains('12.34'));
      final rows = parseGroupCsv(csv).rows;
      expect(rows.firstWhere((r) => r.id == 'e1').amountCents, 123456);
      final legacy = rows.firstWhere((r) => r.id == 'e2');
      expect(legacy.amountCents, 1234);
      expect(legacy.sharesByName, {'Alex': 617, 'Sam': 617});
    });
  });
}
