/// G9: leaving / deleting a group. Leaving marks our participant `removed`
/// for everyone and purges the group locally; a device-local tombstone keeps
/// late digests / bootstraps from resurrecting it — unless we are re-added.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

void main() {
  final dbs = <ProviderContainer, AppDatabase>{};

  ProviderContainer makeUser(FakeMatrixNetwork net, String userId,
      {String device = 'D1'}) {
    final db = openTestDatabase();
    net.clientFor(userId, device: device);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ledgerTransportProvider
          .overrideWith((ref) => net.clientFor(userId, device: device)),
      pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
      syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ]);
    dbs[container] = db;
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    container.listen(syncEngineProvider, (_, _) {});
    return container;
  }

  Future<String> seedGroup(ProviderContainer a, FakeMatrixNetwork net,
      {bool withBob = true}) async {
    await net.settle();
    await a.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await a.read(groupsDaoProvider).getAllGroups()).single.roomId;
    if (withBob) {
      await a.read(memberAdderProvider.notifier).add(groupId, bob);
    }
    await a.read(expenseAdderProvider.notifier).addExpense(
          roomId: groupId,
          description: 'Dinner',
          amountCents: 4000,
          currency: 'EUR',
          paidBy: alice,
          splits: withBob ? {alice: 2000, bob: 2000} : {alice: 4000},
        );
    await net.settle();
    return groupId;
  }

  Future<String?> statusOf(ProviderContainer c, String groupId, String mxid) async =>
      (await c.read(membersDaoProvider).memberByMatrixId(groupId, mxid))
          ?.status;

  Future<bool> hasGroup(ProviderContainer c, String groupId) async =>
      (await c.read(groupsDaoProvider).getGroup(groupId)) != null;

  /// Alice's current bootstrap for the group, sent straight at Bob.
  Future<void> sendBootstrap(ProviderContainer from, String fromId,
      String groupId, String to) async {
    final exp = from.read(expensesDaoProvider);
    await net(from).sendToUsers(
        {to},
        bootstrapEventType,
        buildBootstrapContent(
          groupId,
          await from.read(groupsDaoProvider).getGroup(groupId),
          await from.read(membersDaoProvider).getMembers(groupId),
          await exp.getAllExpensesForGroup(groupId),
          await exp.getAllSettlementsForGroup(groupId),
        ));
  }

  test('leaving: peers see us removed, the group is purged locally', () async {
    final n = FakeMatrixNetwork();
    final a = makeUser(n, alice);
    final b = makeUser(n, bob);
    final groupId = await seedGroup(a, n);
    expect(await hasGroup(b, groupId), isTrue, reason: 'sanity: bob joined');
    expect(groupExitKind(await b.read(membersDaoProvider).getMembers(groupId), bob),
        GroupExitKind.leave);

    await b.read(groupExiterProvider.notifier).leave(groupId);
    await n.settle();

    expect(b.read(groupExiterProvider).hasError, isFalse);
    expect(await statusOf(a, groupId, bob), 'removed');
    expect(await hasGroup(b, groupId), isFalse);
    expect(await b.read(membersDaoProvider).getMembers(groupId), isEmpty);
    expect(await b.read(expensesDaoProvider).getAllExpensesForGroup(groupId),
        isEmpty);
    expect(await SettingsDao(dbs[b]!).leftGroup(groupId), isNotNull);
    // Alice keeps the history (Bob's share is still attributed to him).
    expect(await a.read(expensesDaoProvider).getExpensesForRoom(groupId),
        hasLength(1));
  });

  test('after leaving, peers stop targeting us and late digests / bootstraps '
      'do not resurrect the group', () async {
    final n = FakeMatrixNetwork();
    final a = makeUser(n, alice);
    final b = makeUser(n, bob);
    final groupId = await seedGroup(a, n);
    await b.read(groupExiterProvider.notifier).leave(groupId);
    await n.settle();

    // Alice's regular digest cycle no longer targets Bob.
    n.sent.clear();
    await a.read(syncEngineProvider).broadcastDigests();
    await n.settle();
    expect(n.sent.where((s) => s.targets.contains(bob)), isEmpty);

    // A late digest still naming the group (sent before Alice learned of the
    // leave) must not trigger a resync — nor does a stale bootstrap.
    final staleDigest = {
      'v': 1,
      'group': groupId,
      'reply': false,
      'meta_updated_at': 1,
      'members': {
        bob: {'status': 'active', 'updated_at': 1, 'matrix_id': bob},
      },
      'expenses': const {},
      'settlements': const {},
    };
    n.sent.clear();
    await n.clientFor(alice).sendToUsers({bob}, digestEventType, staleDigest);
    await n.settle();
    expect(n.sent.where((s) => s.type == resyncRequestEventType), isEmpty);
    expect(await hasGroup(b, groupId), isFalse);

    // Even a full snapshot from Alice (which lists Bob removed) is ignored.
    await sendBootstrap(a, alice, groupId, bob);
    await n.settle();
    expect(await hasGroup(b, groupId), isFalse);
    expect(await b.read(membersDaoProvider).getMembers(groupId), isEmpty);
  });

  test('a lost leave notice is repaired from the tombstone (rule 7)', () async {
    final n = FakeMatrixNetwork();
    final a = makeUser(n, alice);
    final b = makeUser(n, bob);
    final groupId = await seedGroup(a, n);

    n.dropWhere = (_, _, type) => type == memberEventType;
    await b.read(groupExiterProvider.notifier).leave(groupId);
    await n.settle();
    n.dropWhere = null;
    expect(await statusOf(a, groupId, bob), 'active',
        reason: 'sanity: the leave notice was lost');
    expect(await hasGroup(b, groupId), isFalse);

    // Alice's next digest still lists Bob active → Bob answers with his
    // stored removal; nothing else, and the group stays gone on Bob.
    await a.read(syncEngineProvider).broadcastDigests();
    await n.settle();
    expect(await statusOf(a, groupId, bob), 'removed');
    expect(await hasGroup(b, groupId), isFalse);
  });

  test('re-adding us after leaving brings the group back', () async {
    final n = FakeMatrixNetwork();
    final a = makeUser(n, alice);
    final b = makeUser(n, bob);
    final groupId = await seedGroup(a, n);
    await b.read(groupExiterProvider.notifier).leave(groupId);
    await n.settle();
    expect(await hasGroup(b, groupId), isFalse);

    // Make sure the re-add clock is strictly newer than the leave.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await a.read(memberAdderProvider.notifier).add(groupId, bob);
    await n.settle();

    expect(await hasGroup(b, groupId), isTrue);
    expect(await statusOf(b, groupId, bob), 'active');
    expect(await b.read(expensesDaoProvider).getExpensesForRoom(groupId),
        hasLength(1));
    expect(await SettingsDao(dbs[b]!).leftGroup(groupId), isNull);
    // And live replication works again.
    await a.read(expenseAdderProvider.notifier).addExpense(
          roomId: groupId,
          description: 'Taxi',
          amountCents: 1000,
          currency: 'EUR',
          paidBy: alice,
          splits: {alice: 500, bob: 500},
        );
    await n.settle();
    expect(await b.read(expensesDaoProvider).getExpensesForRoom(groupId),
        hasLength(2));
  });

  test('deleting a solo group purges it; our other device cannot resurrect it',
      () async {
    final n = FakeMatrixNetwork();
    final a1 = makeUser(n, alice);
    final groupId = await seedGroup(a1, n, withBob: false);
    final a2 = makeUser(n, alice, device: 'D2');
    // D2 is a new device: its startup resync(all) pulls the group from D1.
    await n.settle();
    expect(await hasGroup(a2, groupId), isTrue, reason: 'sanity: D2 synced');
    expect(groupExitKind(
            await a1.read(membersDaoProvider).getMembers(groupId), alice),
        GroupExitKind.delete);

    n.sent.clear();
    await a1.read(groupExiterProvider.notifier).delete(groupId);
    await n.settle();
    expect(n.sent, isEmpty, reason: 'delete is purely local');
    expect(await hasGroup(a1, groupId), isFalse);
    expect(await hasGroup(a2, groupId), isTrue,
        reason: 'other devices keep their copy');

    // D2's digest (sent to self) and a full bootstrap from D2 are ignored.
    await a2.read(syncEngineProvider).broadcastDigests();
    await n.settle();
    await sendBootstrap(a2, alice, groupId, alice);
    await n.settle();
    expect(await hasGroup(a1, groupId), isFalse);
  });
}

LedgerTransport net(ProviderContainer c) => c.read(ledgerTransportProvider).value!;
