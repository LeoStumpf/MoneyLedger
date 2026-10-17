/// G69: the pure parts — share text (U17), statistics (U19) and the groups
/// list order (U20).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/l10n/formatting.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_share.dart';
import 'package:money_ledger/features/balance/group_stats.dart';
import 'package:money_ledger/features/groups/group_overview_provider.dart';
import 'package:money_ledger/models/expense_category.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';

import '../helpers/l10n.dart';

const _names = {'a': 'Anna', 'b': 'Ben', 'c': 'Chris'};
String _nameOf(String id) => _names[id] ?? id;

ExpenseModel _expense(
  String id,
  int amount,
  String paidBy,
  Map<String, int> split, {
  String currency = 'EUR',
  String? category,
}) => ExpenseModel(
  id: id,
  roomId: 'g',
  description: id,
  amountCents: amount,
  currency: currency,
  paidBy: paidBy,
  splitsJson:
      '{${split.entries.map((e) => '"${e.key}":${e.value}').join(',')}}',
  createdAt: 1,
  category: category,
);

GroupOverview _overview(int? last) => GroupOverview(
  members: const [],
  me: null,
  myBalance: const {},
  lastActivityAt: last,
  recordCount: 0,
);

void main() {
  group('share text (U17)', () {
    const debts = [
      DebtEntry(from: 'b', to: 'a', cents: 4210, currency: 'EUR'),
      DebtEntry(from: 'c', to: 'a', cents: 1200, currency: 'EUR'),
    ];

    test('German: title, one line per payment, footer', () {
      final text = buildBalanceShareText(
        l: de,
        groupName: 'Rom 2026',
        debts: debts,
        nameOf: _nameOf,
      );
      expect(
        text,
        'Rom 2026 – wer zahlt wem\n'
        '\n'
        'Ben → Anna: ${formatMoney(4210, 'EUR', 'de')}\n'
        'Chris → Anna: ${formatMoney(1200, 'EUR', 'de')}\n'
        '\n'
        'Erstellt mit MoneyLedger',
      );
      expect(text, contains('42,10'));
    });

    test('English', () {
      final text = buildBalanceShareText(
        l: en,
        groupName: ' Rome 2026 ',
        debts: debts,
        nameOf: _nameOf,
      );
      expect(text, startsWith('Rome 2026 – who pays whom\n\n'));
      expect(text, contains('Ben → Anna: €42.10\n'));
      expect(text, endsWith('\n\nMade with MoneyLedger'));
      // Nobody is "you" — the text is for the others.
      expect(text.toLowerCase(), isNot(contains('you ')));
      // No link, no tracking.
      expect(text, isNot(contains('http')));
    });

    test('several currencies: one block each, never netted', () {
      final text = buildBalanceShareText(
        l: de,
        groupName: 'Alpen',
        debts: const [
          DebtEntry(from: 'b', to: 'a', cents: 1000, currency: 'CHF'),
          DebtEntry(from: 'a', to: 'c', cents: 550, currency: 'EUR'),
        ],
        nameOf: _nameOf,
      );
      expect(
        text,
        'Alpen – wer zahlt wem\n'
        '\n'
        'In CHF:\n'
        'Ben → Anna: ${formatMoney(1000, 'CHF', 'de')}\n'
        '\n'
        'In EUR:\n'
        'Anna → Chris: ${formatMoney(550, 'EUR', 'de')}\n'
        '\n'
        'Erstellt mit MoneyLedger',
      );
    });

    test('all settled', () {
      expect(
        buildBalanceShareText(
          l: de,
          groupName: 'Rom',
          debts: const [],
          nameOf: _nameOf,
        ),
        'Rom – wer zahlt wem\n\nAlles ausgeglichen.\n\nErstellt mit MoneyLedger',
      );
      expect(
        buildBalanceShareText(
          l: en,
          groupName: 'Rome',
          debts: const [],
          nameOf: _nameOf,
        ),
        contains('\n\nAll settled up.\n\n'),
      );
    });
  });

  group('statistics (U19)', () {
    test('total, paid vs. share, categories per currency', () {
      const custom = [CustomCategory(id: 'c:dog', name: 'Dog', icon: 'pets')];
      final stats = groupStats([
        _expense('e1', 3000, 'a', {
          'a': 1000,
          'b': 1000,
          'c': 1000,
        }, category: 'food'),
        _expense('e2', 1000, 'b', {'a': 500, 'b': 500}, category: 'food'),
        _expense('e3', 2000, 'b', {'b': 2000}, category: 'c:dog'),
        _expense('e4', 500, 'c', {'a': 500}),
        _expense(
          'e5',
          800,
          'a',
          {'a': 400, 'b': 400},
          currency: 'CHF',
          category: 'transport',
        ),
      ], customCategories: custom);
      expect(stats.map((s) => s.currency), ['CHF', 'EUR']);
      final eur = stats[1];
      expect(eur.total, 6500);
      expect(eur.count, 4);
      expect(eur.people, const [
        PersonStat(id: 'b', paid: 3000, share: 3500),
        PersonStat(id: 'a', paid: 3000, share: 2000),
        PersonStat(id: 'c', paid: 500, share: 1000),
      ]);
      // Paid and shares both add up to the total.
      expect(eur.people.fold<int>(0, (s, p) => s + p.paid), eur.total);
      expect(eur.people.fold<int>(0, (s, p) => s + p.share), eur.total);
      expect(
        [for (final c in eur.categories) (c.category?.key, c.cents)],
        [('food', 4000), ('c:dog', 2000), (null, 500)],
      );
      expect(eur.categories[1].category!.custom!.name, 'Dog');
      final chf = stats[0];
      expect(chf.total, 800);
      expect(chf.categories.single.category!.key, 'transport');
    });

    test('an unknown category counts as Other; equal sums keep order', () {
      final stats = groupStats([
        _expense('e1', 100, 'a', {'a': 100}, category: 'c:gone'),
        _expense('e2', 100, 'a', {'a': 100}, category: 'food'),
        _expense('e3', 100, 'a', {'a': 100}, category: 'other'),
      ]);
      expect(
        [for (final c in stats.single.categories) (c.category?.key, c.cents)],
        [('other', 200), ('food', 100)],
      );
    });

    test('a malformed split is left out; no expenses → empty', () {
      final bad = ExpenseModel(
        id: 'x',
        roomId: 'g',
        description: 'x',
        amountCents: 100,
        currency: 'EUR',
        paidBy: 'a',
        splitsJson: 'nope',
        createdAt: 1,
      );
      expect(groupStats([bad]), isEmpty);
      expect(groupStats(const []), isEmpty);
    });
  });

  group('groups list order (U20)', () {
    // 2026-10-01 / 2026-10-10 as UUIDv7 ids.
    final oct1 = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
    final oct10 = DateTime.utc(2026, 10, 10).millisecondsSinceEpoch;
    String v7(int ms) {
      final hex = ms.toRadixString(16).padLeft(12, '0');
      return '${hex.substring(0, 8)}-${hex.substring(8)}-7abc-8def-0123456789ab';
    }

    test('uuidV7Millis', () {
      expect(uuidV7Millis(v7(oct1)), oct1);
      expect(uuidV7Millis('01890a5d-ac96-4abc-8def-0123456789ab'), isNull);
      expect(uuidV7Millis('!room:x.org'), isNull);
    });

    test('newest activity first; a new empty group on top; unknown last', () {
      final oldTrip = GroupModel(
        roomId: v7(oct1),
        name: 'Old',
        currency: 'EUR',
      );
      final current = GroupModel(
        roomId: v7(oct1 + 1),
        name: 'Current',
        currency: 'EUR',
      );
      final fresh = GroupModel(
        roomId: v7(oct10),
        name: 'Fresh',
        currency: 'EUR',
      );
      const legacy = GroupModel(
        roomId: '!x:y',
        name: 'Legacy',
        currency: 'EUR',
      );
      const legacyActive = GroupModel(
        roomId: '!z:y',
        name: 'Legacy active',
        currency: 'EUR',
      );
      final sorted = sortGroupsByActivity([
        (legacy, _overview(null)),
        (oldTrip, _overview(oct1 + 1000)),
        (legacyActive, _overview(oct1 + 500)),
        (current, _overview(oct10 - 1000)),
        (fresh, _overview(null)),
      ]);
      expect(sorted.map((e) => e.$1.name), [
        'Fresh',
        'Current',
        'Old',
        'Legacy active',
        'Legacy',
      ]);
    });

    test('equal activity: by name', () {
      const b = GroupModel(roomId: '!b', name: 'beta', currency: 'EUR');
      const a = GroupModel(roomId: '!a', name: 'Alpha', currency: 'EUR');
      expect(
        sortGroupsByActivity([
          (b, _overview(5)),
          (a, _overview(5)),
        ]).map((e) => e.$1.name),
        ['Alpha', 'beta'],
      );
    });
  });
}
