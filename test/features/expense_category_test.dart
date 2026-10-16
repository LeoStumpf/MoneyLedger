/// G16: categories (wire ids, heuristic suggestion), notes and the ledger
/// search / filter — pure functions.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/expenses/expense_filter.dart';
import 'package:money_ledger/models/expense_category.dart';
import 'package:money_ledger/models/expense_model.dart';

ExpenseModel _e(
  String id,
  String description, {
  String paidBy = 'me',
  Map<String, int> split = const {'me': 500, 'bea': 500},
  String? category,
  String? note,
}) => ExpenseModel(
  id: id,
  roomId: 'g1',
  description: description,
  amountCents: 1000,
  currency: 'EUR',
  paidBy: paidBy,
  splitsJson:
      '{${split.entries.map((e) => '"${e.key}":${e.value}').join(',')}}',
  createdAt: 1,
  updatedAt: 1,
  category: category,
  note: note,
);

SettlementModel _s(String from, String to) => SettlementModel(
  id: 's-$from-$to',
  roomId: 'g1',
  amountCents: 100,
  currency: 'EUR',
  fromUser: from,
  toUser: to,
  createdAt: 1,
  updatedAt: 1,
);

const _names = {'me': 'Anna', 'bea': 'Bea', 'carl': 'Carl Großmann'};
String _nameOf(String id) => _names[id] ?? id;

