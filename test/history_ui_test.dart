/// G48 UI: the group's "Reset to an earlier state" page (change list →
/// preview → reset), the read-only case, the group menu entry, the
/// restore-points page (list → preview of the normal restore; web: none)
/// and its settings tile.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart' show RecordKind;
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/backup/backup_ui.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/history/group_history.dart';
import 'package:money_ledger/features/history/group_reset.dart';
import 'package:money_ledger/features/history/group_reset_page.dart';
import 'package:money_ledger/features/history/restore_points.dart';
import 'package:money_ledger/features/history/restore_points_page.dart';
import 'package:money_ledger/features/history/snapshot_store.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

const _bobSig = RecordSignature(user: bob, device: 'B', key: 'K', sig: 'S');

ExpenseModel _e(String id, String what, {bool deleted = false}) => ExpenseModel(
  id: id,
  roomId: 'g1',
  description: what,
  amountCents: 1200,
  currency: 'EUR',
  paidBy: alice,
  splitsJson: '{"$alice":1200}',
  createdAt: 1,
  updatedAt: 1,
  deleted: deleted,
  sig: deleted ? _bobSig : null,
);

HistoryEntry _entry(
  int id,
  RecordKind kind,
  String recordId,
  Map<String, dynamic> content,
  int at, {
  HistorySource source = HistorySource.inbound,
}) => HistoryEntry(
  id: id,
  groupId: 'g1',
  kind: kind,
  recordId: recordId,
  updatedAt: 1,
  versionHash: 'h',
  content: content,
  source: source,
  recordedAt: at,
);

final _t0 = DateTime(2026, 10, 14, 18).millisecondsSinceEpoch;
final _t1 = DateTime(2026, 10, 15, 21, 5).millisecondsSinceEpoch;

final _entries = [
  _entry(
    1,
    RecordKind.meta,
    'g1',
    groupMetaPayload(
      const GroupModel(roomId: 'g1', name: 'Trip', currency: 'EUR'),
    ),
    _t0,
    source: HistorySource.local,
  ),
  _entry(
    2,
    RecordKind.expense,
    'e1',
    expensePayload(_e('e1', 'Dinner')),
    _t0,
    source: HistorySource.local,
  ),
  // Bob deletes it a day later.
  _entry(
    3,
    RecordKind.expense,
    'e1',
    expensePayload(_e('e1', 'Dinner', deleted: true)),
    _t1,
  ),
];

const _alice = MemberModel(
  groupId: 'g1',
  userId: alice,
  displayName: 'Alice',
  matrixId: alice,
  status: 'active',
  updatedAt: 1,
);
const _bob = MemberModel(
  groupId: 'g1',
  userId: bob,
  displayName: 'Bob',
  matrixId: bob,
  status: 'active',
  updatedAt: 1,
);

class _FakeReset implements GroupResetService {
  final planned = <int>[];
  GroupResetPlan? applied;

  @override
  Future<GroupResetPlan> plan(String groupId, int beforeId) async {
    planned.add(beforeId);
    return GroupResetPlan(
      groupId: groupId,
      beforeId: beforeId,
      changes: [
        ResetChange.expense(
          ResetEffect.restored,
          _e('e1', 'Dinner').withSigning(),
        ),
      ],
    );
  }

