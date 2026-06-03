/// Multi-user, cross-homeserver integration tests driven entirely by the
/// in-memory [FakeMatrixNetwork] — no real homeserver, no network, no auth.
///
/// Each user is a separate [ProviderContainer] (its own "device": own Drift DB
/// and own transport view) sharing one fake network, mirroring two real apps.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

void main() {
  /// Builds a user's app instance backed by an in-memory DB and a fake
  /// transport bound to [userId] on the shared [net].
  ProviderContainer makeUser(FakeMatrixNetwork net, String userId) {
    final db = openTestDatabase();
    // Pre-register so invites/events delivered to this user have a target.
    net.clientFor(userId);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
    ]);
    addTearDown(() {
      container.dispose();
      db.close();
    });
    return container;
  }

  Future<String> createGroupAs(
      ProviderContainer user, String name, String currency) async {
    await user.read(groupCreatorProvider.notifier).create(name, currency);
    expect(user.read(groupCreatorProvider).hasError, isFalse);
    final groups = await user.read(groupsDaoProvider).watchAllGroups().first;
    return groups.first.roomId;
  }

  test('federated invite → accept makes the group visible to the second user',
      () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await bob.read(ledgerTransportProvider.future); // ensure bob is live

    final roomId = await createGroupAs(alice, 'Trip', 'CHF');

    await alice.read(userInviterProvider.notifier).invite(roomId, '@bob:y.org');
    await net.settle();

    // Bob sees the pending invite. (listen keeps the autoDispose provider alive.)
    bob.listen(pendingInvitesProvider, (_, _) {});
    final invites = await bob.read(pendingInvitesProvider.future);
    expect(invites.map((r) => r.id), contains(roomId));

    // Bob accepts — this is the path that previously failed silently.
    await bob.read(inviteAcceptorProvider.notifier).accept(roomId);
    expect(bob.read(inviteAcceptorProvider).hasError, isFalse);
    await net.settle();

    // The group is now visible (and correctly typed) for Bob.
    final bobGroups = await bob.read(groupsDaoProvider).watchAllGroups().first;
    expect(bobGroups, hasLength(1));
    expect(bobGroups.first.roomId, roomId);
    expect(bobGroups.first.currency, 'CHF');
  });

  test('joining a remote room with no invite fails (federation guard)',
      () async {
    final net = FakeMatrixNetwork();
    final alice = net.clientFor('@alice:x.org');
    final carol = net.clientFor('@carol:z.org');
    final roomId = await alice.createGroup('Trip', 'EUR'); // hosted on x.org

    // Carol is on a different server and was never invited → no resolvable
    // resident server. This is the failure the via-less joinRoomById produced.
    await expectLater(
      carol.join(roomId),
      throwsA(isA<TransportJoinException>()),
    );
  });

  test('a second user sees expenses that predate their join', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await bob.read(ledgerTransportProvider.future);

    final roomId = await createGroupAs(alice, 'Trip', 'EUR');

    // Alice records an expense BEFORE bob is invited — it's not in any live
    // sync delta bob will receive, only in history.
    await alice.read(expenseAdderProvider.notifier).addExpense(
      roomId: roomId,
      description: 'Pre-join dinner',
      amountCents: 4000,
      currency: 'EUR',
      paidBy: '@alice:x.org',
      splits: {'@alice:x.org': 2000, '@bob:y.org': 2000},
    );

    // Bob's syncer is already running when he joins (he's mid-session).
    bob.listen(ledgerSyncerProvider, (_, _) {});
    await net.settle();

    await alice.read(userInviterProvider.notifier).invite(roomId, '@bob:y.org');
    await net.settle();
    await bob.read(inviteAcceptorProvider.notifier).accept(roomId);
    await net.settle();

    // The history-backfill reconcile must have pulled the pre-join expense in.
    final bobExpenses =
        await bob.read(expensesDaoProvider).watchExpensesForRoom(roomId).first;
    expect(bobExpenses, hasLength(1));
    expect(bobExpenses.first.description, 'Pre-join dinner');
  });

  test('expense added by the first user appears for the second after joining',
      () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await bob.read(ledgerTransportProvider.future);

    final roomId = await createGroupAs(alice, 'Trip', 'EUR');
    await alice.read(userInviterProvider.notifier).invite(roomId, '@bob:y.org');
    await net.settle();
    await bob.read(inviteAcceptorProvider.notifier).accept(roomId);
    await net.settle();

    // Bob keeps the syncer alive so live events land in his Drift.
    // (listen, not read — ledgerSyncerProvider is autoDispose.)
    bob.listen(ledgerSyncerProvider, (_, _) {});
    await net.settle();

    await alice.read(expenseAdderProvider.notifier).addExpense(
      roomId: roomId,
      description: 'Pizza',
      amountCents: 2000,
      currency: 'EUR',
      paidBy: '@alice:x.org',
      splits: {'@alice:x.org': 1000, '@bob:y.org': 1000},
    );
    await net.settle();

    final bobExpenses =
        await bob.read(expensesDaoProvider).watchExpensesForRoom(roomId).first;
    expect(bobExpenses, hasLength(1));
    expect(bobExpenses.first.description, 'Pizza');
    expect(bobExpenses.first.amountCents, 2000);
  });
}