void main() {
  group('ExpenseCategory', () {
    test('wire ids are stable and round-trip', () {
      expect(ExpenseCategory.values.map((c) => c.wire), [
        'food',
        'groceries',
        'transport',
        'accommodation',
        'entertainment',
        'shopping',
        'home',
        'health',
        'travel',
        'other',
      ]);
      for (final c in ExpenseCategory.values) {
        expect(ExpenseCategory.fromWire(c.wire), c);
      }
    });

    test('none for null / empty, "other" for an unknown id', () {
      expect(ExpenseCategory.fromWire(null), isNull);
      expect(ExpenseCategory.fromWire(''), isNull);
      expect(ExpenseCategory.fromWire('pets'), ExpenseCategory.other);
    });

    test('the model keeps an unknown id verbatim and drops empty values', () {
      expect(_e('1', 'x', category: 'pets').category, 'pets');
      expect(_e('1', 'x', category: '', note: '').category, isNull);
      expect(_e('1', 'x', note: '').note, isNull);
      // withSigning keeps content.
      final e = _e('1', 'x', category: 'food', note: 'n').withSigning();
      expect((e.category, e.note), ('food', 'n'));
    });
  });

  group('normalizeNote', () {
    test('trims, and blank means no note', () {
      expect(normalizeNote(null), isNull);
      expect(normalizeNote('   '), isNull);
      expect(normalizeNote('  key box 1234 \n'), 'key box 1234');
    });
  });

  group('suggestCategory (prefill heuristic)', () {
    final cases = {
      'Pizza': ExpenseCategory.food,
      'Seafood dinner': ExpenseCategory.food,
      'Pastéis de Belém': ExpenseCategory.food,
      'Abendessen beim Italiener': ExpenseCategory.food,
      'Groceries': ExpenseCategory.groceries,
      'REWE Einkauf': ExpenseCategory.groceries,
      'Airport taxi': ExpenseCategory.transport,
      'Tram 28 tickets': ExpenseCategory.transport,
      'Tanken': ExpenseCategory.transport,
      'Apartment in Alfama (3 nights)': ExpenseCategory.accommodation,
      'Hotel Zürich': ExpenseCategory.accommodation,
      'Flight to Lisbon': ExpenseCategory.travel,
      'Sintra day trip': ExpenseCategory.travel,
      'Cinema': ExpenseCategory.entertainment,
      'Ski passes (2 days)': ExpenseCategory.entertainment,
      'Rent October': ExpenseCategory.home,
      'Strom': ExpenseCategory.home,
      'Apotheke': ExpenseCategory.health,
      'Birthday gift': ExpenseCategory.shopping,
    };
    for (final MapEntry(key: text, value: expected) in cases.entries) {
      test('"$text" → ${expected.wire}', () {
        expect(suggestCategory(text), expected);
      });
    }

    test('no suggestion for unknown words, blanks or partial words', () {
      expect(suggestCategory(''), isNull);
      expect(suggestCategory('   '), isNull);
      expect(suggestCategory('Misc'), isNull);
      // Short stems only match whole words.
      expect(suggestCategory('Barber'), isNull);
      expect(suggestCategory('Business cards'), isNull);
    });
  });

  group('LedgerFilter / expenseMatches', () {
    final pizza = _e('1', 'Pizza', category: 'food');
    final cafe = _e('2', 'Café Central', paidBy: 'bea', note: 'Birthday');
    final taxi = _e(
      '3',
      'Taxi',
      paidBy: 'carl',
      split: const {'bea': 500, 'carl': 500},
      category: 'transport',
    );
    final all = [pizza, cafe, taxi];

    List<String> run(LedgerFilter f, {String? myId = 'me'}) => [
      for (final e in all)
        if (expenseMatches(e, f, nameOf: _nameOf, myId: myId)) e.id,
    ];

    test('no filter matches everything; isActive', () {
      expect(LedgerFilter.none.isActive, isFalse);
      expect(const LedgerFilter(query: '  ').isActive, isFalse);
      expect(run(LedgerFilter.none), ['1', '2', '3']);
    });

    test('query: description, note and payer name; case + accents', () {
      expect(run(const LedgerFilter(query: 'PIZ')), ['1']);
      expect(run(const LedgerFilter(query: 'cafe')), ['2']); // "Café"
      expect(run(const LedgerFilter(query: 'birthday')), ['2']); // note
      expect(run(const LedgerFilter(query: 'Bea')), ['2']); // payer
      expect(run(const LedgerFilter(query: 'großmann')), ['3']);
      expect(run(const LedgerFilter(query: 'nothing')), isEmpty);
    });

    test('categories: any of the selected; none never matches', () {
      expect(run(const LedgerFilter(categories: {'food'})), ['1']);
      expect(run(const LedgerFilter(categories: {'food', 'transport'})), [
        '1',
        '3',
      ]);
    });

    test('involving me: payer or in the split; nobody when not a member', () {
      expect(run(const LedgerFilter(involvingMe: true)), ['1', '2']);
      expect(run(const LedgerFilter(involvingMe: true), myId: null), isEmpty);
    });

    test('criteria combine (AND)', () {
      expect(
        run(
          const LedgerFilter(
            query: 'a',
            involvingMe: true,
            categories: {'food'},
          ),
        ),
        ['1'],
      );
    });

    test('toggleCategory / copyWith', () {
      final f = LedgerFilter.none.toggleCategory('food').toggleCategory('home');
      expect(f.categories, {'food', 'home'});
      expect(f.toggleCategory('food').categories, {'home'});
      expect(f.copyWith(query: 'x').categories, f.categories);
    });
  });

  group('settlementMatches', () {
    bool m(SettlementModel s, LedgerFilter f, {String? myId = 'me'}) =>
        settlementMatches(
          s,
          f,
          nameOf: _nameOf,
          myId: myId,
          paymentLabel: 'Payment',
        );

    test('query on both names and the word "payment"', () {
      expect(m(_s('bea', 'carl'), const LedgerFilter(query: 'carl')), isTrue);
      expect(m(_s('bea', 'carl'), const LedgerFilter(query: 'pay')), isTrue);
      expect(m(_s('bea', 'carl'), const LedgerFilter(query: 'anna')), isFalse);
    });

    test('a category filter hides payments; involving me = either side', () {
      expect(
        m(_s('me', 'bea'), const LedgerFilter(categories: {'food'})),
        isFalse,
      );
      expect(m(_s('bea', 'me'), const LedgerFilter(involvingMe: true)), isTrue);
      expect(
        m(_s('bea', 'carl'), const LedgerFilter(involvingMe: true)),
        isFalse,
      );
    });
  });

  test('usedCategories: in picker order, unknown ids as "other"', () {
    expect(
      usedCategories([
        _e('1', 'a', category: 'transport'),
        _e('2', 'b', category: 'food'),
        _e('3', 'c'),
        _e('4', 'd', category: 'pets'),
        _e('5', 'e', category: 'food'),
      ]),
      [
        const ResolvedCategory.builtin(ExpenseCategory.food),
        const ResolvedCategory.builtin(ExpenseCategory.transport),
        const ResolvedCategory.builtin(ExpenseCategory.other),
      ],
    );
  });

  // ── G47: custom categories ──────────────────────────────────────────────
  group('custom categories', () {
    const dog = CustomCategory(id: 'c:dog', name: 'Dog', icon: 'pets');
    const kids = CustomCategory(
      id: 'c:kids',
      name: 'Kids',
      icon: 'child',
      hidden: true,
    );
    const custom = [dog, kids];

    test('resolveCategory: built-in, custom (hidden too), unknown → other', () {
      expect(resolveCategory(null, custom), isNull);
      expect(resolveCategory('', custom), isNull);
      expect(
        resolveCategory('food', custom),
        const ResolvedCategory.builtin(ExpenseCategory.food),
      );
      expect(
        resolveCategory('c:dog', custom),
        const ResolvedCategory.custom(dog),
      );
      expect(resolveCategory('c:kids', custom)!.custom, kids);
      expect(
        resolveCategory('c:gone', custom),
        const ResolvedCategory.builtin(ExpenseCategory.other),
      );
      expect(resolveCategory('c:dog', const [])!.key, 'other');
      expect(resolveCategory('c:dog', custom)!.key, 'c:dog');
    });

    test(
      'filter by a custom category; undefined custom ids count as other',
      () {
        final vet = _e('1', 'Vet', category: 'c:dog');
        final toys = _e('2', 'Toys', category: 'c:kids');
        final lost = _e('3', 'Lost', category: 'c:gone');
        final pizza = _e('4', 'Pizza', category: 'food');
        List<String> run(LedgerFilter f) => [
          for (final e in [vet, toys, lost, pizza])
            if (expenseMatches(
              e,
              f,
              nameOf: _nameOf,
              myId: 'me',
              customCategories: custom,
            ))
              e.id,
        ];
        expect(run(const LedgerFilter(categories: {'c:dog'})), ['1']);
        expect(run(const LedgerFilter(categories: {'c:kids', 'food'})), [
          '2',
          '4',
        ]);
        expect(run(const LedgerFilter(categories: {'other'})), ['3']);
        // Combined with a text query.
        expect(run(const LedgerFilter(query: 'toy', categories: {'c:kids'})), [
          '2',
        ]);
        expect(
          usedCategories([vet, toys, lost, pizza], custom).map((c) => c.key),
          ['food', 'other', 'c:dog', 'c:kids'],
        );
      },
    );

    test('parseCustomCategories: lenient shape, invalid entries kept', () {
      expect(parseCustomCategories(null), isEmpty);
      expect(parseCustomCategories([dog.toJson(), kids.toJson()]), custom);
      expect(kids.toJson()['hidden'], isTrue);
      expect(dog.toJson().containsKey('hidden'), isFalse);
      // Malformed → an (invalid) entry, so the content rules refuse it.
      expect(parseCustomCategories('x').single.id, '');
      expect(parseCustomCategories([42]).single.id, '');
      expect(
        parseCustomCategories([
          {'id': 'c:a', 'name': 7, 'icon': 'tag'},
        ]).single.name,
        '',
      );
    });

    test('isValidCategoryName', () {
      expect(isValidCategoryName('Dog'), isTrue);
      expect(isValidCategoryName(''), isFalse);
      expect(isValidCategoryName(' Dog'), isFalse);
      expect(isValidCategoryName('x' * kMaxCategoryNameLength), isTrue);
      expect(isValidCategoryName('x' * (kMaxCategoryNameLength + 1)), isFalse);
    });
  });
}
