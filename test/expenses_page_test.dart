import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_health.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';

const _roomId = '!test:matrix.org';

void main() {
  group('ExpensesPage', () {
    testWidgets('shows empty-state text when no expenses', (tester) async {
      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true, expenses: []),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('No expenses'), findsOneWidget);
    });

    testWidgets('shows FAB to add an expense', (tester) async {
      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Add expense'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows balance icon button in app bar', (tester) async {
      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.balance), findsOneWidget);
    });

    testWidgets('renders expense list tiles when expenses exist',
        (tester) async {
      final expenses = [
        ExpenseModel(
          id: 'uuid-1',
          roomId: _roomId,
          description: "Dinner at Luigi's",
          amountCents: 4200,
          currency: 'EUR',
          paidBy: '@alice:matrix.org',
          splitsJson: '{"@alice:matrix.org":2100,"@bob:matrix.org":2100}',
          createdAt: 0,
        ),
        ExpenseModel(
          id: 'uuid-2',
          roomId: _roomId,
          description: 'Taxi home',
          amountCents: 1500,
          currency: 'EUR',
          paidBy: '@bob:matrix.org',
          splitsJson: '{"@alice:matrix.org":750,"@bob:matrix.org":750}',
          createdAt: 1,
        ),
      ];

      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true, expenses: expenses),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text("Dinner at Luigi's"), findsOneWidget);
      expect(find.text('Taxi home'), findsOneWidget);
      expect(find.text('42.00 EUR'), findsOneWidget);
      expect(find.text('15.00 EUR'), findsOneWidget);
    });

    testWidgets('shows "Expenses" in the app bar', (tester) async {
      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true),
      ));
      await tester.pump();

      expect(find.text('Expenses'), findsOneWidget);
    });

    testWidgets('app bar shows the synced cloud when the group is in sync',
        (tester) async {
      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        // testOverrides defaults groupSyncStatus to fully synced.
        overrides: testOverrides(isLoggedIn: true),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
      expect(find.byIcon(Icons.cloud_queue), findsNothing);
    });

    testWidgets('app bar shows the error cloud and a retry sheet when sync fails',
        (tester) async {
      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: [
          ...testOverrides(isLoggedIn: true),
          syncHealthProvider.overrideWith(_FailingSyncHealth.new),
        ],
      ));
      await tester.pump();
      await tester.pump();

      // Error state wins over the synced/pending clouds and is tappable.
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);

      await tester.tap(find.byIcon(Icons.cloud_off));
      await tester.pumpAndSettle();

      expect(find.text('Sync problem'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry now'), findsOneWidget);
    });

    testWidgets(
        'app bar and tile show the pending cloud while waiting for a peer',
        (tester) async {
      const expense = ExpenseModel(
        id: 'e1',
        roomId: _roomId,
        description: 'Dinner',
        amountCents: 4000,
        currency: 'EUR',
        paidBy: '@alice:matrix.org',
        splitsJson: '{"@alice:matrix.org":4000}',
        createdAt: 5000,
        updatedAt: 5000,
      );

      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: [
          expensesForRoomProvider
              .overrideWith((ref, roomId) => Stream.value([expense])),
          groupMembersProvider
              .overrideWith((ref, groupId) => Stream.value(const [])),
          groupSyncStatusProvider.overrideWith(
            (ref, groupId) => const GroupSyncStatus(
                pendingPeers: {'@bob:y.org'}, minPeerInSyncAt: 0),
          ),
        ],
      ));
      await tester.pump();
      await tester.pump();

      // One pending cloud in the app bar + one on the un-replicated tile.
      expect(find.byIcon(Icons.cloud_queue), findsNWidgets(2));
      expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
      expect(find.byTooltip('Waiting for @bob:y.org…'), findsOneWidget);
    });

    testWidgets('shows a self-claim banner when not yet a participant',
        (tester) async {
      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: [
          expensesForRoomProvider
              .overrideWith((ref, roomId) => Stream.value(const [])),
          groupSyncStatusProvider.overrideWith((ref, g) =>
              const GroupSyncStatus(pendingPeers: {}, minPeerInSyncAt: null)),
          // A local participant exists, but this device claims nobody.
          groupMembersProvider.overrideWith((ref, g) => Stream.value(const [
                MemberModel(
                    groupId: _roomId,
                    userId: 'p-bobby',
                    displayName: 'Bobby',
                    status: 'active',
                    updatedAt: 1),
              ])),
          currentParticipantProvider
              .overrideWith((ref, g) => Future<MemberModel?>.value(null)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Which participant are you'), findsOneWidget);
      // Opening the picker lists the unclaimed local participant.
      await tester.tap(find.widgetWithText(TextButton, 'Choose'));
      await tester.pumpAndSettle();
      expect(find.text('Bobby'), findsOneWidget);
      expect(find.text("I'm someone new"), findsOneWidget);
    });

    testWidgets('confirming the delete dialog tombstones the expense',
        (tester) async {
      // The list itself renders from an overridden stream (Drift watch streams
      // don't mix with the widget-test fake clock); the real in-memory DB is
      // only used to verify the tombstone write that confirm triggers. The
      // tombstone-filtered list rendering is covered by the DAO tests.
      const expense = ExpenseModel(
        id: 'e1',
        roomId: 'g1',
        description: 'Mistake',
        amountCents: 100,
        currency: 'EUR',
        paidBy: '@alice:x.org',
        splitsJson: '{"@alice:x.org":100}',
        createdAt: 1000,
        updatedAt: 1000,
      );
      final db = openTestDatabase();
      addTearDown(db.close);
      await ExpensesDao(db).upsertExpenseLww(const ExpensesCompanion(
        id: Value('e1'),
        roomId: Value('g1'),
        description: Value('Mistake'),
        amountCents: Value(100),
        currency: Value('EUR'),
        paidBy: Value('@alice:x.org'),
        splitsJson: Value('{"@alice:x.org":100}'),
        createdAt: Value(1000),
        updatedAt: Value(1000),
      ));
      await MembersDao(db).upsertMemberLww(const MembersCompanion(
        groupId: Value('g1'),
        userId: Value('@alice:x.org'),
        status: Value('active'),
        updatedAt: Value(1000),
      ));
      final net = FakeMatrixNetwork();

      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: 'g1'),
        overrides: [
          ...testOverrides(isLoggedIn: true, expenses: [expense]),
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider
              .overrideWith((ref) => net.clientFor('@alice:x.org')),
        ],
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Mistake'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete expense?'), findsOneWidget);

      // Drift writes resolve on the real event loop — confirm under runAsync
      // (see create_group_page_test.dart for the pattern).
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();

        // The row survives as a tombstone for anti-entropy.
        final all = await ExpensesDao(db).getAllExpensesForGroup('g1');
        expect(all.single.deleted, true);
      });
    });

    testWidgets('cancelling the delete dialog keeps the expense',
        (tester) async {
      final expenses = [
        const ExpenseModel(
          id: 'e1',
          roomId: _roomId,
          description: 'Keep me',
          amountCents: 100,
          currency: 'EUR',
          paidBy: '@alice:matrix.org',
          splitsJson: '{"@alice:matrix.org":100}',
          createdAt: 0,
        ),
      ];

      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true, expenses: expenses),
      ));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Keep me'), findsOneWidget);
    });
  });
}

/// Overrides [syncHealthProvider] with a sustained-failure state.
class _FailingSyncHealth extends SyncHealth {
  @override
  SyncHealthState build() => const SyncHealthState(
        consecutiveFailures: kSyncFailureThreshold,
        lastError: 'offline',
        lastSuccessAt: 1,
      );
}
