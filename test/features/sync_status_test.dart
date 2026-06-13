/// Sync-status (Phase C, M7): the pure status computation and the reactive
/// `groupSyncStatusProvider` that drives the cloud icons. A peer counts as
/// caught up only once a matching digest has written its `lastInSyncAt`.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/sync_states_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

MemberModel _m(String id, {String status = 'active', int updatedAt = 0}) =>
    MemberModel(groupId: 'g1', userId: id, status: status, updatedAt: updatedAt);

void main() {
  group('computeSyncStatus', () {
    test('a solo group (no peers) is always synced and never pending', () {
      final s = computeSyncStatus(
        selfId: '@alice:x.org',
        members: [_m('@alice:x.org')],
        peerInSyncAt: const {},
        maxRecordUpdatedAt: 5000,
      );
      expect(s.synced, true);
      expect(s.pendingPeers, isEmpty);
      expect(s.isRecordPending(5000), false);
    });

    test('a peer with no recorded sync is pending', () {
      final s = computeSyncStatus(
        selfId: '@alice:x.org',
        members: [_m('@alice:x.org'), _m('@bob:y.org')],
        peerInSyncAt: const {},
        maxRecordUpdatedAt: 5000,
      );
      expect(s.synced, false);
      expect(s.pendingPeers, {'@bob:y.org'});
      expect(s.isRecordPending(5000), true);
      expect(s.isRecordPending(0), false);
    });

    test('a peer in sync below the latest record is still pending', () {
      final s = computeSyncStatus(
        selfId: '@alice:x.org',
        members: [_m('@alice:x.org'), _m('@bob:y.org')],
        peerInSyncAt: const {'@bob:y.org': 4000},
        maxRecordUpdatedAt: 5000,
      );
      expect(s.synced, false);
      expect(s.pendingPeers, {'@bob:y.org'});
      // The record at 4000 is known-replicated; the one at 5000 is not.
      expect(s.isRecordPending(4000), false);
      expect(s.isRecordPending(5000), true);
    });

    test('all peers caught up to the latest record → synced', () {
      final s = computeSyncStatus(
        selfId: '@alice:x.org',
        members: [_m('@alice:x.org'), _m('@bob:y.org')],
        peerInSyncAt: const {'@bob:y.org': 5000},
        maxRecordUpdatedAt: 5000,
      );
      expect(s.synced, true);
      expect(s.pendingPeers, isEmpty);
      expect(s.isRecordPending(5000), false);
    });

    test('removed members are ignored', () {
      final s = computeSyncStatus(
        selfId: '@alice:x.org',
        members: [
          _m('@alice:x.org'),
          _m('@bob:y.org', status: 'removed', updatedAt: 6000),
        ],
        peerInSyncAt: const {},
        maxRecordUpdatedAt: 5000,
      );
      expect(s.synced, true);
      expect(s.pendingPeers, isEmpty);
    });

    test('pending reflects the laggard; min in-sync gates per-record pending',
        () {
      final s = computeSyncStatus(
        selfId: '@alice:x.org',
        members: [_m('@alice:x.org'), _m('@bob:y.org'), _m('@carol:z.org')],
        peerInSyncAt: const {'@bob:y.org': 5000, '@carol:z.org': 3000},
        maxRecordUpdatedAt: 5000,
      );
      expect(s.pendingPeers, {'@carol:z.org'});
      // Carol (min = 3000) hasn't acked records newer than 3000.
      expect(s.isRecordPending(3000), false);
      expect(s.isRecordPending(4000), true);
    });
  });

  group('groupSyncStatusProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = openTestDatabase();
      final net = FakeMatrixNetwork();
      container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider
            .overrideWith((ref) => net.clientFor('@alice:x.org')),
      ]);
      addTearDown(() {
        container.dispose();
        db.close();
      });
      // Seed a group: Alice (self) + Bob, one expense at updatedAt = 5000.
      await GroupsDao(db).upsertGroupLww(const GroupsCompanion(
        roomId: Value('g1'),
        name: Value('Trip'),
        currency: Value('EUR'),
        updatedAt: Value(1000),
      ));
      for (final id in ['@alice:x.org', '@bob:y.org']) {
        await MembersDao(db).upsertMemberLww(MembersCompanion(
          groupId: const Value('g1'),
          userId: Value(id),
          status: const Value('active'),
          updatedAt: const Value(1000),
        ));
      }
      await ExpensesDao(db).upsertExpenseLww(const ExpensesCompanion(
        id: Value('e1'),
        roomId: Value('g1'),
        description: Value('Dinner'),
        amountCents: Value(4000),
        currency: Value('EUR'),
        paidBy: Value('@alice:x.org'),
        splitsJson: Value('{"@alice:x.org":2000,"@bob:y.org":2000}'),
        createdAt: Value(5000),
        updatedAt: Value(5000),
      ));
    });

    Future<GroupSyncStatus> readStatus() async {
      container.listen(groupSyncStatusProvider('g1'), (_, _) {});
      // Force every watched stream to emit before reading the derived value.
      await container.read(groupMembersProvider('g1').future);
      await container.read(peerSyncStatesProvider('g1').future);
      await container.read(allExpensesForGroupProvider('g1').future);
      await container.read(allSettlementsForGroupProvider('g1').future);
      await container.read(ledgerGroupsProvider.future);
      return container.read(groupSyncStatusProvider('g1'));
    }

    test('a peer with no digest match is pending', () async {
      final s = await readStatus();
      expect(s.synced, false);
      expect(s.pendingPeers, {'@bob:y.org'});
      expect(s.isRecordPending(5000), true);
    });

    test('writing a matching peer sync state flips the group to synced',
        () async {
      expect((await readStatus()).synced, false);

      await SyncStatesDao(db).markInSync('g1', '@bob:y.org', 5000);

      final s = await readStatus();
      expect(s.synced, true);
      expect(s.pendingPeers, isEmpty);
      expect(s.isRecordPending(5000), false);
    });
  });
}
