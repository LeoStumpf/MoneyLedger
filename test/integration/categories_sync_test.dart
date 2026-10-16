/// G16 end to end: a category + note added / edited on one device reaches the
/// other through the signed live relay, and a fresh device gets them via the
/// (verified) bootstrap.
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
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    return container;
  }

  test(
    'category + note replicate on add and edit; bootstrap carries them',
    () async {
      final net = FakeMatrixNetwork();
      final alice = makeUser(net, '@alice:x.org');
      final bob = makeUser(net, '@bob:y.org');
      await net.settle();
      await alice.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
      final groupId =
          (await alice.read(groupsDaoProvider).watchAllGroups().first)
              .first
              .roomId;
      await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
      await net.settle();

      await alice
          .read(expenseAdderProvider.notifier)
          .addExpense(
            roomId: groupId,
            description: 'Dinner',
            amountCents: 4000,
            currency: 'EUR',
            paidBy: '@alice:x.org',
            splits: {'@alice:x.org': 2000, '@bob:y.org': 2000},
            category: 'food',
            note: 'Tip included',
          );
      await net.settle();

      var row =
          (await bob.read(expensesDaoProvider).getExpensesForRoom(groupId))
              .single;
      expect(row.category, 'food');
      expect(row.note, 'Tip included');
      expect(row.sig, isNotNull); // verified + stored as signed

      // Bob edits: new category, note removed.
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
            category: 'entertainment',
            note: '  ',
          );
      await net.settle();
      row = (await alice.read(expensesDaoProvider).getExpensesForRoom(groupId))
          .single;
      expect(row.category, 'entertainment');
      expect(row.note, isNull);

      // A delete keeps the content (the tombstone is a signed version too).
      await alice
          .read(expenseAdderProvider.notifier)
          .deleteExpense(row.id, groupId);
      await net.settle();
      final tomb = await bob.read(expensesDaoProvider).getExpenseById(row.id);
      expect(tomb!.deleted, isTrue);
      expect(tomb.category, 'entertainment');

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
      expect(carolRow, isNotNull);
      expect(carolRow!.category, 'entertainment');
      expect(carolRow.deleted, isTrue);
    },
  );
}
