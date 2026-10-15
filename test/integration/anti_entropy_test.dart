/// Anti-entropy integration tests (Phase C): lost to-device messages must be
/// detected and repaired by the digest exchange, never silently diverge.
/// Same multi-container setup as multi_user_group_visibility_test.dart, plus
/// each user's SyncEngine running with test-fast timings and the fake
/// network's loss injection.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

void main() {
  ProviderContainer makeUser(FakeMatrixNetwork net, String userId) {
    final db = openTestDatabase();
    net.clientFor(userId);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
      // Test-fast timings: pokes fire almost immediately; the periodic timer
      // never fires within a test (digest cycles are triggered explicitly).
      pokeDebounceProvider
          .overrideWithValue(const Duration(milliseconds: 1)),
      syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ]);
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    container.listen(syncEngineProvider, (_, _) {});
    return container;
  }


  Future<String> seedGroupWithBob(
      ProviderContainer alice, FakeMatrixNetwork net) async {
    await net.settle();
    await alice.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await alice.read(groupsDaoProvider).watchAllGroups().first)
            .first
            .roomId;
    await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
    await net.settle();
    return groupId;
  }

  Future<void> addExpenseAs(ProviderContainer user, String groupId,
          String description, String paidBy) =>
      user.read(expenseAdderProvider.notifier).addExpense(
        roomId: groupId,
        description: description,
        amountCents: 4000,
        currency: 'EUR',
        paidBy: paidBy,
        splits: {'@alice:x.org': 2000, '@bob:y.org': 2000},
      );

  test('a dropped expense relay is repaired by one digest cycle', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    final groupId = await seedGroupWithBob(alice, net);

    // The live relay of the expense is lost in transit.
    net.dropWhere = (_, _, type) => type == expenseEventType;
    await addExpenseAs(alice, groupId, 'Lost dinner', '@alice:x.org');
    await net.settle();
    expect(await bob.read(expensesDaoProvider).getExpensesForRoom(groupId),
        isEmpty,
        reason: 'sanity: the live relay was dropped');

    // Network heals; the next digest cycle must repair Bob.
    net.dropWhere = null;
    await alice.read(syncEngineProvider).broadcastDigests();
    await net.settle();

    final bobExpenses =
        await bob.read(expensesDaoProvider).getExpensesForRoom(groupId);
    expect(bobExpenses, hasLength(1));
    expect(bobExpenses.single.description, 'Lost dinner');

    // The follow-up digests prove convergence to both sides (sync-status UI).
    await net.settle();
    final aliceStates =
        await alice.read(syncStatesDaoProvider).getSyncStates(groupId);
    final bobSeenByAlice =
        aliceStates.where((s) => s.userId == '@bob:y.org').single;
    expect(bobSeenByAlice.lastInSyncAt, greaterThan(0));
  });

  test('a lost delete is repaired — the tombstone wins over the stale peer',
      () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    final groupId = await seedGroupWithBob(alice, net);

    await addExpenseAs(alice, groupId, 'Mistake', '@alice:x.org');
    await net.settle();
    final expense = (await alice
            .read(expensesDaoProvider)
            .getExpensesForRoom(groupId))
        .single;

    // Bob misses the deletion.
    net.dropWhere = (_, _, type) => type == expenseEventType;
    await alice
        .read(expenseAdderProvider.notifier)
        .deleteExpense(expense.id, groupId);
    await net.settle();
    expect(await bob.read(expensesDaoProvider).getExpensesForRoom(groupId),
        hasLength(1),
        reason: 'sanity: bob still has the stale live copy');

    // Bob's own digest advertises the stale revision — Alice must answer with
    // the tombstone, and Bob must never re-instate the record.
    net.dropWhere = null;
    await bob.read(syncEngineProvider).broadcastDigests();
    await net.settle();

    final bobDao = bob.read(expensesDaoProvider);
    expect(await bobDao.getExpensesForRoom(groupId), isEmpty);
    expect((await bobDao.getAllExpensesForGroup(groupId)).single.deleted, true);
    // And alice's copy was not resurrected by bob's stale digest.
    expect(
        await alice.read(expensesDaoProvider).getExpensesForRoom(groupId),
        isEmpty);
  });

  test("a removed member's device learns of its removal from its own digest",
      () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    final groupId = await seedGroupWithBob(alice, net);

    // Bob never hears he was removed.
    net.dropWhere = (_, _, type) => type == memberEventType;
    await alice
        .read(memberRemoverProvider.notifier)
        .remove(groupId, '@bob:y.org');
    await net.settle();
    final bobSelfBefore = (await bob
            .read(membersDaoProvider)
            .getMembers(groupId))
        .firstWhere((m) => m.userId == '@bob:y.org');
    expect(bobSelfBefore.status, 'active',
        reason: 'sanity: the removal relay was dropped');

    // Bob digests as usual; Alice answers a removed sender only with their
    // member tombstone.
    net.dropWhere = null;
    await bob.read(syncEngineProvider).broadcastDigests();
    await net.settle();

    final bobSelf = (await bob.read(membersDaoProvider).getMembers(groupId))
        .firstWhere((m) => m.userId == '@bob:y.org');
    expect(bobSelf.status, 'removed');
  });

  test('a member who missed the bootstrap recovers via resync_request',
      () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await net.settle();

    await alice.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await alice.read(groupsDaoProvider).watchAllGroups().first)
            .first
            .roomId;
    await addExpenseAs(alice, groupId, 'Pre-join dinner', '@alice:x.org');

    // Bob is added but the bootstrap payload is lost — he knows nothing.
    net.dropWhere = (_, _, type) => type == bootstrapEventType;
    await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
    await net.settle();
    expect(await bob.read(groupsDaoProvider).watchAllGroups().first, isEmpty,
        reason: 'sanity: the bootstrap was dropped');

    // Alice's digest names a group Bob doesn't know → Bob requests a resync
    // → Alice verifies membership and re-sends the bootstrap.
    net.dropWhere = null;
    await alice.read(syncEngineProvider).broadcastDigests();
    await net.settle();

    final bobGroups = await bob.read(groupsDaoProvider).watchAllGroups().first;
    expect(bobGroups, hasLength(1));
    final bobExpenses =
        await bob.read(expensesDaoProvider).getExpensesForRoom(groupId);
    expect(bobExpenses.single.description, 'Pre-join dinner');
  });

  test('digest exchange is bounded: one primary, one reply, no ping-pong',
      () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    final groupId = await seedGroupWithBob(alice, net);
    await addExpenseAs(alice, groupId, 'Dinner', '@alice:x.org');
    await net.settle();
    await net.settle(); // drain post-receipt ack digests before counting

    final digests = <TransportMessage>[];
    net.clientFor('@alice:x.org').onMessage.listen((m) {
      if (m.type == digestEventType) digests.add(m);
    });
    net.clientFor('@bob:y.org').onMessage.listen((m) {
      if (m.type == digestEventType) digests.add(m);
    });

    await alice.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    await net.settle();

    // Exactly alice→bob (primary) and bob→alice (reply); states are in sync
    // so nothing further is triggered.
    expect(digests, hasLength(2));
    expect(digests[0].content['reply'], false);
    expect(digests[1].content['reply'], true);

    // Both sides recorded the other as in sync.
    final aliceView = (await alice
            .read(syncStatesDaoProvider)
            .getSyncStates(groupId))
        .firstWhere((s) => s.userId == '@bob:y.org');
    final bobView =
        (await bob.read(syncStatesDaoProvider).getSyncStates(groupId))
            .firstWhere((s) => s.userId == '@alice:x.org');
    expect(aliceView.lastInSyncAt, greaterThan(0));
    expect(bobView.lastInSyncAt, greaterThan(0));
  });
}
