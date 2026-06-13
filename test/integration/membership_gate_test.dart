/// Membership gate (Phase F, M1): a forged record from a non-member is dropped
/// end-to-end by LedgerSyncer, while a real member's record is applied.
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
  ProviderContainer makeUser(FakeMatrixNetwork net, String userId) {
    final db = openTestDatabase();
    net.clientFor(userId);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
    ]);
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    return container;
  }

  Map<String, dynamic> forgedExpense(String groupId) => {
        'v': 1,
        'id': 'forged-1',
        'group': groupId,
        'description': 'Fake',
        'amount': 9999,
        'currency': 'EUR',
        'paid_by': '@alice:x.org',
        'split': {'@alice:x.org': 9999},
        'created_at': 1000,
        'updated_at': 2000,
        'deleted': false,
      };

  test('a forged expense from a non-member is dropped', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    makeUser(net, '@mallory:evil.org');
    await net.settle();

    await alice.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await alice.read(groupsDaoProvider).watchAllGroups().first).first.roomId;
    await net.settle();

    // Mallory, who is not a member, pushes a forged expense straight at Alice.
    await net
        .clientFor('@mallory:evil.org')
        .sendToUsers({'@alice:x.org'}, expenseEventType, forgedExpense(groupId));
    await net.settle();

    final expenses =
        await alice.read(expensesDaoProvider).getExpensesForRoom(groupId);
    expect(expenses, isEmpty); // gate dropped it
  });

  test('an expense from an active member is applied', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await net.settle();

    await alice.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await alice.read(groupsDaoProvider).watchAllGroups().first).first.roomId;
    // Bob is a real, claimed member (invited + self-joins).
    await alice.read(memberAdderProvider.notifier).invite(groupId, '@bob:y.org');
    await net.settle();
    await bob.read(memberAdderProvider.notifier).joinAsNew(groupId, 'Bob');
    await net.settle();

    // Now a record from Bob (a member) is accepted by Alice.
    await bob.read(expenseAdderProvider.notifier).addExpense(
          roomId: groupId,
          description: 'Lunch',
          amountCents: 2000,
          currency: 'EUR',
          paidBy: (await bob
                  .read(membersDaoProvider)
                  .memberByMatrixId(groupId, '@bob:y.org'))!
              .userId,
          splits: const {},
        );
    await net.settle();

    final expenses =
        await alice.read(expensesDaoProvider).getExpensesForRoom(groupId);
    expect(expenses.map((e) => e.description), contains('Lunch'));
  });
}
