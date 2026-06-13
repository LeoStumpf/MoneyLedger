/// CSV import (Phase D, M2): parse a per-group sheet and merge it into Drift —
/// group/participants created as needed, expenses LWW-upserted by id.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/backup/csv_import.dart';
import 'package:money_ledger/features/backup/ledger_csv.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/in_memory_database.dart';

void main() {
  const grp =
      GroupModel(roomId: 'g1', name: 'Trip', currency: 'EUR', updatedAt: 1000);
  final members = [
    const MemberModel(
        groupId: 'g1', userId: 'pa', displayName: 'Alex', status: 'active', updatedAt: 1),
    const MemberModel(
        groupId: 'g1', userId: 'pb', displayName: 'Sam', status: 'active', updatedAt: 1),
  ];

  ExpenseModel exp({
    String id = 'e1',
    String desc = 'Dinner',
    int amount = 4200,
    int updatedAt = 1000,
    Map<String, int> split = const {'pa': 2100, 'pb': 2100},
  }) =>
      ExpenseModel(
        id: id,
        roomId: 'g1',
        description: desc,
        amountCents: amount,
        currency: 'EUR',
        paidBy: 'pa',
        splitsJson:
            '{${split.entries.map((e) => '"${e.key}":${e.value}').join(',')}}',
        createdAt: 1760000000000,
        updatedAt: updatedAt,
      );

  late ProviderContainer c;
  setUp(() {
    final db = openTestDatabase();
    c = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() {
      c.dispose();
      db.close();
    });
  });

  Future<int> import(String csv) =>
      c.read(csvImporterProvider.notifier).importCsv(csv);

  test('import into an empty DB creates the group, participants and expenses',
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

    final expenses = await c.read(expensesDaoProvider).getExpensesForRoom('g1');
    expect(expenses.single.description, 'Dinner');
    expect(expenses.single.amountCents, 4200);
    // paid_by + split keys are remapped to the new local participant ids.
    final pidByName = {for (final m in imported) m.displayName: m.userId};
    expect(expenses.single.paidBy, pidByName['Alex']);
    final splits = (jsonDecode(expenses.single.splitsJson) as Map);
    expect(splits[pidByName['Alex']], 2100);
    expect(splits[pidByName['Sam']], 2100);
  });

  test('re-importing the same CSV is idempotent (no duplicates)', () async {
    final csv = buildGroupCsv(grp, members, [exp()]);
    await import(csv);
    await import(csv);

    expect((await c.read(groupsDaoProvider).getAllGroups()), hasLength(1));
    expect((await c.read(membersDaoProvider).getMembers('g1')), hasLength(2));
    expect((await c.read(expensesDaoProvider).getExpensesForRoom('g1')),
        hasLength(1));
  });

  test('merge obeys LWW: newer row wins, staler row is ignored', () async {
    await import(buildGroupCsv(grp, members, [exp(amount: 4200, updatedAt: 1000)]));

    // Newer edit of the same expense id wins.
    await import(buildGroupCsv(grp, members, [exp(amount: 5000, updatedAt: 2000)]));
    var e = (await c.read(expensesDaoProvider).getExpensesForRoom('g1')).single;
    expect(e.amountCents, 5000);

    // A staler edit (lower clock) must not overwrite.
    await import(buildGroupCsv(grp, members, [exp(amount: 9999, updatedAt: 1500)]));
    e = (await c.read(expensesDaoProvider).getExpensesForRoom('g1')).single;
    expect(e.amountCents, 5000);
  });

  test('an unequal split round-trips, including an excluded participant',
      () async {
    // Alex covers 30.00, Sam 12.00; a third expense leaves Sam out entirely.
    final csv = buildGroupCsv(grp, members, [
      exp(id: 'e1', split: const {'pa': 3000, 'pb': 1200}),
      exp(id: 'e2', amount: 4200, split: const {'pa': 4200}), // Sam excluded
    ]);
    await import(csv);

    final imported = await c.read(membersDaoProvider).getMembers('g1');
    final pid = {for (final m in imported) m.displayName: m.userId};
    final expenses = await c.read(expensesDaoProvider).getExpensesForRoom('g1');
    final byId = {for (final e in expenses) e.id: e};

    final unequal = jsonDecode(byId['e1']!.splitsJson) as Map;
    expect(unequal[pid['Alex']], 3000);
    expect(unequal[pid['Sam']], 1200);

    // The excluded participant's blank column stays out of the split.
    final excluded = jsonDecode(byId['e2']!.splitsJson) as Map;
    expect(excluded[pid['Alex']], 4200);
    expect(excluded.containsKey(pid['Sam']), isFalse);
  });

  test('unknown participant names become local participants', () async {
    // A CSV referencing a payer/split name not present locally.
    final csv = buildGroupCsv(grp, members, [exp()]);
    await import(csv);
    final names = (await c.read(membersDaoProvider).getMembers('g1'))
        .map((m) => m.displayName)
        .toSet();
    expect(names, containsAll(['Alex', 'Sam']));
  });
}