  @override
  Future<int> apply(GroupResetPlan plan) async {
    applied = plan;
    return plan.changes.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('reset page', () {
    Widget page(_FakeReset fake, {bool removed = false}) => testRouterApp(
      const GroupResetPage(roomId: 'g1'),
      overrides: [
        ...testOverrides(members: const [_alice, _bob]),
        groupHistoryProvider.overrideWith((ref, g) => Stream.value(_entries)),
        historyFloorProvider.overrideWith((ref) => Stream.value(0)),
        currentUserIdProvider.overrideWith((ref) => alice),
        localModeActiveProvider.overrideWithValue(false),
        currentParticipantProvider.overrideWith(
          (ref, g) => Future<MemberModel?>.value(
            removed
                ? const MemberModel(
                    groupId: 'g1',
                    userId: alice,
                    displayName: 'Alice',
                    matrixId: alice,
                    status: 'removed',
                    updatedAt: 2,
                  )
                : _alice,
          ),
        ),
        groupResetServiceProvider.overrideWith((ref) => fake),
      ],
    );

    testWidgets('lists the changes; undo → preview → reset', (tester) async {
      final fake = _FakeReset();
      await tester.pumpWidget(page(fake));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('groupResetIntro')), findsOneWidget);
      // Bob's deletion (newest) can be undone; the group's arrival can't.
      expect(find.byKey(const Key('changeBatch-3')), findsOneWidget);
      expect(find.textContaining('1 deleted'), findsOneWidget);
      expect(find.textContaining('by Bob'), findsOneWidget);
      expect(find.byKey(const Key('undoFrom-1')), findsNothing);
      expect(
        find.textContaining('Earliest state on this device'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('undoFrom-3')));
      await tester.pumpAndSettle();
      expect(fake.planned, [3]);
      expect(find.byKey(const Key('resetPreviewDialog')), findsOneWidget);
      expect(find.text('1 entry comes back'), findsOneWidget);
      expect(find.textContaining('Dinner'), findsWidgets);
      expect(
        find.text('Everyone in the group gets these changes.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('resetConfirm')));
      await tester.pumpAndSettle();
      expect(fake.applied?.beforeId, 3);
      expect(find.text('Group reset (1 change)'), findsOneWidget);
      // Back on the host page.
      expect(find.text('host'), findsOneWidget);
    });

    testWidgets('a read-only (removed) group offers no reset', (tester) async {
      final fake = _FakeReset();
      await tester.pumpWidget(page(fake, removed: true));
      await tester.pumpAndSettle();
      expect(
        find.text("You were removed from this group, so it can't be reset."),
        findsOneWidget,
      );
      expect(find.byKey(const Key('undoFrom-3')), findsNothing);
    });

    testWidgets('German labels', (tester) async {
      await tester.pumpWidget(
        testRouterApp(
          const GroupResetPage(roomId: 'g1'),
          locale: const Locale('de'),
          overrides: [
            ...testOverrides(members: const [_alice, _bob]),
            groupHistoryProvider.overrideWith(
              (ref, g) => Stream.value(_entries),
            ),
            historyFloorProvider.overrideWith((ref) => Stream.value(0)),
            currentUserIdProvider.overrideWith((ref) => alice),
            localModeActiveProvider.overrideWithValue(false),
            currentParticipantProvider.overrideWith(
              (ref, g) => Future<MemberModel?>.value(_alice),
            ),
            groupResetServiceProvider.overrideWith((ref) => _FakeReset()),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gruppe zurücksetzen'), findsOneWidget);
      expect(find.text('Ab hier rückgängig'), findsOneWidget);
    });
  });

  group('restore points page', () {
    String snapshot() => buildBackupJson(
      account: alice,
      exportedAt: DateTime(2026, 10, 15, 3).millisecondsSinceEpoch,
      groups: [
        GroupSnapshot(
          group: const GroupModel(roomId: 'g1', name: 'Trip', currency: 'EUR'),
          members: const [_alice],
          expenses: [_e('e1', 'Dinner')],
          settlements: const [],
        ),
      ],
    );

    testWidgets('lists the snapshots; Restore opens the restore preview', (
      tester,
    ) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final store = InMemorySnapshotStore()
        ..files['2026-10-15.json'] = snapshot();
      final net = FakeMatrixNetwork();
      await tester.pumpWidget(
        testRouterApp(
          const RestorePointsPage(),
          overrides: [
            ...testOverrides(),
            appDatabaseProvider.overrideWithValue(db),
            ledgerTransportProvider.overrideWith((ref) => net.clientFor(alice)),
            currentUserIdProvider.overrideWith((ref) => alice),
            ledgerIdentityProvider.overrideWithValue(alice),
            snapshotStoreFactoryProvider.overrideWithValue((_) => store),
            // Not started — nothing is restored in this test.
            syncEngineProvider.overrideWith((ref) => SyncEngine(ref)),
          ],
        ),
      );
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('Restore points'), findsOneWidget);
      expect(
        find.byKey(const Key('restorePoint-2026-10-15.json')),
        findsOneWidget,
      );
      expect(find.text('1 group · 1 entry'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const Key('restorePointRestore-2026-10-15.json')),
        );
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find
              .byKey(const Key('restorePreviewDialog'))
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
      });
      await tester.pump();
      expect(find.byKey(const Key('restorePreviewDialog')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
    });

    testWidgets('no snapshot store (web): explains the alternatives', (
      tester,
    ) async {
      await tester.pumpWidget(
        testRouterApp(
          const RestorePointsPage(),
          overrides: [
            ...testOverrides(),
            ledgerIdentityProvider.overrideWithValue(alice),
            snapshotStoreFactoryProvider.overrideWithValue((_) => null),
            restorePointsProvider.overrideWith((ref) async => const []),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('noSnapshots')), findsOneWidget);
    });

    testWidgets('the settings section links to it', (tester) async {
      await tester.pumpWidget(
        testApp(
          const Scaffold(body: BackupSettingsSection()),
          overrides: testOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('restorePointsTile')), findsOneWidget);
      expect(find.text('Restore points'), findsOneWidget);
    });
  });
}
