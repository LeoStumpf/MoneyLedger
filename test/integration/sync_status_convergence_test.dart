/// G29: the sync status must turn "Synced" as soon as convergence is proven —
/// an inbound record from a peer that was in sync before, when it is the only
/// newer thing we hold, proves the peer holds everything we hold. Before, A
/// showed "Waiting for B…" after B's own change until a full digest
/// round-trip (poke debounce + two relay hops) had completed.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/peer_convergence.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

void main() {
  ProviderContainer makeUser(FakeMatrixNetwork net, String userId) {
    final db = openTestDatabase();
    net.clientFor(userId);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
    addTearDown(() {
      c.dispose();
      db.close();
    });
    c.listen(ledgerSyncerProvider, (_, _) {});
    c.listen(syncEngineProvider, (_, _) {});
    return c;
  }

  Future<String> seed(
    ProviderContainer a,
    ProviderContainer b,
    FakeMatrixNetwork net,
  ) async {
    await net.settle();
    await a.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await a.read(groupsDaoProvider).getAllGroups()).single.roomId;
    await a.read(memberAdderProvider.notifier).add(groupId, bob);
    await net.settle();
    await a.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    return groupId;
  }

  Future<GroupSyncStatus> statusOf(ProviderContainer c, String groupId) async {
    c.listen(groupSyncStatusProvider(groupId), (_, _) {});
    await c.read(groupMembersProvider(groupId).future);
    await c.read(peerSyncStatesProvider(groupId).future);
    await c.read(allExpensesForGroupProvider(groupId).future);
    await c.read(allSettlementsForGroupProvider(groupId).future);
    await c.read(ledgerGroupsProvider.future);
    await c.read(ledgerTransportProvider.future);
    return c.read(groupSyncStatusProvider(groupId));
  }

  Future<void> addExpense(ProviderContainer c, String groupId, String paidBy) =>
      c
          .read(expenseAdderProvider.notifier)
          .addExpense(
            roomId: groupId,
            description: 'Taxi',
            amountCents: 1400,
            currency: 'EUR',
            paidBy: paidBy,
            splits: {alice: 700, bob: 700},
          );

  test(
    'a peer\'s own change proves convergence without a digest round-trip',
    () async {
      final net = FakeMatrixNetwork();
      final a = makeUser(net, alice);
      final b = makeUser(net, bob);
      final groupId = await seed(a, b, net);
      expect(
        (await statusOf(a, groupId)).synced,
        isTrue,
        reason: 'sanity: the seed exchange proved convergence',
      );

      // No digests at all from now on: only the record itself reaches alice.
      net.dropWhere = (_, _, type) => type == digestEventType;
      await addExpense(b, groupId, bob);
      await net.settle();

      expect(
        await a.read(expensesDaoProvider).getExpensesForRoom(groupId),
        hasLength(1),
      );
      final s = await statusOf(a, groupId);
      expect(s.synced, isTrue, reason: 'bob sent the only newer record');
      expect(s.pendingPeers, isEmpty);
    },
  );

  test('not proven while we hold a newer record the peer may lack', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final groupId = await seed(a, b, net);

    // Alice's own expense is lost on the way to bob; digests stay off.
    net.dropWhere = (_, target, type) =>
        type == digestEventType || (target == bob && type == expenseEventType);
    await addExpense(a, groupId, alice);
    await net.settle();
    net.dropWhere = (_, _, type) => type == digestEventType;
    await addExpense(b, groupId, bob);
    await net.settle();

    final s = await statusOf(a, groupId);
    expect(
      s.synced,
      isFalse,
      reason: 'bob never got alice\'s expense — must not look synced',
    );
    expect(s.pendingPeers, {bob});

    // The regular digest exchange repairs bob and then proves convergence.
    net.dropWhere = null;
    await a.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    await a.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    expect((await statusOf(a, groupId)).synced, isTrue);
  });

  group('peerHoldsEverything', () {
    test('records up to the sync point are covered', () {
      expect(
        peerHoldsEverything(
          local: {'g': 1, 'e:1': 5},
          inSyncAt: 5,
          heldByPeer: const {},
        ),
        isTrue,
      );
    });
    test('a newer record the peer sent at the same revision is covered', () {
      expect(
        peerHoldsEverything(
          local: {'g': 1, 'e:1': 9},
          inSyncAt: 5,
          heldByPeer: {'e:1': 9},
        ),
        isTrue,
      );
    });
    test('a newer record at a different revision is not', () {
      expect(
        peerHoldsEverything(
          local: {'e:1': 9},
          inSyncAt: 5,
          heldByPeer: {'e:1': 8},
        ),
        isFalse,
      );
    });
    test('an unknown newer record blocks the proof', () {
      expect(
        peerHoldsEverything(
          local: {'e:1': 9, 's:2': 7},
          inSyncAt: 5,
          heldByPeer: {'e:1': 9},
        ),
        isFalse,
      );
    });
    test('inboundRecordRevision keys by record type', () {
      expect(
        inboundRecordRevision(expenseEventType, {'id': 'x', 'updated_at': 3}),
        (key: 'e:x', updatedAt: 3),
      );
      expect(
        inboundRecordRevision(memberEventType, {
          'participant_id': 'p',
          'updated_at': 4,
        }),
        (key: 'm:p', updatedAt: 4),
      );
      expect(
        inboundRecordRevision(bootstrapEventType, {'updated_at': 1}),
        isNull,
      );
    });
  });
}
