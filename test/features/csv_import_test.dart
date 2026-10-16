/// CSV import (Phase D, M2): parse a per-group sheet and merge it into Drift —
/// group/participants created as needed, expenses LWW-upserted by id.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/backup/csv_import.dart';
import 'package:money_ledger/features/backup/ledger_csv.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'package:money_ledger/core/matrix/transport_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

void main() {
  const grp = GroupModel(
    roomId: 'g1',
    name: 'Trip',
    currency: 'EUR',
    updatedAt: 1000,
  );
  final members = [
    const MemberModel(
      groupId: 'g1',
      userId: 'pa',
      displayName: 'Alex',
      status: 'active',
      updatedAt: 1,
    ),
    const MemberModel(
      groupId: 'g1',
      userId: 'pb',
      displayName: 'Sam',
      status: 'active',
      updatedAt: 1,
    ),
  ];

  ExpenseModel exp({
    String id = 'e1',
    String desc = 'Dinner',
    int amount = 4200,
    int updatedAt = 1000,
    Map<String, int>? split,
  }) => ExpenseModel(
    id: id,
    roomId: 'g1',
    description: desc,
    amountCents: amount,
    currency: 'EUR',
    paidBy: 'pa',
    // Default: halves that sum to the amount (G18 review: import validates).
    splitsJson:
        '{${(split ?? {'pa': amount - amount ~/ 2, 'pb': amount ~/ 2}).entries.map((e) => '"${e.key}":${e.value}').join(',')}}',
    createdAt: 1760000000000,
    updatedAt: updatedAt,
  );

  late ProviderContainer c;
  setUp(() {
    final db = openTestDatabase();
    final net = FakeMatrixNetwork();
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith(
          (ref) => net.clientFor('@importer:x.org'),
        ),
      ],
    );
    addTearDown(() {
      c.dispose();
      db.close();
    });
  });

  Future<int> import(String csv) => c
      .read(csvImporterProvider.notifier)
      .importCsv(csv)
      .then((r) => r.expenses);

  test(
    'import into an empty DB creates the group, participants and expenses',
    () async {
      final count = await import(buildGroupCsv(grp, members, [exp()]));
      expect(count, 1);

      final groups = await c.read(groupsDaoProvider).getAllGroups();
      expect(groups.single.roomId, 'g1');
      expect(groups.single.name, 'Trip');

      final imported = await c.read(membersDaoProvider).getMembers('g1');
      expect(imported.map((m) => m.displayName), containsAll(['Alex', 'Sam']));
      // Imported participants are local (no Matrix account yet).
      expect(imported.every((m) => m.matrixId == null), isTrue);

      final expenses = await c
          .read(expensesDaoProvider)
          .getExpensesForRoom('g1');
      expect(expenses.single.description, 'Dinner');
      expect(expenses.single.amountCents, 4200);
      // paid_by + split keys are remapped to the new local participant ids.
      final pidByName = {for (final m in imported) m.displayName: m.userId};
      expect(expenses.single.paidBy, pidByName['Alex']);
      final splits = (jsonDecode(expenses.single.splitsJson) as Map);
      expect(splits[pidByName['Alex']], 2100);
      expect(splits[pidByName['Sam']], 2100);
    },
  );

  test('G6: imported rows are signed by the importing device (as creator '
      'and editor); a row that does not win is not re-signed', () async {
    await import(buildGroupCsv(grp, members, [exp(updatedAt: 2000)]));
    final e = await c.read(expensesDaoProvider).getExpenseById('e1');
    expect(e!.sig!.user, '@importer:x.org');
    expect(e.origin!.user, '@importer:x.org');
    final g = await c.read(groupsDaoProvider).getGroup('g1');
    expect(g!.sig!.user, '@importer:x.org');
    final ms = await c.read(membersDaoProvider).getMembers('g1');
    expect(ms.every((m) => m.sig != null), isTrue);

    await import(buildGroupCsv(grp, members, [exp(updatedAt: 1500)]));
    final again = await c.read(expensesDaoProvider).getExpenseById('e1');
    expect(again!.sig, e.sig, reason: 'stale row skipped, nothing re-signed');
  });

  test('G22: the importer notifier survives the async file-picker gap '
      '(read once, used after awaits with no listener)', () async {
    // importCsvWithPreview reads the notifier, then awaits the picker and a
    // dialog — an auto-disposed provider was gone by then ("Cannot use the
    // Ref of csvImporterProvider after it has been disposed", seen on device).
    final importer = c.read(csvImporterProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final csv = buildGroupCsv(grp, members, [exp()]);
    final preview = await importer.preview(csv);
    expect(preview.isNewGroup, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final r = await importer.importCsv(csv);
    expect(r.expenses, 1);
  });

  test('re-importing the same CSV is idempotent (no duplicates)', () async {
    final csv = buildGroupCsv(grp, members, [exp()]);
    await import(csv);
    await import(csv);

    expect((await c.read(groupsDaoProvider).getAllGroups()), hasLength(1));
    expect((await c.read(membersDaoProvider).getMembers('g1')), hasLength(2));
    expect(
      (await c.read(expensesDaoProvider).getExpensesForRoom('g1')),
      hasLength(1),
    );
  });

  test('merge obeys LWW: newer row wins, staler row is ignored', () async {
    await import(
      buildGroupCsv(grp, members, [exp(amount: 4200, updatedAt: 1000)]),
    );

    // Newer edit of the same expense id wins.
    await import(
      buildGroupCsv(grp, members, [exp(amount: 5000, updatedAt: 2000)]),
    );
    var e = (await c.read(expensesDaoProvider).getExpensesForRoom('g1')).single;
    expect(e.amountCents, 5000);

    // A staler edit (lower clock) must not overwrite.
    await import(
      buildGroupCsv(grp, members, [exp(amount: 9999, updatedAt: 1500)]),
    );
    e = (await c.read(expensesDaoProvider).getExpensesForRoom('g1')).single;
    expect(e.amountCents, 5000);
  });

  test(
    'an unequal split round-trips, including an excluded participant',
    () async {
      // Alex covers 30.00, Sam 12.00; a third expense leaves Sam out entirely.
      final csv = buildGroupCsv(grp, members, [
        exp(id: 'e1', split: const {'pa': 3000, 'pb': 1200}),
        exp(id: 'e2', amount: 4200, split: const {'pa': 4200}), // Sam excluded
      ]);
      await import(csv);

      final imported = await c.read(membersDaoProvider).getMembers('g1');
      final pid = {for (final m in imported) m.displayName: m.userId};
      final expenses = await c
          .read(expensesDaoProvider)
          .getExpensesForRoom('g1');
      final byId = {for (final e in expenses) e.id: e};

      final unequal = jsonDecode(byId['e1']!.splitsJson) as Map;
      expect(unequal[pid['Alex']], 3000);
      expect(unequal[pid['Sam']], 1200);

      // The excluded participant's blank column stays out of the split.
      final excluded = jsonDecode(byId['e2']!.splitsJson) as Map;
      expect(excluded[pid['Alex']], 4200);
      expect(excluded.containsKey(pid['Sam']), isFalse);
    },
  );

  test('unknown participant names become local participants', () async {
    // A CSV referencing a payer/split name not present locally.
    final csv = buildGroupCsv(grp, members, [exp()]);
    await import(csv);
    final names = (await c.read(membersDaoProvider).getMembers('g1'))
        .map((m) => m.displayName)
        .toSet();
    expect(names, containsAll(['Alex', 'Sam']));
  });

  group('payments + name warnings (G13)', () {
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

    test('payments import as settlements, idempotently', () async {
      final csv = buildGroupCsv(grp, members, [exp()], [payment]);
      final r1 = await c.read(csvImporterProvider.notifier).importCsv(csv);
      expect(r1, (expenses: 1, payments: 1));
      await c.read(csvImporterProvider.notifier).importCsv(csv);

      final pid = {
        for (final m in await c.read(membersDaoProvider).getMembers('g1'))
          m.displayName: m.userId,
      };
      final s = await c
          .read(expensesDaoProvider)
          .getAllSettlementsForGroup('g1');
      expect(s, hasLength(1));
      expect(s.single.id, 's1');
      expect(s.single.fromUser, pid['Sam']);
      expect(s.single.toUser, pid['Alex']);
      expect(s.single.amountCents, 2100);
      expect(s.single.updatedAt, 1760000200000);
      expect(
        await c.read(expensesDaoProvider).getExpensesForRoom('g1'),
        hasLength(1),
      );
    });

    test('preview of a new group lists no name warnings', () async {
      final p = await c
          .read(csvImporterProvider.notifier)
          .preview(buildGroupCsv(grp, members, [exp()], [payment]));
      expect(p.isNewGroup, isTrue);
      expect(p.groupName, 'Trip');
      expect(p.expenseCount, 1);
      expect(p.paymentCount, 1);
      expect(p.unmatched, isEmpty);
      expect(p.ambiguous, isEmpty);
    });

    test('preview into an existing group warns about unknown and duplicate '
        'names', () async {
      // Existing group with two "Alex" participants and no "Sam".
      await c
          .read(groupsDaoProvider)
          .upsertGroupLww(
            const GroupsCompanion(
              roomId: Value('g1'),
              name: Value('Trip'),
              currency: Value('EUR'),
              updatedAt: Value(1),
            ),
          );
      for (final (pid, status) in [('a1', 'removed'), ('a2', 'active')]) {
        await c
            .read(membersDaoProvider)
            .upsertMemberLww(
              MembersCompanion(
                groupId: const Value('g1'),
                userId: Value(pid),
                displayName: const Value('Alex'),
                status: Value(status),
                updatedAt: const Value(1),
              ),
            );
      }
      final csv = buildGroupCsv(grp, members, [exp()]);
      final p = await c.read(csvImporterProvider.notifier).preview(csv);
      expect(p.isNewGroup, isFalse);
      expect(p.unmatched, ['Sam']);
      expect(p.ambiguous, ['Alex']);

      // The import does what the preview said: the active Alex is used, Sam
      // becomes a new local person.
      await import(csv);
      final e =
          (await c.read(expensesDaoProvider).getExpensesForRoom('g1')).single;
      expect(e.paidBy, 'a2');
      final names = (await c.read(membersDaoProvider).getMembers('g1')).map(
        (m) => m.displayName,
      );
      expect(names.where((n) => n == 'Sam'), hasLength(1));
    });
  });

  test('resolveCsvNames matches by label, prefers active participants', () {
    const ms = [
      MemberModel(
        groupId: 'g',
        userId: 'x1',
        displayName: 'Bo',
        status: 'removed',
        updatedAt: 1,
      ),
      MemberModel(
        groupId: 'g',
        userId: 'x2',
        displayName: 'Bo',
        status: 'active',
        updatedAt: 1,
      ),
      MemberModel(
        groupId: 'g',
        userId: '@cy:x',
        displayName: '',
        matrixId: '@cy:x',
        status: 'active',
        updatedAt: 1,
      ),
    ];
    final r = resolveCsvNames(['Bo', '@cy:x', 'Dee', ''], ms);
    expect(r.pidByName, {'Bo': 'x2', '@cy:x': '@cy:x'});
    expect(r.unmatched, ['Dee']);
    expect(r.ambiguous, ['Bo']);
  });

  // G18 review (findings 8, 13).
  group('G18 review', () {
    // G18 review 2 (Minor 2).
    test("an Expense ID of another group's record aborts the import — the "
        'record is never moved', () async {
      await import(buildGroupCsv(grp, members, [exp(id: 'shared-id')]));
      const other = GroupModel(
        roomId: 'g2',
        name: 'Flat',
        currency: 'EUR',
        updatedAt: 1000,
      );
      final otherMembers = [
        for (final m in members)
          MemberModel(
            groupId: 'g2',
            userId: m.userId,
            displayName: m.displayName,
            status: 'active',
            updatedAt: 1,
          ),
      ];
      final csv = buildGroupCsv(other, otherMembers, [
        exp(id: 'shared-id', desc: 'Moved', updatedAt: 999999),
      ]).replaceAll(',g1,', ',g2,');
      await expectLater(
        import(csv),
        throwsA(
          isA<CsvImportException>().having(
            (e) => e.problem,
            'problem',
            kCsvForeignIdProblem,
          ),
        ),
      );
      final e = (await c
          .read(expensesDaoProvider)
          .getExpenseById('shared-id'))!;
      expect(e.roomId, 'g1');
      expect(e.description, 'Dinner');
      expect(await c.read(groupsDaoProvider).getGroup('g2'), isNull);
    });

    test('a far-future Updated At is clamped to now on import', () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      await import(
        buildGroupCsv(grp, members, [exp(updatedAt: 9000000000000000)]),
      );
      final e = (await c.read(expensesDaoProvider).getExpenseById('e1'))!;
      expect(e.updatedAt, inInclusiveRange(before, before + 60000));
      // …so a normal later edit still wins.
      expect(e.createdAt, lessThanOrEqualTo(e.updatedAt));
    });

    test(
      'an invalid row aborts the whole import — nothing is written',
      () async {
        final good = buildGroupCsv(grp, members, [
          exp(id: 'ok'),
          exp(id: 'bad', amount: 4200, split: const {'pa': 1}),
        ]);
        await expectLater(import(good), throwsA(isA<CsvImportException>()));
        expect(await c.read(groupsDaoProvider).getAllGroups(), isEmpty);
        expect(await c.read(membersDaoProvider).getMembers('g1'), isEmpty);
        expect(await c.read(expensesDaoProvider).getExpenseById('ok'), isNull);
      },
    );

    test(
      'unreadable / negative money cells are refused, grouping is read',
      () async {
        String withAmount(String cell, {String share = ''}) {
          final lines = const LineSplitter().convert(
            buildGroupCsv(grp, members, [exp()]),
          );
          final header = _row(lines[0]);
          final row = _row(lines[1]);
          row[header.indexOf('Amount')] = cell;
          if (share.isNotEmpty) row[header.indexOf('Alex')] = share;
          return '${lines[0]}\r\n${row.map(_q).join(',')}';
        }

        for (final bad in ['-42.00', 'NaN', '12,34.5', '1e5', 'abc']) {
          await expectLater(
            import(withAmount(bad)),
            throwsA(isA<CsvImportException>()),
            reason: bad,
          );
        }
        final parsed = parseGroupCsv(withAmount('4,200.00', share: '2,100.00'));
        expect(parsed.rows.single.problem, isNull);
        expect(parsed.rows.single.amountCents, 420000);
        expect(parsed.rows.single.sharesByName['Alex'], 210000);
        expect(parseGroupCsv(withAmount('-1')).rows.single.problem, isNotNull);
      },
    );
  });
}

List<String> _row(String line) => line.split(',');
String _q(String f) => f.contains(',') ? '"$f"' : f;
