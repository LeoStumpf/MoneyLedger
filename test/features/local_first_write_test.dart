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
  Future<void> sendToUsers(
          Set<String> userIds, String type, Map<String, dynamic> content) async =>
      throw Exception('offline');
}

void main() {
  group('local-first writes', () {
    Future<void> seedMembers(ProviderContainer c, String group) async {
      final dao = c.read(membersDaoProvider);
      for (final u in ['@alice:x.org', '@bob:x.org']) {
        await dao.upsertMemberLww(MembersCompanion(
          groupId: Value(group),
          userId: Value(u),
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
