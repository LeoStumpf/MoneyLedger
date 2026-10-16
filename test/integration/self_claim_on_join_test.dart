/// Self-claim on join (virtual users, M6): a sharer invites a Matrix account
/// without assigning them a slot; the invitee receives the whole group and then
/// links themselves to an existing local participant (or joins as new) — no
/// duplicate participant, history preserved.
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

  test('an invited user self-claims an existing local participant', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await net.settle();

    final groupId = await createGroupAs(alice, 'Trip', 'EUR');
    await alice.read(memberAdderProvider.notifier).addLocal(groupId, 'Bobby');
    await net.settle();

    // Alice invites Bob's account — shares the group, assigns no slot.
    await alice
        .read(memberAdderProvider.notifier)
        .invite(groupId, '@bob:y.org');
    expect(alice.read(memberAdderProvider).hasError, isFalse);
    await net.settle();

    // Bob received the group but is nobody yet.
    expect(
      await bob
          .read(membersDaoProvider)
          .memberByMatrixId(groupId, '@bob:y.org'),
      isNull,
    );
    final bobby = (await bob.read(membersDaoProvider).getMembers(groupId))
        .firstWhere((m) => m.displayName == 'Bobby');
    expect(bobby.matrixId, isNull);

    // Bob recognises himself as "Bobby" and self-claims.
    await bob
        .read(memberAdderProvider.notifier)
        .selfClaim(groupId, bobby.userId);
    expect(bob.read(memberAdderProvider).hasError, isFalse);
    await net.settle();

    // Bob is now that participant (same ledger identity)...
    final bobSelf = await bob
        .read(membersDaoProvider)
        .memberByMatrixId(groupId, '@bob:y.org');
    expect(bobSelf?.userId, bobby.userId);
    expect(bobSelf?.displayName, 'Bobby');

    // ...and Alice sees the claim with no duplicate participant.
    final aliceBobby = await alice
        .read(membersDaoProvider)
        .memberByMatrixId(groupId, '@bob:y.org');
    expect(aliceBobby?.userId, bobby.userId);
    expect(aliceBobby?.displayName, 'Bobby');
    final aliceMembers = await alice
        .read(membersDaoProvider)
        .getMembers(groupId);
    expect(aliceMembers, hasLength(2)); // alice + bobby, no dupe
  });

  test('an invited user can join as a brand-new participant', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await net.settle();

    final groupId = await createGroupAs(alice, 'Trip', 'EUR');
    await alice
        .read(memberAdderProvider.notifier)
        .invite(groupId, '@bob:y.org');
    await net.settle();

    await bob.read(memberAdderProvider.notifier).joinAsNew(groupId, 'Bob');
    expect(bob.read(memberAdderProvider).hasError, isFalse);
    await net.settle();

    final bobSelf = await bob
        .read(membersDaoProvider)
        .memberByMatrixId(groupId, '@bob:y.org');
    expect(bobSelf?.displayName, 'Bob');
    // Alice learns about the new participant.
    final aliceBob = await alice
        .read(membersDaoProvider)
        .memberByMatrixId(groupId, '@bob:y.org');
    expect(aliceBob?.displayName, 'Bob');
  });
}
