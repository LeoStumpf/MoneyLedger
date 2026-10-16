/// Joining a group (virtual users, M6; G18 review): the **inviter** decides
/// which participant an invited Matrix account becomes — an existing local
/// person (history kept, no duplicate) or a new participant. The invitee then
/// receives the group as an active member. A non-member can no longer make
/// itself a participant (self-claim / join-as-new / rejoin): peers refuse it.
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
  ProviderContainer makeUser(FakeMatrixNetwork net, String userId) {
    final db = openTestDatabase();
    net.clientFor(userId);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
      ],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    return container;
  }

  Future<String> createGroupAs(
    ProviderContainer user,
    String name,
    String currency,
  ) async {
    await user.read(groupCreatorProvider.notifier).create(name, currency);
    final groups = await user.read(groupsDaoProvider).watchAllGroups().first;
    return groups.first.roomId;
  }

  test(
    'the inviter assigns an existing local participant to the invitee',
    () async {
      final net = FakeMatrixNetwork();
      final alice = makeUser(net, '@alice:x.org');
      final bob = makeUser(net, '@bob:y.org');
      await net.settle();

      final groupId = await createGroupAs(alice, 'Trip', 'EUR');
      await alice.read(memberAdderProvider.notifier).addLocal(groupId, 'Bobby');
      await net.settle();
      final bobby = (await alice.read(membersDaoProvider).getMembers(groupId))
          .firstWhere((m) => m.displayName == 'Bobby');

      // Alice invites Bob's account as "Bobby".
      await alice
          .read(memberAdderProvider.notifier)
          .invite(groupId, '@bob:y.org', participantId: bobby.userId);
      expect(alice.read(memberAdderProvider).hasError, isFalse);
      await net.settle();

      for (final c in [alice, bob]) {
        final self = await c
            .read(membersDaoProvider)
            .memberByMatrixId(groupId, '@bob:y.org');
        expect(self?.userId, bobby.userId);
        expect(self?.displayName, 'Bobby');
        expect(self?.isActive, isTrue);
        expect(
          await c.read(membersDaoProvider).getMembers(groupId),
          hasLength(2), // alice + bobby, no dupe
        );
      }

      // Bob is a full member: his records reach Alice.
      await bob
          .read(expenseAdderProvider.notifier)
          .addExpense(
            roomId: groupId,
            description: 'Taxi',
            amountCents: 1000,
            currency: 'EUR',
            paidBy: bobby.userId,
            splits: {bobby.userId: 500, '@alice:x.org': 500},
          );
      await net.settle();
      expect(
        (await alice.read(expensesDaoProvider).getExpensesForRoom(groupId)).map(
          (e) => e.description,
        ),
        contains('Taxi'),
      );
    },
  );

  test('without a pick the invitee becomes a new participant', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await net.settle();

    final groupId = await createGroupAs(alice, 'Trip', 'EUR');
    await alice
        .read(memberAdderProvider.notifier)
        .invite(groupId, '@bob:y.org');
    await net.settle();

    for (final c in [alice, bob]) {
      final self = await c
          .read(membersDaoProvider)
          .memberByMatrixId(groupId, '@bob:y.org');
      expect(self?.isActive, isTrue);
    }
  });

  // G18 review: the old invitee-driven flow is refused by peers.
  test("a non-member's self-claim / join-as-new is refused by peers", () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await net.settle();

    final groupId = await createGroupAs(alice, 'Trip', 'EUR');
    await alice.read(memberAdderProvider.notifier).addLocal(groupId, 'Bobby');
    await net.settle();
    // Bob somehow holds the group (e.g. an old slot-less invite) …
    await alice
        .read(memberAdderProvider.notifier)
        .claim(
          groupId,
          (await alice.read(membersDaoProvider).getMembers(groupId))
              .firstWhere((m) => m.displayName == 'Bobby')
              .userId,
          '@bob:y.org',
        );
    await net.settle();
    final bobby = await alice
        .read(membersDaoProvider)
        .memberByMatrixId(groupId, '@bob:y.org');
    // … and is removed again.
    await alice
        .read(memberRemoverProvider.notifier)
        .remove(groupId, bobby!.userId);
    await net.settle();

    // Joining as a new participant on his own: Alice refuses.
    await bob.read(memberAdderProvider.notifier).joinAsNew(groupId, 'Bob');
    await net.settle();
    final aliceView = await alice.read(membersDaoProvider).getMembers(groupId);
    expect(
      aliceView.where((m) => m.matrixId == '@bob:y.org' && m.isActive),
      isEmpty,
    );
    expect(aliceView, hasLength(2));
  });
}
