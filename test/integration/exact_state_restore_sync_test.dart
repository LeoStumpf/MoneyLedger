/// G58 over the in-memory relay: a restore point restored with "Exactly
/// this state" — the group's expenses / payments / meta are reset to the
/// snapshot as new versions signed by the restoring device (origins kept),
/// peers adopt them, participants are never touched.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/core/sync/sync_health.dart';
import 'package:money_ledger/features/backup/backup_service.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/history/group_reset.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

void main() {
  final dbs = <ProviderContainer, AppDatabase>{};

  ProviderContainer makeUser(FakeMatrixNetwork net, String userId) {
    final db = openTestDatabase();
    net.clientFor(userId);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
        digestOnStartProvider.overrideWithValue(false),
      ],
    );
    dbs[container] = db;
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    container.listen(syncEngineProvider, (_, _) {});
    container.listen(syncHealthProvider, (_, _) {});
    return container;
  }

  Future<void> add(ProviderContainer c, String g, String what, int cents) => c
      .read(expenseAdderProvider.notifier)
      .addExpense(
        roomId: g,
        description: what,
        amountCents: cents,
        currency: 'EUR',
        paidBy: alice,
        splits: {alice: cents},
      );

  test('an exact-state snapshot restore is relayed as new signed versions and '
      'adopted by peers; participants are untouched', () async {
    final n = FakeMatrixNetwork();
    final a = makeUser(n, alice);
    final b = makeUser(n, bob);
    await n.settle();
    await a.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final g = (await a.read(groupsDaoProvider).getAllGroups()).single.roomId;
    await a.read(memberAdderProvider.notifier).add(g, bob);
    await n.settle();
    await add(a, g, 'Dinner', 4000);
    await add(a, g, 'Taxi', 1500);
    await n.settle();

    // Alice's daily snapshot (the same export the restore points use).
    final snapshot = parseBackup(
      await a.read(backupServiceProvider).exportJson(account: alice, now: 1),
    );

    // Since then: Bob deletes Taxi, edits Dinner, adds Bogus, renames the
    // group; Alice adds a local person.
    final byName = {
      for (final e in await b.read(expensesDaoProvider).getExpensesForRoom(g))
        e.description: e,
    };
    final bobAdder = b.read(expenseAdderProvider.notifier);
    await bobAdder.deleteExpense(byName['Taxi']!.id, g);
    final d = byName['Dinner']!;
    await bobAdder.updateExpense(
      id: d.id,
      roomId: g,
      description: 'Dinner (changed)',
      amountCents: 9900,
      currency: 'EUR',
      paidBy: alice,
      splits: {alice: 9900},
      createdAt: d.createdAt,
    );
    await bobAdder.addExpense(
      roomId: g,
      description: 'Bogus',
      amountCents: 100,
      currency: 'EUR',
      paidBy: alice,
      splits: {alice: 100},
    );
    await b
        .read(groupEditorProvider.notifier)
        .edit(g, name: 'Renamed', currency: 'EUR');
    await a.read(memberAdderProvider.notifier).addLocal(g, 'Carol');
    await n.settle();
    final membersBefore = await a.read(membersDaoProvider).getMembers(g);
    expect(membersBefore, hasLength(3));

    // Alice restores the snapshot with "Exactly this state".
    a.listen(groupResetServiceProvider, (_, _) {});
    a.listen(backupServiceProvider, (_, _) {});
    final reset = a.read(groupResetServiceProvider);
    final plan = await reset.planToSnapshot(snapshot.groups.single, me: alice);
    expect(plan, isNotNull);
    expect(plan!.restored, 1);
    expect(plan.reverted, 1);
    expect(plan.removed, 1);
    expect(plan.meta?.name, 'Trip');
    final restored = await a.read(backupServiceProvider).restore(snapshot);
    expect(restored, [g]);
    expect(await reset.resetGroupsToSnapshot(snapshot, restored, me: alice), 4);
    await n.settle();

    for (final c in [a, b]) {
      final live = await c.read(expensesDaoProvider).getExpensesForRoom(g);
      expect(
        live.map((e) => '${e.description}:${e.amountCents}'),
        unorderedEquals(['Dinner:4000', 'Taxi:1500']),
      );
      for (final e in live) {
        expect(e.sig?.user, alice);
        expect(e.origin?.user, alice);
      }
      expect((await c.read(groupsDaoProvider).getGroup(g))!.name, 'Trip');
      // Participants are never reset: Carol (added after the snapshot)
      // stays, nobody's claim or status moved.
      final ms = await c.read(membersDaoProvider).getMembers(g);
      expect(
        ms.map((m) => '${m.displayName}|${m.matrixId}|${m.status}'),
        unorderedEquals(
          membersBefore.map(
            (m) => '${m.displayName}|${m.matrixId}|${m.status}',
          ),
        ),
      );
    }
    final bogus = (await b.read(expensesDaoProvider).getAllExpensesForGroup(g))
        .firstWhere((e) => e.description == 'Bogus');
    expect(bogus.deleted, isTrue);
    expect(bogus.origin?.user, bob);

    final ha = await HistoryDao(dbs[a]!).entriesForGroup(g);
    expect(ha.where((e) => e.source == HistorySource.revert), hasLength(4));

    // Restoring the same snapshot exactly again changes nothing.
    expect(await reset.resetGroupsToSnapshot(snapshot, [g], me: alice), 0);
  });

  test('a removed member\'s group is not reset (read-only history)', () async {
    final n = FakeMatrixNetwork();
    final a = makeUser(n, alice);
    final b = makeUser(n, bob);
    await n.settle();
    await a.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final g = (await a.read(groupsDaoProvider).getAllGroups()).single.roomId;
    await a.read(memberAdderProvider.notifier).add(g, bob);
    await n.settle();
    await add(a, g, 'Dinner', 4000);
    await n.settle();
    b.listen(backupServiceProvider, (_, _) {});
    final snapshot = parseBackup(
      await b.read(backupServiceProvider).exportJson(account: bob, now: 1),
    );
    await add(a, g, 'Later', 100);
    final bobId = (await a.read(membersDaoProvider).getMembers(g))
        .firstWhere((m) => m.matrixId == bob)
        .userId;
    await a.read(memberRemoverProvider.notifier).remove(g, bobId);
    await n.settle();
    b.listen(groupResetServiceProvider, (_, _) {});
    expect(
      await b
          .read(groupResetServiceProvider)
          .planToSnapshot(snapshot.groups.single, me: bob),
      isNull,
    );
  });
}
