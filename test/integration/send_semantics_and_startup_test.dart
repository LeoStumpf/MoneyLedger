/// G24 (found in real-device testing):
/// 1. "Nothing could be sent" must be observable — a peer without any device
///    is reported distinctly (not a failure), an unavailable transport
///    (signed out / encryption off) is a failure.
/// 2. Inbound payloads that arrive before the sync components attach (app
///    start) are buffered and replayed, not lost until the next digest.
/// 3. Sign-in sends exactly one resync_request / one initial digest per group
///    — no duplicates from a sync engine on the signed-out placeholder DB.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/ledger_sync_host.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/core/sync/sync_health.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_auth_gateway.dart';
import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

void main() {
  /// A signed-in device whose sync runs via the app-level host only.
  ProviderContainer makeUser(FakeMatrixNetwork net, String userId,
      {bool attach = true}) {
    final db = openTestDatabase();
    net.clientFor(userId);
    final c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      accountUserIdProvider.overrideWithValue(userId),
      ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
      pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
      syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ]);
    addTearDown(() {
      c.dispose();
      db.close();
    });
    c.listen(syncHealthProvider, (_, _) {});
    if (attach) c.listen(ledgerSyncActiveProvider, (_, _) {});
    return c;
  }

  Future<String> createGroup(ProviderContainer c) async {
    await c.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    return (await c.read(groupsDaoProvider).getAllGroups()).single.roomId;
  }

  Future<void> addExpense(ProviderContainer c, String groupId, String what) =>
      c.read(expenseAdderProvider.notifier).addExpense(
        roomId: groupId,
        description: what,
        amountCents: 100,
        currency: 'EUR',
        paidBy: alice,
        splits: {alice: 50, bob: 50},
      );

  int countSent(FakeMatrixNetwork net, String sender, String type,
          {bool Function(Map<String, dynamic> c)? where}) =>
      net.sent
          .where((s) =>
              s.sender == sender &&
              s.type == type &&
              (where?.call(s.content) ?? true))
          .length;

  group('send semantics', () {
    test('a member without any device is reported, not counted as failure',
        () async {
      final net = FakeMatrixNetwork();
      final a = makeUser(net, alice);
      await net.settle();
      final groupId = await createGroup(a);
      await a.read(memberAdderProvider.notifier).add(groupId, bob); // no device
      await addExpense(a, groupId, 'One');
      await addExpense(a, groupId, 'Two');
      await net.settle();

      var health = a.read(syncHealthProvider);
      expect(health.failing, isFalse);
      expect(health.consecutiveFailures, 0);
      expect(health.unreachablePeers, {bob});

      // Bob signs in somewhere: the next send reaches him and clears it.
      makeUser(net, bob);
      await net.settle();
      await addExpense(a, groupId, 'Three');
      await net.settle();
      health = a.read(syncHealthProvider);
      expect(health.unreachablePeers, isEmpty);
    });

    test('an unavailable transport (encryption off) is a sync failure',
        () async {
      final net = FakeMatrixNetwork();
      final a = makeUser(net, alice);
      makeUser(net, bob);
      await net.settle();
      final groupId = await createGroup(a);
      await a.read(memberAdderProvider.notifier).add(groupId, bob);
      await net.settle();

      net.clientFor(alice).unavailable = true;
      for (var i = 0; i < kSyncFailureThreshold; i++) {
        await addExpense(a, groupId, 'Offline $i');
      }
      final health = a.read(syncHealthProvider);
      expect(health.failing, isTrue);
      expect(health.lastError, contains('Transport unavailable'));
      // The writes themselves are still saved locally.
      expect(
          await a.read(expensesDaoProvider).getAllExpensesForGroup(groupId),
          hasLength(kSyncFailureThreshold));
    });

    test('a digest is only marked sent to peers that had a device', () async {
      final net = FakeMatrixNetwork();
      final a = makeUser(net, alice);
      await net.settle();
      final groupId = await createGroup(a);
      await a.read(memberAdderProvider.notifier).add(groupId, bob); // no device
      await a.read(syncEngineProvider).broadcastDigests();
      await net.settle();

      final states =
          await a.read(syncStatesDaoProvider).getSyncStates(groupId);
      expect(states.where((s) => s.userId == bob && s.lastDigestSentAt > 0),
          isEmpty);
      expect(a.read(syncHealthProvider).unreachablePeers, {bob});
    });
  });

  group('startup buffering', () {
    Future<List<String>> bobExpensesAfterLateStart(
        {required bool buffered}) async {
      final net = FakeMatrixNetwork(bufferInbound: buffered);
      final a = makeUser(net, alice);
      // Bob's client exists (Matrix client built, background /sync running)
      // but his sync components haven't attached yet — like app start before
      // the account DB / LedgerSyncHost are up.
      final b = makeUser(net, bob, attach: false);
      await net.settle();

      final groupId = await createGroup(a);
      await a.read(memberAdderProvider.notifier).add(groupId, bob);
      await addExpense(a, groupId, 'G24 buffer');
      await net.settle();

      b.listen(ledgerSyncActiveProvider, (_, _) {}); // sync attaches late
      await net.settle();
      return [
        for (final e
            in await b.read(expensesDaoProvider).getAllExpensesForGroup(groupId))
          e.description
      ];
    }

    test('payloads received before the syncer attaches are replayed',
        () async {
      expect(await bobExpensesAfterLateStart(buffered: true), ['G24 buffer']);
    });

    test('(control) without buffering they are lost until the next digest',
        () async {
      expect(await bobExpensesAfterLateStart(buffered: false), isEmpty);
    });
  });

  group('no duplicate startup sends', () {
    /// A device going through the real sign-in chain, with both the app-level
    /// sync host **and** a page that watches the engine directly (as
    /// GroupsPage/ExpensesPage do) — before and across the login.
    Future<ProviderContainer> signIn(
        FakeMatrixNetwork net, AppDatabase Function() openDb) async {
      final gateway = FakeAuthGateway();
      final c = ProviderContainer(overrides: [
        authGatewayProvider.overrideWith((ref) => gateway),
        accountDatabaseOpenerProvider.overrideWithValue((_) => openDb()),
        ledgerTransportProvider.overrideWith((ref) async => net.clientFor(alice)),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ]);
      addTearDown(() {
        c.dispose();
        gateway.dispose();
      });
      c.listen(ledgerSyncActiveProvider, (_, _) {});
      c.listen(syncEngineProvider, (_, _) {}); // a page watching the engine
      c.listen(ledgerSyncerProvider, (_, _) {});
      await net.settle();
      await c.read(authProvider.notifier).login(
          resolvedHomeserver: 'https://x.org', username: 'alice', password: 'pw');
      await net.settle();
      return c;
    }

    test('a fresh device sends exactly one resync_request on sign-in',
        () async {
      final net = FakeMatrixNetwork();
      net.clientFor(alice, device: 'D2'); // another own device to answer
      await signIn(net, openTestDatabase);
      expect(countSent(net, alice, resyncRequestEventType), 1);
    });

    test('an existing ledger sends exactly one initial digest per group',
        () async {
      final net = FakeMatrixNetwork();
      final db = openTestDatabase();
      addTearDown(db.close);
      for (final g in ['g1', 'g2']) {
        await db.into(db.groups).insert(GroupsCompanion.insert(
            roomId: g, name: g, updatedAt: const Value(1)));
        await db.into(db.members).insert(MembersCompanion(
              groupId: Value(g),
              userId: const Value(alice),
              matrixId: const Value(alice),
              displayName: const Value('Alice'),
              status: const Value('active'),
              updatedAt: const Value(1),
            ));
      }
      await signIn(net, () => db);

      expect(countSent(net, alice, resyncRequestEventType), 0);
      for (final g in ['g1', 'g2']) {
        expect(
            countSent(net, alice, digestEventType,
                where: (c) => c['group'] == g && c['reply'] == false),
            1,
            reason: 'group $g');
      }
    });

    test('a burst of digests for an unknown group asks for it only once',
        () async {
      final net = FakeMatrixNetwork();
      makeUser(net, alice);
      await net.settle();
      Map<String, dynamic> digest() => {
            'v': protocolVersion,
            'group': 'unknown-group',
            'reply': false,
            'meta_updated_at': 1,
            'members': const {},
            'expenses': const {},
            'settlements': const {},
          };
      // Two devices of a peer answer at once.
      await net.clientFor(bob).sendToUsers({alice}, digestEventType, digest());
      await net
          .clientFor(bob, device: 'D2')
          .sendToUsers({alice}, digestEventType, digest());
      await net.settle();

      expect(
          countSent(net, alice, resyncRequestEventType,
              where: (c) => c['scope'] == 'group'),
          1);
    });
  });
}
