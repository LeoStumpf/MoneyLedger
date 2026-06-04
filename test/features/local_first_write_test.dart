import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

void main() {
  group('local-first writes', () {
    test('addExpense persists to Drift even when replication fails (offline)',
        () async {
      final net = FakeMatrixNetwork();
      final alice = net.clientFor('@alice:x.org');
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => openTestDatabase()),
        ledgerTransportProvider.overrideWith((ref) => alice),
      ]);
      addTearDown(container.dispose);

      // The room was never created on the transport, so sendExpense throws —
      // standing in for "offline / cannot reach peers right now".
      await container.read(expenseAdderProvider.notifier).addExpense(
        roomId: '!missing:x.org',
        description: 'Pizza',
        amountCents: 2000,
        currency: 'CHF',
        paidBy: '@alice:x.org',
        splits: const {'@alice:x.org': 1000, '@bob:x.org': 1000},
      );

      // The user's action succeeded locally despite replication failing.
      expect(container.read(expenseAdderProvider).hasError, isFalse);
      final saved = await container
          .read(expensesDaoProvider)
          .getExpensesForRoom('!missing:x.org');
      expect(saved, hasLength(1));
      expect(saved.first.description, 'Pizza');
      expect(saved.first.amountCents, 2000);
      // Not yet replicated → no Matrix event id.
      expect(saved.first.matrixEventId, isNull);
    });

    test('addExpense writes locally AND replicates when online', () async {
      final net = FakeMatrixNetwork();
      final alice = net.clientFor('@alice:x.org');
      final roomId = await alice.createGroup('Trip', 'CHF');
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => openTestDatabase()),
        ledgerTransportProvider.overrideWith((ref) => alice),
      ]);
      addTearDown(container.dispose);

      await container.read(expenseAdderProvider.notifier).addExpense(
        roomId: roomId,
        description: 'Pizza',
        amountCents: 2000,
        currency: 'CHF',
        paidBy: '@alice:x.org',
        splits: const {'@alice:x.org': 2000},
      );

      // Local copy exists immediately...
      final local =
          await container.read(expensesDaoProvider).getExpensesForRoom(roomId);
      expect(local, hasLength(1));
      // ...and the same record was replicated to the transport.
      final sent = await alice.timelineEvents(roomId);
      expect(sent, hasLength(1));
      expect(sent.first.content['id'], local.first.id);
      expect(sent.first.content['description'], 'Pizza');
    });

    test('addSettlement persists locally when replication fails', () async {
      final net = FakeMatrixNetwork();
      final alice = net.clientFor('@alice:x.org');
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => openTestDatabase()),
        ledgerTransportProvider.overrideWith((ref) => alice),
      ]);
      addTearDown(container.dispose);

      await container.read(expenseAdderProvider.notifier).addSettlement(
            roomId: '!missing:x.org',
            amountCents: 500,
            currency: 'CHF',
            fromUser: '@bob:x.org',
            toUser: '@alice:x.org',
          );

      expect(container.read(expenseAdderProvider).hasError, isFalse);
      final saved = await container
          .read(expensesDaoProvider)
          .getSettlementsForRoom('!missing:x.org');
      expect(saved, hasLength(1));
      expect(saved.first.amountCents, 500);
      expect(saved.first.matrixEventId, isNull);
    });
  });
}
