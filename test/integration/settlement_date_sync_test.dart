/// G60 end to end: a back-dated payment reaches the other members through
/// the signed live relay (date verified as part of the content), its delete
/// keeps the date, and a later member gets it via the (verified) bootstrap.
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

  test('the payment date replicates; bootstrap and delete carry it', () async {
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
    final day = DateTime(now.year, now.month, now.day - 2);
    await alice
        .read(expenseAdderProvider.notifier)
        .addSettlement(
          roomId: groupId,
          amountCents: 1500,
          currency: 'EUR',
          fromUser: '@bob:y.org',
          toUser: '@alice:x.org',
          day: day,
        );
    await net.settle();

    final row =
        (await bob.read(expensesDaoProvider).getSettlementsForRoom(groupId))
            .single;
    expect(row.date, expenseDateOf(day));
    expect(row.displayDay, day);
    expect(row.sig, isNotNull); // verified + stored as signed
    expect(row.origin!.user, '@alice:x.org');

    // Carol joins later: her bootstrap (verified record by record) has it.
    final carol = makeUser(net, '@carol:z.org');
    await net.settle();
    await alice.read(memberAdderProvider.notifier).add(groupId, '@carol:z.org');
    await net.settle();
    final carolRow = await carol
        .read(expensesDaoProvider)
        .getSettlementById(row.id);
    expect(carolRow!.date, expenseDateOf(day));

    // Bob deletes it: the tombstone keeps the date (same content) and
    // verifies on Alice's side.
    await bob
        .read(expenseAdderProvider.notifier)
        .deleteSettlement(row.id, groupId);
    await net.settle();
    final gone = await alice
        .read(expensesDaoProvider)
        .getSettlementById(row.id);
    expect(gone!.deleted, isTrue);
    expect(gone.date, expenseDateOf(day));
    expect(gone.sig!.user, '@bob:y.org');
  });

  test('a payment dated today carries no date at all', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org');
    await net.settle();
    final groupId = (await alice
        .read(groupCreatorProvider.notifier)
        .create('Solo', 'EUR'))!;
    await alice
        .read(expenseAdderProvider.notifier)
        .addSettlement(
          roomId: groupId,
          amountCents: 400,
          currency: 'EUR',
          fromUser: '@alice:x.org',
          toUser: 'someone',
          day: DateTime.now(),
        );
    final row =
        (await alice.read(expensesDaoProvider).getSettlementsForRoom(groupId))
            .single;
    expect(row.date, isNull);
  });
}
