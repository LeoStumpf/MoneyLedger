/// G8: deleting a settlement (from the expenses list) tombstones it, replicates
/// the tombstone to the other member, and restores the balance on both sides.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_provider.dart';
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

  /// Polls the (stream-derived) balance provider until [done] holds.
  Future<List<DebtEntry>> balanceWhen(ProviderContainer c, String groupId,
      bool Function(List<DebtEntry>) done) async {
    final sub = c.listen(balanceForRoomProvider(groupId), (_, _) {});
    try {
      for (var i = 0; i < 200; i++) {
        final debts = c.read(balanceForRoomProvider(groupId));
        if (done(debts)) return debts;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return c.read(balanceForRoomProvider(groupId));
    } finally {
      sub.close();
    }
  }

  test('a settlement delete on A replicates to B and restores the balance',
      () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await net.settle();

    await alice.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await alice.read(groupsDaoProvider).watchAllGroups().first).first.roomId;
    await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
    await net.settle();

    // Alice pays 40 EUR split evenly → Bob owes Alice 20 EUR.
    await alice.read(expenseAdderProvider.notifier).addExpense(
      roomId: groupId,
      description: 'Dinner',
      amountCents: 4000,
      currency: 'EUR',
      paidBy: '@alice:x.org',
      splits: {'@alice:x.org': 2000, '@bob:y.org': 2000},
    );
    // Bob settles up (wrongly, say) — the debt disappears on both devices.
    await net.settle();
    await bob.read(expenseAdderProvider.notifier).addSettlement(
          roomId: groupId,
          amountCents: 2000,
          currency: 'EUR',
          fromUser: '@bob:y.org',
          toUser: '@alice:x.org',
        );
    await net.settle();
    expect(await balanceWhen(alice, groupId, (d) => d.isEmpty), isEmpty);
    final settlement =
        (await alice.read(expensesDaoProvider).getSettlementsForRoom(groupId))
            .single;

    // Alice deletes it from her list.
    await alice
        .read(expenseAdderProvider.notifier)
        .deleteSettlement(settlement.id, groupId);
    await net.settle();

    for (final user in [alice, bob]) {
      final dao = user.read(expensesDaoProvider);
      expect(await dao.getSettlementsForRoom(groupId), isEmpty);
      // Kept as a tombstone so anti-entropy can't resurrect it.
      final all = await dao.getAllSettlementsForGroup(groupId);
      expect(all.single.id, settlement.id);
      expect(all.single.deleted, true);

      final debts = await balanceWhen(user, groupId, (d) => d.isNotEmpty);
      expect(debts, hasLength(1));
      expect(debts.single.from, '@bob:y.org');
      expect(debts.single.to, '@alice:x.org');
      expect(debts.single.cents, 2000);
    }
  });
}
