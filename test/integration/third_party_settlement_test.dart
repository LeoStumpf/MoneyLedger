/// G28: any active member may record a payment between any two participants —
/// a settlement recorded by a **third** member (and one for a local person)
/// replicates to everyone and all balances converge.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';
const carol = '@carol:z.org';

void main() {
  ProviderContainer makeUser(FakeMatrixNetwork net, String userId) {
    final db = openTestDatabase();
    net.clientFor(userId);
    final c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
      pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
      syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ]);
    addTearDown(() {
      c.dispose();
      db.close();
    });
    c.listen(ledgerSyncerProvider, (_, _) {});
    c.listen(syncEngineProvider, (_, _) {});
    return c;
  }

  Future<List<DebtEntry>> debtsOf(ProviderContainer c, String groupId) async {
    final dao = c.read(expensesDaoProvider);
    return calculateDebts(await dao.getExpensesForRoom(groupId),
        await dao.getSettlementsForRoom(groupId));
  }

  test('a settlement recorded by a third member replicates; balances converge',
      () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final c = makeUser(net, carol);
    await net.settle();

    await a.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await a.read(groupsDaoProvider).getAllGroups()).single.roomId;
    await a.read(memberAdderProvider.notifier).add(groupId, bob);
    await net.settle();
    await a.read(memberAdderProvider.notifier).add(groupId, carol);
    await net.settle();
    await a.read(memberAdderProvider.notifier).addLocal(groupId, 'Dan');
    await net.settle();
    final dan = (await a.read(membersDaoProvider).getMembers(groupId))
        .singleWhere((m) => m.displayName == 'Dan')
        .userId;

    // Alice pays 40 for four: bob, carol and local Dan each owe her 10.
    await a.read(expenseAdderProvider.notifier).addExpense(
          roomId: groupId,
          description: 'Dinner',
          amountCents: 4000,
          currency: 'EUR',
          paidBy: alice,
          splits: {alice: 1000, bob: 1000, carol: 1000, dan: 1000},
        );
    await net.settle();

    // Carol (a third party) records that bob paid alice, and that local Dan
    // paid alice.
    for (final from in [bob, dan]) {
      await c.read(expenseAdderProvider.notifier).addSettlement(
            roomId: groupId,
            amountCents: 1000,
            currency: 'EUR',
            fromUser: from,
            toUser: alice,
          );
    }
    await net.settle();

    for (final user in [a, b, c]) {
      expect(
          await user.read(expensesDaoProvider).getSettlementsForRoom(groupId),
          hasLength(2));
      final debts = await debtsOf(user, groupId);
      expect(debts, hasLength(1));
      expect((debts.single.from, debts.single.to, debts.single.cents),
          (carol, alice, 1000));
    }
  });
}
