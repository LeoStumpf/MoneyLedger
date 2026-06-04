/// Multi-user, cross-homeserver integration tests driven entirely by the
/// in-memory [FakeMatrixNetwork] — no real homeserver, no network, no auth.
///
/// Each user is a separate [ProviderContainer] (its own "device": own Drift DB
/// and own transport view) sharing one fake relay, mirroring two real apps.
/// Roomless (Phase B): groups/members live in each device's DB and replicate via
/// to-device payloads; each user's LedgerSyncer consumes the inbound stream.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

void main() {
  /// Builds a user's app instance backed by an in-memory DB and a fake transport
  /// bound to [userId] on the shared [net], with its LedgerSyncer running so
  /// inbound payloads land in Drift.
  ProviderContainer makeUser(FakeMatrixNetwork net, String userId) {
    final db = openTestDatabase();
    net.clientFor(userId); // pre-register so deliveries have a target
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
    ]);
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {}); // keep the syncer alive
    return container;
  }

  Future<String> createGroupAs(
      ProviderContainer user, String name, String currency) async {
    await user.read(groupCreatorProvider.notifier).create(name, currency);
    expect(user.read(groupCreatorProvider).hasError, isFalse);
    final groups = await user.read(groupsDaoProvider).watchAllGroups().first;
    return groups.first.roomId;
  }

  test('adding a member relays the whole group (bootstrap) to them', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await net.settle(); // let both syncers subscribe

    final groupId = await createGroupAs(alice, 'Trip', 'CHF');
    await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
    expect(alice.read(memberAdderProvider).hasError, isFalse);
    await net.settle();

    // The group is now visible (and correctly typed) for Bob.
    final bobGroups = await bob.read(groupsDaoProvider).watchAllGroups().first;
    expect(bobGroups, hasLength(1));
    expect(bobGroups.first.roomId, groupId);
    expect(bobGroups.first.currency, 'CHF');
    // ...with both members.
    final bobMembers = await bob.read(membersDaoProvider).getMembers(groupId);
    expect(bobMembers.map((m) => m.userId),
        containsAll(['@alice:x.org', '@bob:y.org']));
  });

  test('a new member receives expenses that predate their join (bootstrap)',
      () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await net.settle();

    final groupId = await createGroupAs(alice, 'Trip', 'EUR');

    // Alice records an expense BEFORE bob is added — bob will only get it via
    // the bootstrap payload, not a live relay.
    await alice.read(expenseAdderProvider.notifier).addExpense(
      roomId: groupId,
      description: 'Pre-join dinner',
      amountCents: 4000,
      currency: 'EUR',
      paidBy: '@alice:x.org',
      splits: {'@alice:x.org': 2000, '@bob:y.org': 2000},
    );
    await net.settle();

    await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
    await net.settle();

    final bobExpenses =
        await bob.read(expensesDaoProvider).watchExpensesForRoom(groupId).first;
    expect(bobExpenses, hasLength(1));
    expect(bobExpenses.first.description, 'Pre-join dinner');
  });

  test('expense added after a member joins live-relays to them', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await net.settle();

    final groupId = await createGroupAs(alice, 'Trip', 'EUR');
    await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
    await net.settle();

    await alice.read(expenseAdderProvider.notifier).addExpense(
      roomId: groupId,
      description: 'Pizza',
      amountCents: 2000,
      currency: 'EUR',
      paidBy: '@alice:x.org',
      splits: {'@alice:x.org': 1000, '@bob:y.org': 1000},
    );
    await net.settle();

    final bobExpenses =
        await bob.read(expensesDaoProvider).watchExpensesForRoom(groupId).first;
    expect(bobExpenses, hasLength(1));
    expect(bobExpenses.first.description, 'Pizza');
    expect(bobExpenses.first.amountCents, 2000);

    // And it flows the other way too: Bob adds an expense, Alice receives it.
    await bob.read(expenseAdderProvider.notifier).addExpense(
      roomId: groupId,
      description: 'Drinks',
      amountCents: 1000,
      currency: 'EUR',
      paidBy: '@bob:y.org',
      splits: {'@alice:x.org': 500, '@bob:y.org': 500},
    );
    await net.settle();

    final aliceExpenses = await alice
        .read(expensesDaoProvider)
        .watchExpensesForRoom(groupId)
        .first;
    expect(aliceExpenses.map((e) => e.description),
        containsAll(['Pizza', 'Drinks']));
  });

  test('removing a member replicates the removal to the other device',
      () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await net.settle();

    final groupId = await createGroupAs(alice, 'Trip', 'EUR');
    await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
    await net.settle();

    await alice.read(memberRemoverProvider.notifier).remove(groupId, '@bob:y.org');
    expect(alice.read(memberRemoverProvider).hasError, isFalse);
    await net.settle();

    // Bob's own device reflects that he was removed.
    final bobMembers = await bob.read(membersDaoProvider).getMembers(groupId);
    final bobSelf = bobMembers.firstWhere((m) => m.userId == '@bob:y.org');
    expect(bobSelf.status, 'removed');
  });
}
