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

  test('G47: a custom category added by one member reaches the others; '
      'rename / hide follow; an expense using it is labelled; a group edit '
      'keeps them; a later member gets them via the bootstrap', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    await net.settle();
    final groupId = (await alice
        .read(groupCreatorProvider.notifier)
        .create('Trip', 'EUR'))!;
    await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
    await net.settle();

    final editor = alice.read(groupEditorProvider.notifier);
    alice.listen(groupEditorProvider, (_, _) {});
    final id = await editor.addCategory(groupId, name: 'Dog', icon: 'pets');
    expect(id, startsWith('c:'));
    await net.settle();

    var bobGroup = (await bob.read(groupsDaoProvider).getGroup(groupId))!;
    expect(bobGroup.categories.single.id, id);
    expect(bobGroup.categories.single.name, 'Dog');
    expect(bobGroup.categories.single.icon, 'pets');
    expect(bobGroup.sig!.user, '@alice:x.org'); // signed + verified

    // Bob uses it, then renames it; Alice sees both.
    await bob
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: groupId,
          description: 'Vet',
          amountCents: 4000,
          currency: 'EUR',
          paidBy: '@bob:y.org',
          splits: {'@alice:x.org': 2000, '@bob:y.org': 2000},
          category: id,
        );
    bob.listen(groupEditorProvider, (_, _) {});
    await bob
        .read(groupEditorProvider.notifier)
        .updateCategory(
          groupId,
          bobGroup.categories.single.copyWith(name: 'Dog & cat', hidden: true),
        );
    await net.settle();
    final aliceGroup = (await alice.read(groupsDaoProvider).getGroup(groupId))!;
    expect(aliceGroup.categories.single.name, 'Dog & cat');
    expect(aliceGroup.categories.single.hidden, isTrue);
    expect(aliceGroup.visibleCategories, isEmpty);
    final vet =
        (await alice.read(expensesDaoProvider).getExpensesForRoom(groupId))
            .single;
    expect(vet.category, id);

    // Renaming the group keeps the categories.
    await editor.edit(groupId, name: 'Ski trip', currency: 'CHF');
    await net.settle();
    bobGroup = (await bob.read(groupsDaoProvider).getGroup(groupId))!;
    expect(bobGroup.name, 'Ski trip');
    expect(bobGroup.categories.single.id, id);

    // Carol joins later: the bootstrap's signed meta carries them.
    final carol = makeUser(net, '@carol:z.org');
    await net.settle();
    await alice.read(memberAdderProvider.notifier).add(groupId, '@carol:z.org');
    await net.settle();
    final carolGroup = (await carol.read(groupsDaoProvider).getGroup(groupId))!;
    expect(carolGroup.categories.single.name, 'Dog & cat');
  });
}
