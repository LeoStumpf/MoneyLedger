/// G76 end to end: an expense several people paid reaches the other members
/// through the signed live relay (payers verified as part of the content),
/// both sides compute the same balances, a peer's edit back to one payer
/// replicates, and a later member gets the payers via the bootstrap.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_payers.dart';

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
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    return container;
  }

  test(
    'several payers replicate on add and edit; bootstrap carries them',
    () async {
      const a = '@alice:x.org';
      const b = '@bob:y.org';
      final net = FakeMatrixNetwork();
      final alice = makeUser(net, a);
      final bob = makeUser(net, b);
      await net.settle();
      final groupId = (await alice
          .read(groupCreatorProvider.notifier)
          .create('Trip', 'EUR'))!;
      await alice.read(memberAdderProvider.notifier).add(groupId, b);
      await net.settle();

      final written = await alice
          .read(expenseAdderProvider.notifier)
          .addExpense(
            roomId: groupId,
            description: 'Dinner',
            amountCents: 9000,
            currency: 'EUR',
            paidBy: '',
            payers: {a: 6000, b: 3000},
            splits: {a: 4500, b: 4500},
          );
      expect(written, isNotNull);
      await net.settle();

      var row =
          (await bob.read(expensesDaoProvider).getExpensesForRoom(groupId))
              .single;
      expect(row.paidBy, '');
      expect(paidAmountsOf(row), {a: 6000, b: 3000});
      expect(row.sig, isNotNull); // verified + stored as signed
      final aliceRows = await alice
          .read(expensesDaoProvider)
          .getExpensesForRoom(groupId);
      expect(netBalances([row], const []), netBalances(aliceRows, const []));
      expect(netBalances([row], const [])['EUR'], {a: 1500, b: -1500});

      // Bob edits it to "Alice paid it all": the single-payer shape again.
      await bob
          .read(expenseAdderProvider.notifier)
          .updateExpense(
            id: row.id,
            roomId: groupId,
            description: 'Dinner',
            amountCents: 9000,
            currency: 'EUR',
            paidBy: a,
            splits: {a: 4500, b: 4500},
            createdAt: row.createdAt,
          );
      await net.settle();
      row = (await alice.read(expensesDaoProvider).getExpensesForRoom(groupId))
          .single;
      expect(row.paidBy, a);
      expect(row.payersJson, isNull);
      expect(row.sig!.user, b);

      // … and back to two payers; Carol joins later and gets it by bootstrap.
      await alice
          .read(expenseAdderProvider.notifier)
          .updateExpense(
            id: row.id,
            roomId: groupId,
            description: 'Dinner',
            amountCents: 9000,
            currency: 'EUR',
            paidBy: a,
            payers: {a: 1000, b: 8000},
            splits: {a: 4500, b: 4500},
            createdAt: row.createdAt,
          );
      await net.settle();
      final carol = makeUser(net, '@carol:z.org');
      await net.settle();
      await alice
          .read(memberAdderProvider.notifier)
          .add(groupId, '@carol:z.org');
      await net.settle();
      final carolRow = await carol
          .read(expensesDaoProvider)
          .getExpenseById(row.id);
      expect(paidAmountsOf(carolRow!), {a: 1000, b: 8000});
      expect(carolRow.origin!.user, a);
    },
  );

  test('payers that do not add up are refused by the writer', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    await net.settle();
    final groupId = (await alice
        .read(groupCreatorProvider.notifier)
        .create('Solo', 'EUR'))!;
    final adder = alice.read(expenseAdderProvider.notifier);
    final written = await adder.addExpense(
      roomId: groupId,
      description: 'Coffee',
      amountCents: 400,
      currency: 'EUR',
      paidBy: '',
      payers: {'@alice:x.org': 300, 'p2': 50},
      splits: {'@alice:x.org': 400},
    );
    expect(written, isNull);
    expect(alice.read(expenseAdderProvider).error, isA<ArgumentError>());
    expect(
      await alice.read(expensesDaoProvider).getExpensesForRoom(groupId),
      isEmpty,
    );
    // One payer with the whole amount is stored as the plain shape.
    await adder.addExpense(
      roomId: groupId,
      description: 'Tea',
      amountCents: 400,
      currency: 'EUR',
      paidBy: '',
      payers: {'@alice:x.org': 400, 'p2': 0},
      splits: {'@alice:x.org': 400},
    );
    final row =
        (await alice.read(expensesDaoProvider).getExpensesForRoom(groupId))
            .single;
    expect(row.paidBy, '@alice:x.org');
    expect(row.payersJson, isNull);
  });
}
