/// G73 end to end: fixed exchange rates set by one member reach the others
/// in the signed meta, drive their balances ("settle up in EUR"), survive a
/// group edit, reach a later member via the bootstrap, and removing the
/// last rate clears them everywhere.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/balance/balance_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/exchange_rates.dart';

import '../helpers/eventually.dart';
import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const _alice = '@alice:x.org';
const _bob = '@bob:y.org';

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
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    return container;
  }

  test('rates replicate signed, convert the balances, survive an edit, '
      'bootstrap to a later member, and clear everywhere', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, _alice);
    final bob = makeUser(net, _bob);
    await net.settle();
    final groupId = (await alice
        .read(groupCreatorProvider.notifier)
        .create('Trip', 'EUR'))!;
    await alice.read(memberAdderProvider.notifier).add(groupId, _bob);
    await net.settle();

    // Alice paid €40, Bob paid CHF 100 — both split equally.
    final members = alice.read(membersDaoProvider);
    final me = (await members.memberByMatrixId(groupId, _alice))!;
    final bobP = (await members.memberByMatrixId(groupId, _bob))!;
    final adder = alice.read(expenseAdderProvider.notifier);
    alice.listen(expenseAdderProvider, (_, _) {});
    await adder.addExpense(
      roomId: groupId,
      description: 'Dinner',
      amountCents: 4000,
      currency: 'EUR',
      paidBy: me.userId,
      splits: {me.userId: 2000, bobP.userId: 2000},
    );
    await adder.addExpense(
      roomId: groupId,
      description: 'Hotel',
      amountCents: 10000,
      currency: 'CHF',
      paidBy: bobP.userId,
      splits: {me.userId: 5000, bobP.userId: 5000},
    );
    await net.settle();

    final editor = alice.read(groupEditorProvider.notifier);
    alice.listen(groupEditorProvider, (_, _) {});
    await editor.setExchangeRates(
      groupId,
      ExchangeRates(base: 'EUR', rates: const {'CHF': '1.1'}, settle: true),
    );
    expect(alice.read(groupEditorProvider).hasError, isFalse);
    await net.settle();

    var bobGroup = (await bob.read(groupsDaoProvider).getGroup(groupId))!;
    expect(bobGroup.exchangeRates?.rates, {'CHF': '1.1'});
    expect(bobGroup.exchangeRates?.settle, isTrue);
    expect(bobGroup.sig!.user, _alice); // signed + verified

    // Bob's balance: one EUR debt — Alice owes Bob 55 − 20 = €35.
    bob.listen(balanceForRoomProvider(groupId), (_, _) {});
    await bob.read(ledgerGroupsProvider.future);
    await bob.read(expensesForRoomProvider(groupId).future);
    await bob.read(settlementsForRoomProvider(groupId).future);
    await eventually(
      () => bob.read(balanceForRoomProvider(groupId)).length == 1,
    );
    final debt = bob.read(balanceForRoomProvider(groupId)).single;
    expect(debt.currency, 'EUR');
    expect(debt.cents, 3500);
    expect(debt.from, me.userId);

    // A name edit keeps the rates.
    await editor.edit(groupId, name: 'Trip 2026', currency: 'EUR');
    await net.settle();
    bobGroup = (await bob.read(groupsDaoProvider).getGroup(groupId))!;
    expect(bobGroup.name, 'Trip 2026');
    expect(bobGroup.exchangeRates?.rates, {'CHF': '1.1'});

    // Carol joins later: the bootstrap's (verified) meta carries them.
    final carol = makeUser(net, '@carol:z.org');
    await net.settle();
    await alice.read(memberAdderProvider.notifier).add(groupId, '@carol:z.org');
    await net.settle();
    final carolGroup = (await carol.read(groupsDaoProvider).getGroup(groupId))!;
    expect(carolGroup.exchangeRates?.settle, isTrue);

    // Removing the last rate clears them everywhere.
    await bob
        .read(groupEditorProvider.notifier)
        .setExchangeRates(groupId, null);
    await net.settle();
    for (final c in [alice, bob, carol]) {
      final g = (await c.read(groupsDaoProvider).getGroup(groupId))!;
      expect(g.exchangeRates, isNull);
      expect(g.name, 'Trip 2026');
    }
  });

  test('rates breaking the content rules are refused before writing', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, _alice);
    await net.settle();
    final groupId = (await alice
        .read(groupCreatorProvider.notifier)
        .create('Trip', 'EUR'))!;
    alice.listen(groupEditorProvider, (_, _) {});
    await alice
        .read(groupEditorProvider.notifier)
        .setExchangeRates(
          groupId,
          ExchangeRates(base: 'EUR', rates: const {'EUR': '1'}),
        );
    expect(alice.read(groupEditorProvider).hasError, isTrue);
    final g = (await alice.read(groupsDaoProvider).getGroup(groupId))!;
    expect(g.exchangeRates, isNull);
  });
}
