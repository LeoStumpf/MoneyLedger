/// G67 (U13): undo of a delete / a just-recorded payment / a new expense —
/// a new version with the earlier content (next LWW clock, the creator's
/// origin kept, signed by the undoing device — `pendingSign` without a
/// key), relayed so the other members adopt it; nothing is written when
/// someone else changed the record meanwhile.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/record_signing.dart' show RecordKind;
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/expenses/record_undo.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

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

  Future<(ProviderContainer, ProviderContainer, String)> sharedGroup(
    FakeMatrixNetwork net,
  ) async {
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    await net.settle();
    final groupId = (await a
        .read(groupCreatorProvider.notifier)
        .create('Trip', 'EUR'))!;
    await a.read(memberAdderProvider.notifier).add(groupId, bob);
    await net.settle();
    return (a, b, groupId);
  }

  Future<UndoableWrite> addDinner(ProviderContainer c, String groupId) async =>
      (await c
          .read(expenseAdderProvider.notifier)
          .addExpense(
            roomId: groupId,
            description: 'Dinner',
            amountCents: 4200,
            currency: 'EUR',
            paidBy: alice,
            splits: {alice: 2100, bob: 2100},
            note: 'Tip incl.',
          ))!;

  test('undo of a delete restores the expense for everyone', () async {
    final net = FakeMatrixNetwork();
    final (a, b, groupId) = await sharedGroup(net);
    final id = (await addDinner(a, groupId)).recordId;
    await net.settle();
    final created = (await a.read(expensesDaoProvider).getExpenseById(id))!;

    // Bob deletes it, then undoes the delete.
    final delete = await b
        .read(expenseAdderProvider.notifier)
        .deleteExpense(id, groupId);
    expect(delete, isNotNull);
    expect(delete!.beforeExpense!.deleted, isFalse);
    await net.settle();
    expect(
      (await a.read(expensesDaoProvider).getExpenseById(id))!.deleted,
      isTrue,
    );
    net.sent.clear();

    final outcome = await b.read(recordUndoerProvider).undo(delete);
    expect(outcome, UndoOutcome.undone);
    // Relayed live like an edit.
    expect(
      net.sent.where((m) => m.type == expenseEventType && m.sender == bob),
      isNotEmpty,
    );
    await net.settle();

    for (final c in [a, b]) {
      final row = (await c.read(expensesDaoProvider).getExpenseById(id))!;
      expect(row.deleted, isFalse);
      expect(row.description, 'Dinner');
      expect(row.amountCents, 4200);
      expect(row.note, 'Tip incl.');
      expect(row.createdAt, created.createdAt);
      expect(row.updatedAt, greaterThan(delete.writtenExpense!.updatedAt));
      // The creator's origin is kept; the undo is signed by Bob's device.
      expect(row.origin!.user, alice);
      expect(row.origin!.sig, created.origin!.sig);
      expect(row.sig!.user, bob);
      expect(row.pendingSign, isFalse);
    }

    // G48: the undo is in the history as a revert (a reset can go back).
    final history = await HistoryDao(
      b.read(appDatabaseProvider),
    ).entriesForGroup(groupId);
    final versions = history
        .where((e) => e.kind == RecordKind.expense && e.recordId == id)
        .toList();
    expect(versions.last.source, HistorySource.revert);
  });

  test('undo of a recorded payment deletes it again everywhere', () async {
    final net = FakeMatrixNetwork();
    final (a, b, groupId) = await sharedGroup(net);
    final write = (await a
        .read(expenseAdderProvider.notifier)
        .addSettlement(
          roomId: groupId,
          amountCents: 1500,
          currency: 'EUR',
          fromUser: bob,
          toUser: alice,
        ))!;
    expect(write.beforeSettlement, isNull);
    await net.settle();
    expect(
      await b.read(expensesDaoProvider).getSettlementById(write.recordId),
      isNotNull,
    );

    expect(await a.read(recordUndoerProvider).undo(write), UndoOutcome.undone);
    await net.settle();
    for (final c in [a, b]) {
      final row = (await c
          .read(expensesDaoProvider)
          .getSettlementById(write.recordId))!;
      expect(row.deleted, isTrue);
      expect(row.amountCents, 1500);
      expect(row.sig!.user, alice);
    }
    // A second undo of the same write does nothing.
    expect(
      await a.read(recordUndoerProvider).undo(write),
      UndoOutcome.changedMeanwhile,
    );
  });

  test('undo of a payment delete restores it (peer adopts)', () async {
    final net = FakeMatrixNetwork();
    final (a, b, groupId) = await sharedGroup(net);
    final id =
        (await a
                .read(expenseAdderProvider.notifier)
                .addSettlement(
                  roomId: groupId,
                  amountCents: 990,
                  currency: 'EUR',
                  fromUser: bob,
                  toUser: alice,
                ))!
            .recordId;
    await net.settle();
    final delete = (await a
        .read(expenseAdderProvider.notifier)
        .deleteSettlement(id, groupId))!;
    await net.settle();
    expect(
      (await b.read(expensesDaoProvider).getSettlementById(id))!.deleted,
      isTrue,
    );

    expect(await a.read(recordUndoerProvider).undo(delete), UndoOutcome.undone);
    await net.settle();
    final row = (await b.read(expensesDaoProvider).getSettlementById(id))!;
    expect(row.deleted, isFalse);
    expect(row.amountCents, 990);
    expect(row.origin!.user, alice);
  });

  test('a concurrent remote edit wins: undo writes nothing', () async {
    final net = FakeMatrixNetwork();
    final (a, b, groupId) = await sharedGroup(net);
    final id = (await addDinner(a, groupId)).recordId;
    await net.settle();
    final delete = (await a
        .read(expenseAdderProvider.notifier)
        .deleteExpense(id, groupId))!;
    await net.settle();

    // Meanwhile Bob writes a newer version (other content, live again).
    final current = (await b.read(expensesDaoProvider).getExpenseById(id))!;
    await b
        .read(expenseAdderProvider.notifier)
        .updateExpense(
          id: id,
          roomId: groupId,
          description: 'Dinner (fixed)',
          amountCents: 5000,
          currency: 'EUR',
          paidBy: alice,
          splits: {alice: 2500, bob: 2500},
          createdAt: current.createdAt,
        );
    await net.settle();
    net.sent.clear();

    expect(
      await a.read(recordUndoerProvider).undo(delete),
      UndoOutcome.changedMeanwhile,
    );
    await net.settle();
    expect(net.sent, isEmpty);
    for (final c in [a, b]) {
      final row = (await c.read(expensesDaoProvider).getExpenseById(id))!;
      expect(row.description, 'Dinner (fixed)');
      expect(row.amountCents, 5000);
      expect(row.sig!.user, bob);
    }
  });

  test(
    'without a device key the undo is stored pendingSign, not sent',
    () async {
      final net = FakeMatrixNetwork();
      final (a, _, groupId) = await sharedGroup(net);
      final id = (await addDinner(a, groupId)).recordId;
      await net.settle();
      final delete = (await a
          .read(expenseAdderProvider.notifier)
          .deleteExpense(id, groupId))!;
      await net.settle();
      net.clientFor(alice).crypto.ready = false;
      net.sent.clear();

      expect(
        await a.read(recordUndoerProvider).undo(delete),
        UndoOutcome.undone,
      );
      final row = (await a.read(expensesDaoProvider).getExpenseById(id))!;
      expect(row.deleted, isFalse);
      expect(row.pendingSign, isTrue);
      expect(row.origin!.user, alice); // the creator's origin stays
      expect(net.sent.where((m) => m.type == expenseEventType), isEmpty);
    },
  );
}
