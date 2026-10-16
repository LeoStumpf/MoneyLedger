/// G48 over the in-memory relay: Bob deletes / edits / adds entries, Alice
/// resets the group to the state before — the reset is written as new
/// versions signed by Alice (origins kept) and Bob's device adopts it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/core/sync/sync_health.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/history/group_history.dart';
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

  test(
    'a reset is relayed as new signed versions and adopted by peers',
    () async {
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
      await add(a, g, 'Museum', 2000);
      await n.settle();
      final before = await b.read(expensesDaoProvider).getExpensesForRoom(g);
      expect(before, hasLength(3));
      final byName = {for (final e in before) e.description: e};

      // Alice's history up to here; everything after is "the attack".
      final point = await HistoryDao(dbs[a]!).latestId() + 1;

      // Bob deletes two, edits one, adds one.
      final bobAdder = b.read(expenseAdderProvider.notifier);
      await bobAdder.deleteExpense(byName['Dinner']!.id, g);
      await bobAdder.deleteExpense(byName['Taxi']!.id, g);
      final m = byName['Museum']!;
      await bobAdder.updateExpense(
        id: m.id,
        roomId: g,
        description: 'Museum (changed)',
        amountCents: 9900,
        currency: 'EUR',
        paidBy: alice,
        splits: {alice: 9900},
        createdAt: m.createdAt,
      );
      await bobAdder.addExpense(
        roomId: g,
        description: 'Bogus',
        amountCents: 100,
        currency: 'EUR',
        paidBy: alice,
        splits: {alice: 100},
      );
      await n.settle();
      expect(
        (await a.read(expensesDaoProvider).getExpensesForRoom(g)).map(
          (e) => e.description,
        ),
        unorderedEquals(['Museum (changed)', 'Bogus']),
      );

      // Alice resets to before Bob's changes.
      a.listen(groupResetServiceProvider, (_, _) {});
      final service = a.read(groupResetServiceProvider);
      final plan = await service.plan(g, point);
      expect(plan.restored, 2);
      expect(plan.reverted, 1);
      expect(plan.removed, 1);
      expect(await service.apply(plan), 4);
      await n.settle();

      for (final c in [a, b]) {
        final live = await c.read(expensesDaoProvider).getExpensesForRoom(g);
        expect(
          live.map((e) => '${e.description}:${e.amountCents}'),
          unorderedEquals(['Dinner:4000', 'Taxi:1500', 'Museum:2000']),
        );
        for (final e in live) {
          // Signed by Alice as editor, "added by" unchanged (Alice created).
          expect(e.sig?.user, alice);
          expect(e.origin?.user, alice);
        }
      }
      final bogus =
          (await b.read(expensesDaoProvider).getAllExpensesForGroup(g))
              .firstWhere((e) => e.description == 'Bogus');
      expect(bogus.deleted, isTrue);
      // Bob created it — the tombstone keeps his origin.
      expect(bogus.origin?.user, bob);
      expect(bogus.sig?.user, alice);

      // Alice's history marks the reset; Bob's records it as inbound.
      final ha = await HistoryDao(dbs[a]!).entriesForGroup(g);
      expect(ha.where((e) => e.source == HistorySource.revert), hasLength(4));
      final hb = await HistoryDao(dbs[b]!).entriesForGroup(g);
      expect(hb.last.source, HistorySource.inbound);

      // A reset can itself be undone the same way (back to the attack state).
      final undo = await service.plan(
        g,
        ha.firstWhere((e) => e.source == HistorySource.revert).id,
      );
      expect(undo.changes, hasLength(4));
      expect(
        undo.changes.where((c) => c.effect == ResetEffect.removed),
        hasLength(2),
      );
    },
  );
}
