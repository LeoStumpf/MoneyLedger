/// Multi-user edit/delete convergence tests over the in-memory relay (Phase C).
/// Same setup as multi_user_group_visibility_test.dart: each user is a separate
/// ProviderContainer (own Drift DB + transport view) on one FakeMatrixNetwork.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_model.dart';

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

  /// Group with alice + bob and one expense; returns (groupId, expense).
  Future<(String, ExpenseModel)> seedSharedExpense(
      ProviderContainer alice, ProviderContainer bob, FakeMatrixNetwork net) async {
    await net.settle();
    await alice.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await alice.read(groupsDaoProvider).watchAllGroups().first).first.roomId;
    await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
    await net.settle();

    await alice.read(expenseAdderProvider.notifier).addExpense(
      roomId: groupId,
      description: 'Dinner',
      amountCents: 4000,
      currency: 'EUR',
      paidBy: '@alice:x.org',
      splits: {'@alice:x.org': 2000, '@bob:y.org': 2000},
    );
    await net.settle();
    final expense =
        (await alice.read(expensesDaoProvider).getExpensesForRoom(groupId)).single;
    return (groupId, expense);
  }

  test('an edit replicates to the other device', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    final (groupId, expense) = await seedSharedExpense(alice, bob, net);

    await alice.read(expenseAdderProvider.notifier).updateExpense(
      id: expense.id,
      roomId: groupId,
      description: 'Dinner (corrected)',
      amountCents: 4500,
      currency: 'EUR',
      paidBy: '@alice:x.org',
      splits: {'@alice:x.org': 2250, '@bob:y.org': 2250},
      createdAt: expense.createdAt,
    );
    await net.settle();

    final bobRows =
        await bob.read(expensesDaoProvider).getExpensesForRoom(groupId);
    expect(bobRows, hasLength(1));
    expect(bobRows.single.id, expense.id);
    expect(bobRows.single.description, 'Dinner (corrected)');
    expect(bobRows.single.amountCents, 4500);
  });

  test('concurrent edits converge to the same (latest) winner on both devices',
      () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    final (groupId, expense) = await seedSharedExpense(alice, bob, net);

    Future<void> editAs(ProviderContainer user, String description) =>
        user.read(expenseAdderProvider.notifier).updateExpense(
          id: expense.id,
          roomId: groupId,
          description: description,
          amountCents: 4000,
          currency: 'EUR',
          paidBy: '@alice:x.org',
          splits: {'@alice:x.org': 2000, '@bob:y.org': 2000},
          createdAt: expense.createdAt,
        );

    // Both edit "at the same time" (before either sees the other's edit).
    // A short real-clock gap keeps the LWW timestamps distinct so the winner
    // is deterministic: bob's later edit must win on BOTH devices.
    await editAs(alice, 'alice version');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await editAs(bob, 'bob version');
    await net.settle();

    final aliceRow = (await alice
            .read(expensesDaoProvider)
            .getExpensesForRoom(groupId))
        .single;
    final bobRow =
        (await bob.read(expensesDaoProvider).getExpensesForRoom(groupId)).single;
    expect(aliceRow.description, 'bob version');
    expect(bobRow.description, 'bob version');
    expect(aliceRow.updatedAt, bobRow.updatedAt);
  });

  test('a delete on one device removes the expense from the other', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    final (groupId, expense) = await seedSharedExpense(alice, bob, net);

    await alice.read(expenseAdderProvider.notifier).deleteExpense(
        expense.id, groupId);
    await net.settle();

    final bobDao = bob.read(expensesDaoProvider);
    expect(await bobDao.getExpensesForRoom(groupId), isEmpty);
    // Bob keeps the tombstone so anti-entropy can't resurrect the record.
    final all = await bobDao.getAllExpensesForGroup(groupId);
    expect(all.single.deleted, true);
  });

  test('a new member bootstrapped after a delete never sees the expense',
      () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    final bob = makeUser(net, '@bob:y.org');
    final (groupId, expense) = await seedSharedExpense(alice, bob, net);

    await alice
        .read(expenseAdderProvider.notifier)
        .deleteExpense(expense.id, groupId);
    await net.settle();

    // Carol joins after the deletion — her bootstrap must carry the tombstone.
    final carol = makeUser(net, '@carol:z.org');
    await net.settle();
    await alice.read(memberAdderProvider.notifier).add(groupId, '@carol:z.org');
    await net.settle();

    final carolDao = carol.read(expensesDaoProvider);
    expect(await carolDao.getExpensesForRoom(groupId), isEmpty);
    final all = await carolDao.getAllExpensesForGroup(groupId);
    expect(all.single.deleted, true);
  });
}
