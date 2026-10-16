/// G49 end to end: a back-dated expense reaches the other members through the
/// signed live relay (date verified as part of the content), a peer can
/// re-date it (the creator's origin stays valid), and a later member gets the
/// date via the (verified) bootstrap.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import 'package:money_ledger/models/expense_date.dart';

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
    'the expense date replicates on add and edit; bootstrap carries it',
    () async {
      final net = FakeMatrixNetwork();
      final alice = makeUser(net, '@alice:x.org');
      final bob = makeUser(net, '@bob:y.org');
      await net.settle();
      final groupId = (await alice
          .read(groupCreatorProvider.notifier)
          .create('Trip', 'EUR'))!;
      await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
      await net.settle();

      final now = DateTime.now();
      await alice
          .read(expenseAdderProvider.notifier)
          .addExpense(
            roomId: groupId,
            description: 'Dinner',
            amountCents: 4000,
            currency: 'EUR',
            paidBy: '@alice:x.org',
            splits: {'@alice:x.org': 2000, '@bob:y.org': 2000},
            day: DateTime(now.year, now.month, now.day - 3),
          );
      await net.settle();
      final threeDaysAgo = expenseDateOf(
        DateTime(now.year, now.month, now.day - 3),
      );

      var row =
          (await bob.read(expensesDaoProvider).getExpensesForRoom(groupId))
              .single;
      expect(row.date, threeDaysAgo);
      expect(row.sig, isNotNull); // verified + stored as signed
      expect(row.origin!.user, '@alice:x.org');

      // Bob re-dates it: a new signed version, Alice's origin carried over.
      await bob
          .read(expenseAdderProvider.notifier)
          .updateExpense(
            id: row.id,
            roomId: groupId,
            description: 'Dinner',
            amountCents: 4000,
            currency: 'EUR',
            paidBy: '@alice:x.org',
            splits: {'@alice:x.org': 2000, '@bob:y.org': 2000},
            createdAt: row.createdAt,
            date: '2025-12-24',
          );
      await net.settle();
      row = (await alice.read(expensesDaoProvider).getExpensesForRoom(groupId))
          .single;
      expect(row.date, '2025-12-24');
      expect(row.sig!.user, '@bob:y.org');
      expect(row.origin!.user, '@alice:x.org');

      // Carol joins later: her bootstrap (verified record by record) has it.
      final carol = makeUser(net, '@carol:z.org');
      await net.settle();
      await alice
          .read(memberAdderProvider.notifier)
          .add(groupId, '@carol:z.org');
      await net.settle();
      final carolRow = await carol
          .read(expensesDaoProvider)
          .getExpenseById(row.id);
      expect(carolRow!.date, '2025-12-24');
    },
  );

  test('an expense dated today carries no date at all', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    await net.settle();
    final groupId = (await alice
        .read(groupCreatorProvider.notifier)
        .create('Solo', 'EUR'))!;
    await alice
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: groupId,
          description: 'Coffee',
          amountCents: 400,
          currency: 'EUR',
          paidBy: '@alice:x.org',
          splits: {'@alice:x.org': 400},
          day: DateTime.now(),
        );
    final row =
        (await alice.read(expensesDaoProvider).getExpensesForRoom(groupId))
            .single;
    expect(row.date, isNull);
  });
}
