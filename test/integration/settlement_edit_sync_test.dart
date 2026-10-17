/// G60: editing a payment — a new signed version (next LWW clock, this
/// device as editor, the creator's origin kept) that the other members
/// verify and adopt; the G48 history records both versions; an edit of a
/// payment deleted meanwhile is refused locally.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/record_signing.dart' show RecordKind;
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_date.dart';

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

  Future<(ProviderContainer, ProviderContainer, String, String)> sharedPayment(
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
    await a
        .read(expenseAdderProvider.notifier)
        .addSettlement(
          roomId: groupId,
          amountCents: 1500,
          currency: 'EUR',
          fromUser: bob,
          toUser: alice,
        );
    await net.settle();
    final id =
        (await b.read(expensesDaoProvider).getSettlementsForRoom(groupId))
            .single
            .id;
    return (a, b, groupId, id);
  }

  test("a peer's edit reaches the creator: new version, origin kept", () async {
    final net = FakeMatrixNetwork();
    final (a, b, groupId, id) = await sharedPayment(net);
    final before = (await a.read(expensesDaoProvider).getSettlementById(id))!;

    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day - 3);
    await b
        .read(expenseAdderProvider.notifier)
        .updateSettlement(
          id: id,
          roomId: groupId,
          amountCents: 1250,
          currency: 'CHF',
          fromUser: alice,
          toUser: bob,
          date: storedExpenseDate(day, before.createdAt),
        );
    expect(b.read(expenseAdderProvider).error, isNull);
    await net.settle();

    for (final c in [a, b]) {
      final row = (await c.read(expensesDaoProvider).getSettlementById(id))!;
      expect(row.amountCents, 1250);
      expect(row.currency, 'CHF');
      expect(row.fromUser, alice);
      expect(row.toUser, bob);
      expect(row.date, expenseDateOf(day));
      expect(row.deleted, isFalse);
      expect(row.createdAt, before.createdAt);
      expect(row.updatedAt, greaterThan(before.updatedAt));
      // "Added by Alice · last edited by Bob" (verified on Alice's side).
      expect(row.origin!.user, alice);
      expect(row.origin!.sig, before.origin!.sig);
      expect(row.sig!.user, bob);
    }

    // G48: Alice's history has both versions (an undo can go back).
    final history = await HistoryDao(
      a.read(appDatabaseProvider),
    ).entriesForGroup(groupId);
    final versions = history.where(
      (e) => e.kind == RecordKind.settlement && e.recordId == id,
    );
    expect(versions, hasLength(2));
  });

  test('an edit of a payment deleted meanwhile is not written', () async {
    final net = FakeMatrixNetwork();
    final (a, b, groupId, id) = await sharedPayment(net);
    await a.read(expenseAdderProvider.notifier).deleteSettlement(id, groupId);
    await net.settle();
    net.sent.clear();

    await b
        .read(expenseAdderProvider.notifier)
        .updateSettlement(
          id: id,
          roomId: groupId,
          amountCents: 999,
          currency: 'EUR',
          fromUser: bob,
          toUser: alice,
        );
    expect(b.read(expenseAdderProvider).error, isA<RecordDeletedException>());
    await net.settle();
    expect(net.sent, isEmpty);
    final row = (await a.read(expensesDaoProvider).getSettlementById(id))!;
    expect(row.deleted, isTrue);
    expect(row.amountCents, 1500);
  });
}
