import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

/// A transport whose every send fails — stands in for "offline / cannot reach
/// peers right now". Lets us assert that a write still persists locally.
class _OfflineTransport implements LedgerTransport {
  @override
  String get userId => '@alice:x.org';
  @override
  Stream<TransportMessage> get onMessage => const Stream.empty();
  @override
  Future<SendResult> sendToUsers(
          Set<String> userIds, String type, Map<String, dynamic> content) async =>
      throw Exception('offline');
  @override
  Future<String?> profileName(String matrixId) async => null;
}

void main() {
  group('local-first writes', () {
    Future<void> seedMembers(ProviderContainer c, String group) async {
      final dao = c.read(membersDaoProvider);
      for (final u in ['@alice:x.org', '@bob:x.org']) {
        await dao.upsertMemberLww(MembersCompanion(
          groupId: Value(group),
          userId: Value(u),
          matrixId: Value(u), // claimed members are the replication targets
          status: const Value('active'),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ));
      }
    }

    test('addExpense persists to Drift even when replication fails (offline)',
        () async {
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => openTestDatabase()),
        ledgerTransportProvider.overrideWith((ref) => _OfflineTransport()),
      ]);
      addTearDown(container.dispose);
      await seedMembers(container, 'g1');

      await container.read(expenseAdderProvider.notifier).addExpense(
            roomId: 'g1',
            description: 'Pizza',
            amountCents: 2000,
            currency: 'CHF',
            paidBy: '@alice:x.org',
            splits: const {'@alice:x.org': 1000, '@bob:x.org': 1000},
          );

      // The user's action succeeded locally despite replication throwing.
      expect(container.read(expenseAdderProvider).hasError, isFalse);
      final saved =
          await container.read(expensesDaoProvider).getExpensesForRoom('g1');
      expect(saved, hasLength(1));
      expect(saved.first.description, 'Pizza');
      expect(saved.first.amountCents, 2000);
    });

    test('addExpense writes locally AND replicates to members when online',
        () async {
      final net = FakeMatrixNetwork();
      final alice = net.clientFor('@alice:x.org');
      final bob = net.clientFor('@bob:x.org');
      final received = <TransportMessage>[];
      bob.onMessage.listen(received.add);

      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => openTestDatabase()),
        ledgerTransportProvider.overrideWith((ref) => alice),
      ]);
      addTearDown(container.dispose);
      await seedMembers(container, 'g1');

      await container.read(expenseAdderProvider.notifier).addExpense(
            roomId: 'g1',
            description: 'Pizza',
            amountCents: 2000,
            currency: 'CHF',
            paidBy: '@alice:x.org',
            splits: const {'@alice:x.org': 1000, '@bob:x.org': 1000},
          );
      await net.settle();

      // Local copy exists immediately...
      final local =
          await container.read(expensesDaoProvider).getExpensesForRoom('g1');
      expect(local, hasLength(1));
      // ...and the same record was relayed to the other member (not to self).
      expect(received, hasLength(1));
      expect(received.first.type, expenseEventType);
      expect(received.first.content['id'], local.first.id);
      expect(received.first.content['description'], 'Pizza');
    });

    test('updateExpense persists the edit locally when offline', () async {
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => openTestDatabase()),
        ledgerTransportProvider.overrideWith((ref) => _OfflineTransport()),
      ]);
      addTearDown(container.dispose);
      await seedMembers(container, 'g1');

      final adder = container.read(expenseAdderProvider.notifier);
      await adder.addExpense(
        roomId: 'g1',
        description: 'Pizza',
        amountCents: 2000,
        currency: 'CHF',
        paidBy: '@alice:x.org',
        splits: const {'@alice:x.org': 1000, '@bob:x.org': 1000},
      );
      final saved =
          (await container.read(expensesDaoProvider).getExpensesForRoom('g1'))
              .single;

      await adder.updateExpense(
        id: saved.id,
        roomId: 'g1',
        description: 'Pizza + drinks',
        amountCents: 3000,
        currency: 'CHF',
        paidBy: '@alice:x.org',
        splits: const {'@alice:x.org': 1500, '@bob:x.org': 1500},
        createdAt: saved.createdAt,
      );

      expect(container.read(expenseAdderProvider).hasError, isFalse);
      final edited =
          (await container.read(expensesDaoProvider).getExpensesForRoom('g1'))
              .single;
      expect(edited.id, saved.id);
      expect(edited.description, 'Pizza + drinks');
      expect(edited.amountCents, 3000);
      expect(edited.updatedAt, greaterThanOrEqualTo(saved.updatedAt));
    });

    test('deleteExpense tombstones locally when offline', () async {
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => openTestDatabase()),
        ledgerTransportProvider.overrideWith((ref) => _OfflineTransport()),
      ]);
      addTearDown(container.dispose);
      await seedMembers(container, 'g1');

      final adder = container.read(expenseAdderProvider.notifier);
      await adder.addExpense(
        roomId: 'g1',
        description: 'Mistake',
        amountCents: 100,
        currency: 'CHF',
        paidBy: '@alice:x.org',
        splits: const {'@alice:x.org': 100},
      );
      final dao = container.read(expensesDaoProvider);
      final saved = (await dao.getExpensesForRoom('g1')).single;

      await adder.deleteExpense(saved.id, 'g1');

      expect(container.read(expenseAdderProvider).hasError, isFalse);
      // Hidden from the UI, but kept as a tombstone for anti-entropy.
      expect(await dao.getExpensesForRoom('g1'), isEmpty);
      final all = await dao.getAllExpensesForGroup('g1');
      expect(all.single.deleted, true);
    });

    test('deleteSettlement tombstones locally when offline', () async {
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => openTestDatabase()),
        ledgerTransportProvider.overrideWith((ref) => _OfflineTransport()),
      ]);
      addTearDown(container.dispose);
      await seedMembers(container, 'g1');

      final adder = container.read(expenseAdderProvider.notifier);
      await adder.addSettlement(
        roomId: 'g1',
        amountCents: 500,
        currency: 'CHF',
        fromUser: '@bob:x.org',
        toUser: '@alice:x.org',
      );
      final dao = container.read(expensesDaoProvider);
      final saved = (await dao.getSettlementsForRoom('g1')).single;

      await adder.deleteSettlement(saved.id, 'g1');

      expect(container.read(expenseAdderProvider).hasError, isFalse);
      expect(await dao.getSettlementsForRoom('g1'), isEmpty);
      final all = await dao.getAllSettlementsForGroup('g1');
      expect(all.single.deleted, true);
    });

    test('addSettlement persists locally when replication fails', () async {
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => openTestDatabase()),
        ledgerTransportProvider.overrideWith((ref) => _OfflineTransport()),
      ]);
      addTearDown(container.dispose);
      await seedMembers(container, 'g1');

      await container.read(expenseAdderProvider.notifier).addSettlement(
            roomId: 'g1',
            amountCents: 500,
            currency: 'CHF',
            fromUser: '@bob:x.org',
            toUser: '@alice:x.org',
          );

      expect(container.read(expenseAdderProvider).hasError, isFalse);
      final saved =
          await container.read(expensesDaoProvider).getSettlementsForRoom('g1');
      expect(saved, hasLength(1));
      expect(saved.first.amountCents, 500);
    });
  });
}
