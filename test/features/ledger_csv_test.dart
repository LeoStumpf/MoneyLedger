/// CSV codec (Phase D, M1): build a human-readable per-group expenses sheet and
/// parse it back. Pure — no DB.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/backup/ledger_csv.dart';
import 'package:money_ledger/models/expense_category.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

void main() {
  const testGroup = GroupModel(
    roomId: 'g1',
    name: 'Trip',
    currency: 'EUR',
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

  ExpenseModel expense({
    String id = 'e1',
    String description = 'Dinner',
    int amount = 4200,
    String paidBy = 'pa',
    Map<String, int> split = const {'pa': 2100, 'pb': 2100},
    int createdAt = 1760000000000,
    int updatedAt = 1760000050000,
    bool deleted = false,
  }) => ExpenseModel(
    id: id,
    roomId: 'g1',
    description: description,
    amountCents: amount,
    currency: 'EUR',
    paidBy: paidBy,
    splitsJson:
        '{${split.entries.map((e) => '"${e.key}":${e.value}').join(',')}}',
    createdAt: createdAt,
    updatedAt: updatedAt,
    deleted: deleted,
  );

  group('buildGroupCsv / parseGroupCsv', () {
    test('round-trips an expense (names, shares, ids, clock)', () {
      final csv = buildGroupCsv(testGroup, members, [expense()]);
      final parsed = parseGroupCsv(csv);

      expect(parsed.groupId, 'g1');
      expect(parsed.groupName, 'Trip');
      expect(parsed.participantNames, ['Alex', 'Sam']);
      expect(parsed.rows, hasLength(1));
      final r = parsed.rows.single;
      expect(r.id, 'e1');
      expect(r.description, 'Dinner');
      expect(r.currency, 'EUR');
      expect(r.amountCents, 4200);
      expect(r.paidByName, 'Alex'); // resolved from participant id
      expect(r.sharesByName, {'Alex': 2100, 'Sam': 2100});
      expect(r.updatedAt, 1760000050000);
      expect(r.createdAt, 1760000000000);
    });

    test('decimal amounts convert to and from cents', () {
      final csv = buildGroupCsv(testGroup, members, [
        expense(amount: 1500, split: {'pa': 1500}),
      ]);
      expect(csv, contains('15.00'));
      final r = parseGroupCsv(csv).rows.single;
      expect(r.amountCents, 1500);
      expect(r.sharesByName, {'Alex': 1500});
    });

    test('quotes fields with commas, quotes and newlines (round-trip)', () {
      final tricky = 'Dinner, with "friends"\nand wine';
      final csv = buildGroupCsv(testGroup, members, [
        expense(description: tricky),
      ]);
      final r = parseGroupCsv(csv).rows.single;
      expect(r.description, tricky);
    });

    test('a participant name containing a comma survives round-trip', () {
      final weird = [m('pa', 'Alex, Jr.'), m('pb', 'Sam')];
      final csv = buildGroupCsv(testGroup, weird, [
        expense(split: {'pa': 1000, 'pb': 1000}, amount: 2000),
      ]);
      final parsed = parseGroupCsv(csv);
      expect(parsed.participantNames, containsAll(['Alex, Jr.', 'Sam']));
      expect(parsed.rows.single.sharesByName['Alex, Jr.'], 1000);
    });

    test('deleted expenses are not exported', () {
      final csv = buildGroupCsv(testGroup, members, [
        expense(id: 'e1'),
        expense(id: 'e2', deleted: true),
      ]);
      final parsed = parseGroupCsv(csv);
      expect(parsed.rows.map((r) => r.id), ['e1']);
    });

    test('shares only list participants in the split', () {
      final csv = buildGroupCsv(testGroup, members, [
        expense(split: {'pa': 2000}, amount: 2000),
      ]);
      final r = parseGroupCsv(csv).rows.single;
      expect(r.sharesByName, {'Alex': 2000});
      expect(r.sharesByName.containsKey('Sam'), isFalse);
    });

    test('empty group yields just a header (no rows)', () {
      final parsed = parseGroupCsv(buildGroupCsv(testGroup, members, []));
      expect(parsed.rows, isEmpty);
      expect(parsed.participantNames, ['Alex', 'Sam']);
    });
  });

  group('payments (G13)', () {
    const payment = SettlementModel(
      id: 's1',
      roomId: 'g1',
      amountCents: 2100,
      currency: 'EUR',
      fromUser: 'pb',
      toUser: 'pa',
      createdAt: 1760000100000,
      updatedAt: 1760000200000,
    );

    test('a payment is a readable row: payer, recipient share = amount', () {
      final csv = buildGroupCsv(testGroup, members, [expense()], [payment]);
      final lines = csv.split('\r\n');
      expect(
        lines.first,
        'Date,Type,Description,Category,Category Name,Note,Currency,Amount,'
        'Paid By,Alex,Sam,Expense ID,Group,Group ID,Updated At,Created At',
      );
      expect(
        lines[1],
        contains(',Expense,Dinner,,,,EUR,42.00,Alex,21.00,21.00,'),
      );
      expect(
        lines[2],
        contains(',Payment,Payment,,,,EUR,21.00,Sam,21.00,,s1,'),
      );
    });

    test('payments round-trip; deleted ones are skipped', () {
      final csv = buildGroupCsv(
        testGroup,
        members,
        [expense()],
        [
          payment,
          const SettlementModel(
            id: 's2',
            roomId: 'g1',
            amountCents: 5,
            currency: 'EUR',
            fromUser: 'pa',
            toUser: 'pb',
            createdAt: 1,
            updatedAt: 2,
            deleted: true,
          ),
        ],
      );
      final rows = parseGroupCsv(csv).rows;
      expect(rows, hasLength(2));
      expect(rows[0].isPayment, isFalse);
      expect(rows[0].paymentRecipient, isNull);
      final p = rows[1];
      expect(p.isPayment, isTrue);
      expect(p.id, 's1');
      expect(p.paidByName, 'Sam');
      expect(p.paymentRecipient, 'Alex');
      expect(p.amountCents, 2100);
      expect(p.updatedAt, 1760000200000);
    });

    test('a pre-G13 CSV without a Type column is all expenses', () {
      const old =
          'Date,Description,Currency,Amount,Paid By,Alex,Sam,'
          'Expense ID,Group,Group ID,Updated At\r\n'
          '2025-10-09T10:00:00.000,Dinner,EUR,42.00,Alex,21.00,21.00,'
          'e1,Trip,g1,1760000050000';
      final parsed = parseGroupCsv(old);
      expect(parsed.participantNames, ['Alex', 'Sam']);
      final r = parsed.rows.single;
      expect(r.isPayment, isFalse);
      expect(r.description, 'Dinner');
      expect(r.sharesByName, {'Alex': 2100, 'Sam': 2100});
    });

    test('a payment row with several shares is treated as an expense', () {
      const csv =
          'Date,Type,Description,Currency,Amount,Paid By,Alex,Sam,'
          'Expense ID,Group,Group ID,Updated At\r\n'
          '2025-10-09T10:00:00.000,Payment,Odd,EUR,2.00,Alex,1.00,1.00,'
          'x1,Trip,g1,1';
      final r = parseGroupCsv(csv).rows.single;
      expect(r.isPayment, isTrue);
      expect(r.paymentRecipient, isNull);
    });
  });

  group('categories + notes (G16)', () {
    test('round-trip; the note may hold commas, quotes and newlines', () {
      final e = ExpenseModel(
        id: 'e1',
        roomId: 'g1',
        description: 'Dinner',
        amountCents: 4200,
        currency: 'EUR',
        paidBy: 'pa',
        splitsJson: '{"pa":2100,"pb":2100}',
        createdAt: 1760000000000,
        updatedAt: 1760000050000,
        category: 'food',
        note: 'Tip "incl.", see\nreceipt',
      );
      final csv = buildGroupCsv(testGroup, members, [e, expense(id: 'e2')]);
      final rows = parseGroupCsv(csv).rows;
      expect(rows[0].category, 'food');
      expect(rows[0].note, 'Tip "incl.", see\nreceipt');
      expect(rows[0].sharesByName, {'Alex': 2100, 'Sam': 2100});
      expect(rows[1].category, isNull);
      expect(rows[1].note, isNull);
    });

    test('a pre-G16 CSV (no Category / Note columns) imports without them', () {
      const old =
          'Date,Type,Description,Currency,Amount,Paid By,Alex,Sam,'
          'Expense ID,Group,Group ID,Updated At\r\n'
          '2025-10-09T10:00:00.000,Expense,Dinner,EUR,42.00,Alex,21.00,21.00,'
          'e1,Trip,g1,1760000050000';
      final parsed = parseGroupCsv(old);
      expect(parsed.participantNames, ['Alex', 'Sam']);
      final r = parsed.rows.single;
      expect(r.category, isNull);
      expect(r.note, isNull);
      expect(r.sharesByName, {'Alex': 2100, 'Sam': 2100});
    });
  });

  group('custom categories (G47)', () {
    test('the id travels in Category, the name in Category Name', () {
      const g = GroupModel(
        roomId: 'g1',
        name: 'Trip',
        currency: 'EUR',
        updatedAt: 1000,
        categories: [
          CustomCategory(id: 'c:dog', name: 'Dog, Vet', icon: 'pets'),
        ],
      );
      ExpenseModel withCat(String id, String? cat) => ExpenseModel(
        id: id,
        roomId: 'g1',
        description: 'x',
        amountCents: 4200,
        currency: 'EUR',
        paidBy: 'pa',
        splitsJson: '{"pa":2100,"pb":2100}',
        createdAt: 1760000000000,
        updatedAt: 1760000050000,
        category: cat,
      );
      final csv = buildGroupCsv(g, members, [
        withCat('e1', 'c:dog'),
        withCat('e2', 'food'),
        withCat('e3', 'c:unknown'),
      ]);
      expect(csv.split('\r\n')[1], contains(',x,c:dog,"Dog, Vet",,EUR,'));
      final rows = parseGroupCsv(csv).rows;
      expect((rows[0].category, rows[0].categoryName), ('c:dog', 'Dog, Vet'));
      expect((rows[1].category, rows[1].categoryName), ('food', null));
      expect((rows[2].category, rows[2].categoryName), ('c:unknown', null));
      expect(rows[0].sharesByName, {'Alex': 2100, 'Sam': 2100});
    });
  });

  group('expense date (G49)', () {
    final created = DateTime(2026, 10, 17, 9, 30).millisecondsSinceEpoch;
    ExpenseModel dated(String id, String? date) => ExpenseModel(
      id: id,
      roomId: 'g1',
      description: 'x',
      amountCents: 4200,
      currency: 'EUR',
      paidBy: 'pa',
      splitsJson: '{"pa":2100,"pb":2100}',
      createdAt: created,
      updatedAt: created + 1000,
      date: date,
    );

    test('Date is the display day; Created At keeps the exact time', () {
      final csv = buildGroupCsv(testGroup, members, [
        dated('e1', '2026-10-10'),
        dated('e2', null),
      ]);
      final lines = csv.split('\r\n');
      expect(lines.first, endsWith(',Updated At,Created At'));
      expect(lines[1], startsWith('2026-10-10,Expense,'));
      expect(lines[1], endsWith(',$created'));
      expect(lines[2], startsWith('2026-10-17,Expense,'));

      final rows = parseGroupCsv(csv).rows;
      expect(rows[0].date, '2026-10-10');
      expect(rows[0].createdAt, created);
      expect(rows[1].date, isNull); // its own creation day → undated
      expect(rows[1].createdAt, created);
    });

    test('an edited Date cell back-dates the expense on import', () {
      final csv = buildGroupCsv(testGroup, members, [
        dated('e1', null),
      ]).replaceFirst('2026-10-17,Expense,', '2026-09-30,Expense,');
      final r = parseGroupCsv(csv).rows.single;
      expect(r.date, '2026-09-30');
      expect(r.createdAt, created);
    });

    test('a pre-G49 CSV (ISO time in Date, no Created At) is undated', () {
      const old =
          'Date,Type,Description,Currency,Amount,Paid By,Alex,Sam,'
          'Expense ID,Group,Group ID,Updated At\r\n'
          '2025-10-09T10:00:00.000,Expense,Dinner,EUR,42.00,Alex,21.00,21.00,'
          'e1,Trip,g1,1760000050000';
      final r = parseGroupCsv(old).rows.single;
      expect(r.date, isNull);
      expect(
        r.createdAt,
        DateTime.parse('2025-10-09T10:00:00.000').millisecondsSinceEpoch,
      );
    });
  });

  group('payment date (G60)', () {
    final created = DateTime(2026, 10, 17, 9, 30).millisecondsSinceEpoch;
    SettlementModel dated(String id, String? date) => SettlementModel(
      id: id,
      roomId: 'g1',
      amountCents: 2100,
      currency: 'EUR',
      fromUser: 'pb',
      toUser: 'pa',
      createdAt: created,
      updatedAt: created + 1000,
      date: date,
    );

    test('Date is the display day; back-dated payments round-trip', () {
      final csv = buildGroupCsv(testGroup, members, const [], [
        dated('s1', '2026-10-10'),
        dated('s2', null),
      ]);
      final lines = csv.split('\r\n');
      expect(lines[1], startsWith('2026-10-10,Payment,'));
      expect(lines[1], endsWith(',$created'));
      expect(lines[2], startsWith('2026-10-17,Payment,'));
      final rows = parseGroupCsv(csv).rows;
      expect(rows[0].paymentRecipient, 'Alex');
      expect(rows[0].date, '2026-10-10');
      expect(rows[0].createdAt, created);
      expect(rows[1].date, isNull);
    });
  });
}
