import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/l10n/formatting.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_health.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';
import 'helpers/eventually.dart';

const _roomId = '!test:matrix.org';

void main() {
  group('ExpensesPage', () {
    testWidgets('shows empty-state text when no expenses', (tester) async {
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _roomId),
          overrides: testOverrides(isLoggedIn: true, expenses: []),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('No expenses'), findsOneWidget);
    });

    testWidgets('shows FAB to add an expense', (tester) async {
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _roomId),
          overrides: testOverrides(isLoggedIn: true),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Add expense'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('summary card links to the balances (G17)', (tester) async {
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _roomId),
          overrides: testOverrides(
            isLoggedIn: true,
            expenses: const [
              ExpenseModel(
                id: 'e1',
                roomId: _roomId,
                description: 'Dinner',
                amountCents: 4000,
                currency: 'EUR',
                paidBy: '@alice:matrix.org',
                splitsJson: '{"@alice:matrix.org":4000}',
                createdAt: 5000,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('groupSummaryCard')), findsOneWidget);
      expect(find.byKey(const Key('balancesButton')), findsOneWidget);
      expect(find.byIcon(Icons.balance), findsOneWidget);
    });

    testWidgets('Settle up opens the payment dialog prefilled with my debt '
        '(G17)', (tester) async {
      const me = '@bob:matrix.org';
      const alice = '@alice:matrix.org';
      MemberModel m(String id, String name) => MemberModel(
        groupId: _roomId,
        userId: id,
        displayName: name,
        matrixId: id,
        status: 'active',
        updatedAt: 1,
      );
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _roomId),
          overrides: [
            ...testOverrides(
              isLoggedIn: true,
              expenses: const [
                ExpenseModel(
                  id: 'e1',
                  roomId: _roomId,
                  description: 'Dinner',
                  amountCents: 2000,
                  currency: 'EUR',
                  paidBy: alice,
                  splitsJson: '{"$alice":1000,"$me":1000}',
                  createdAt: 5000,
                ),
              ],
              debts: const [
                DebtEntry(from: me, to: alice, cents: 1000, currency: 'EUR'),
              ],
              members: [m(alice, 'Alice'), m(me, 'Bob')],
            ),
            currentParticipantProvider.overrideWith(
              (ref, g) => Future<MemberModel?>.value(m(me, 'Bob')),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      // The tile says what the expense means for me.
      expect(find.text('Paid by Alice'), findsOneWidget);
      expect(find.text('you borrowed €10.00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settleUpButton')));
      await tester.pumpAndSettle();
      expect(find.text('Record payment'), findsOneWidget);
      expect(find.widgetWithText(TextField, '10.00'), findsOneWidget);
    });

    testWidgets('German locale: amounts and labels are localized (G12)', (
      tester,
    ) async {
      final expenses = [
        ExpenseModel(
          id: 'uuid-1',
          roomId: _roomId,
          description: 'Hotel',
          amountCents: 123450,
          currency: 'EUR',
          paidBy: '@alice:matrix.org',
          splitsJson: '{"@alice:matrix.org":123450}',
          createdAt: 0,
        ),
      ];
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _roomId),
          locale: const Locale('de'),
          overrides: testOverrides(isLoggedIn: true, expenses: expenses),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Ausgaben'), findsOneWidget);
      expect(find.text('1.234,50\u00a0€'), findsOneWidget);
      expect(find.textContaining('Bezahlt von'), findsOneWidget);
      expect(find.text('Ausgabe hinzufügen'), findsOneWidget);
    });

    testWidgets('renders expense list tiles when expenses exist', (
      tester,
    ) async {
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

      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _roomId),
          overrides: testOverrides(isLoggedIn: true, expenses: expenses),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text("Dinner at Luigi's"), findsOneWidget);
      expect(find.text('Taxi home'), findsOneWidget);
      expect(find.text('€42.00'), findsOneWidget);
      expect(find.text('€15.00'), findsOneWidget);
    });

    testWidgets('shows "Expenses" in the app bar', (tester) async {
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _roomId),
          overrides: testOverrides(isLoggedIn: true),
        ),
      );
      await tester.pump();

      expect(find.text('Expenses'), findsOneWidget);
    });

    testWidgets('app bar shows the synced cloud when the group is in sync', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _roomId),
          // testOverrides defaults groupSyncStatus to fully synced.
          overrides: testOverrides(isLoggedIn: true),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
      expect(find.byIcon(Icons.cloud_queue), findsNothing);
    });

    testWidgets(
      'app bar shows the error cloud and a retry sheet when sync fails',
      (tester) async {
        await tester.pumpWidget(
          testApp(
            const ExpensesPage(roomId: _roomId),
            overrides: [
              ...testOverrides(isLoggedIn: true),
              syncHealthProvider.overrideWith(_FailingSyncHealth.new),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        // Error state wins over the synced/pending clouds and is tappable.
        expect(find.byIcon(Icons.cloud_off), findsOneWidget);
        expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);

        await tester.tap(find.byIcon(Icons.cloud_off));
        await tester.pumpAndSettle();

        expect(find.text('Sync problem'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Retry now'), findsOneWidget);
      },
    );

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

        await tester.pumpWidget(
          testApp(
            const ExpensesPage(roomId: _roomId),
            overrides: [
              ...signingUiOverrides(),
              expensesForRoomProvider.overrideWith(
                (ref, roomId) => Stream.value([expense]),
              ),
              settlementsForRoomProvider.overrideWith(
                (ref, roomId) => Stream.value(const []),
              ),
              groupMembersProvider.overrideWith(
                (ref, groupId) => Stream.value(const []),
              ),
              ledgerGroupsProvider.overrideWith(
                (ref) => Stream.value(const []),
              ),
              groupSyncStatusProvider.overrideWith(
                (ref, groupId) => const GroupSyncStatus(
                  pendingPeers: {'@bob:y.org'},
                  minPeerInSyncAt: 0,
                ),
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        // One pending cloud in the app bar + one on the un-replicated tile.
        expect(find.byIcon(Icons.cloud_queue), findsNWidgets(2));
        expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
        expect(find.byTooltip('Waiting for @bob:y.org…'), findsOneWidget);
      },
    );

    testWidgets(
      'pending cloud says a peer has no active device (not an error)',
      (tester) async {
        await tester.pumpWidget(
          testApp(
            const ExpensesPage(roomId: _roomId),
            overrides: [
              expensesForRoomProvider.overrideWith(
                (ref, roomId) => Stream.value(const []),
              ),
              settlementsForRoomProvider.overrideWith(
                (ref, roomId) => Stream.value(const []),
              ),
              groupMembersProvider.overrideWith(
                (ref, groupId) => Stream.value(const []),
              ),
              ledgerGroupsProvider.overrideWith(
                (ref) => Stream.value(const []),
              ),
              groupSyncStatusProvider.overrideWith(
                (ref, groupId) => const GroupSyncStatus(
                  pendingPeers: {'@bob:y.org'},
                  minPeerInSyncAt: 0,
                ),
              ),
              syncHealthProvider.overrideWith(_NoDeviceSyncHealth.new),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byIcon(Icons.cloud_off), findsNothing);
        expect(
          find.byTooltip(
            '@bob:y.org has no active device — will sync when they sign in',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows a self-claim banner when not yet a participant', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _roomId),
          overrides: [
            expensesForRoomProvider.overrideWith(
              (ref, roomId) => Stream.value(const []),
            ),
            settlementsForRoomProvider.overrideWith(
              (ref, roomId) => Stream.value(const []),
            ),
            groupSyncStatusProvider.overrideWith(
              (ref, g) => const GroupSyncStatus(
                pendingPeers: {},
                minPeerInSyncAt: null,
              ),
            ),
            ledgerGroupsProvider.overrideWith((ref) => Stream.value(const [])),
            // A local participant exists, but this device claims nobody.
            groupMembersProvider.overrideWith(
              (ref, g) => Stream.value(const [
                MemberModel(
                  groupId: _roomId,
                  userId: 'p-bobby',
                  displayName: 'Bobby',
                  status: 'active',
                  updatedAt: 1,
                ),
              ]),
            ),
            currentParticipantProvider.overrideWith(
              (ref, g) => Future<MemberModel?>.value(null),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Which participant are you'), findsOneWidget);
      // Opening the picker lists the unclaimed local participant.
      await tester.tap(find.widgetWithText(TextButton, 'Choose'));
      await tester.pumpAndSettle();
      expect(find.text('Bobby'), findsOneWidget);
      expect(find.text("I'm someone new"), findsOneWidget);
    });

    testWidgets('confirming the delete dialog tombstones the expense', (
      tester,
    ) async {
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
      await ExpensesDao(db).upsertExpenseLww(
        const ExpensesCompanion(
          id: Value('e1'),
          roomId: Value('g1'),
          description: Value('Mistake'),
          amountCents: Value(100),
          currency: Value('EUR'),
          paidBy: Value('@alice:x.org'),
          splitsJson: Value('{"@alice:x.org":100}'),
          createdAt: Value(1000),
          updatedAt: Value(1000),
        ),
      );
      await MembersDao(db).upsertMemberLww(
        const MembersCompanion(
          groupId: Value('g1'),
          userId: Value('@alice:x.org'),
          status: Value('active'),
          updatedAt: Value(1000),
        ),
      );
      final net = FakeMatrixNetwork();

      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: 'g1'),
          overrides: [
            ...testOverrides(isLoggedIn: true, expenses: [expense]),
            appDatabaseProvider.overrideWithValue(db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
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
        await eventually(
          () async => (await ExpensesDao(
            db,
          ).getAllExpensesForGroup('g1')).every((e) => e.deleted),
          tester: tester,
        );

        // The row survives as a tombstone for anti-entropy.
        final all = await ExpensesDao(db).getAllExpensesForGroup('g1');
        expect(all.single.deleted, true);
      });
    });

    testWidgets('cancelling the delete dialog keeps the expense', (
      tester,
    ) async {
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

      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _roomId),
          overrides: testOverrides(isLoggedIn: true, expenses: expenses),
        ),
      );
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

    group('settlements', () {
      // 2026-06-13 12:00 local — far from midnight, so the date is stable.
      final t1 = DateTime(2026, 6, 13, 12).millisecondsSinceEpoch;
      final t2 = DateTime(2026, 6, 14, 12).millisecondsSinceEpoch;
      final t3 = DateTime(2026, 6, 15, 12).millisecondsSinceEpoch;
      const names = {'p-alex': 'Alex', 'p-sam': 'Sam'};

      SettlementModel settlement(String id, int at, {int cents = 1250}) =>
          SettlementModel(
            id: id,
            roomId: _roomId,
            amountCents: cents,
            currency: 'EUR',
            fromUser: 'p-alex',
            toUser: 'p-sam',
            createdAt: at,
            updatedAt: at,
          );

      ExpenseModel expense(String id, String description, int at) =>
          ExpenseModel(
            id: id,
            roomId: _roomId,
            description: description,
            amountCents: 4000,
            currency: 'EUR',
            paidBy: 'p-sam',
            splitsJson: '{"p-alex":2000,"p-sam":2000}',
            createdAt: at,
            updatedAt: at,
          );

      testWidgets('a settlement shows with names, amount and date', (
        tester,
      ) async {
        await tester.pumpWidget(
          testApp(
            const ExpensesPage(roomId: _roomId),
            overrides: [
              ...testOverrides(
                isLoggedIn: true,
                settlements: [settlement('s1', t1)],
              ),
              participantNamesProvider.overrideWith((ref, g) => names),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        // Only a settlement — the empty state must not show.
        expect(find.textContaining('No expenses'), findsNothing);
        expect(find.text('Alex paid Sam'), findsOneWidget);
        expect(find.text('€12.50'), findsOneWidget);
        // G17: the date moved into the day header above the row.
        expect(find.text('Payment'), findsOneWidget);
        expect(find.text(formatDayHeader(t1, 'en')), findsOneWidget);
        expect(find.byIcon(Icons.handshake_outlined), findsOneWidget);
      });

      testWidgets('settlements merge with expenses newest first', (
        tester,
      ) async {
        await tester.pumpWidget(
          testApp(
            const ExpensesPage(roomId: _roomId),
            overrides: [
              ...testOverrides(
                isLoggedIn: true,
                expenses: [
                  expense('e3', 'Hotel', t3),
                  expense('e1', 'Taxi', t1),
                ],
                settlements: [settlement('s2', t2)],
              ),
              participantNamesProvider.overrideWith((ref, g) => names),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        final dy = [
          tester.getTopLeft(find.text('Hotel')).dy,
          tester.getTopLeft(find.text('Alex paid Sam')).dy,
          tester.getTopLeft(find.text('Taxi')).dy,
        ];
        expect(dy[0], lessThan(dy[1]));
        expect(dy[1], lessThan(dy[2]));
      });

      testWidgets(
        'delete via menu + confirm tombstones it and hides the tile',
        (tester) async {
          final db = openTestDatabase();
          addTearDown(db.close);
          final dao = ExpensesDao(db);
          await tester.runAsync(() async {
            await dao.upsertSettlementLww(
              SettlementsCompanion(
                id: const Value('s1'),
                roomId: const Value('g1'),
                amountCents: const Value(1250),
                currency: const Value('EUR'),
                fromUser: const Value('p-alex'),
                toUser: const Value('p-sam'),
                createdAt: Value(t1),
                updatedAt: Value(t1),
              ),
            );
            await MembersDao(db).upsertMemberLww(
              const MembersCompanion(
                groupId: Value('g1'),
                userId: Value('p-alex'),
                displayName: Value('Alex'),
                matrixId: Value('@alice:x.org'),
                status: Value('active'),
                updatedAt: Value(1000),
              ),
            );
          });
          final net = FakeMatrixNetwork();
          // The tile list is driven by a controller we refill from the DB's
          // tombstone-filtered query (Drift watch streams don't mix with the
          // widget-test fake clock) — so "disappears" reflects the real write.
          final ctrl = StreamController<List<SettlementModel>>();
          addTearDown(ctrl.close);

          await tester.pumpWidget(
            testApp(
              const ExpensesPage(roomId: 'g1'),
              overrides: [
                ...testOverrides(
                  isLoggedIn: true,
                  settlementsStream: ctrl.stream,
                ),
                participantNamesProvider.overrideWith((ref, g) => names),
                appDatabaseProvider.overrideWithValue(db),
                ledgerTransportProvider.overrideWith(
                  (ref) => net.clientFor('@alice:x.org'),
                ),
              ],
            ),
          );
          await tester.runAsync(
            () async => ctrl.add(await dao.getSettlementsForRoom('g1')),
          );
          await tester.pump();
          await tester.pump();
          // This device (@alice:x.org) is Alex → "You paid Sam" (G17).
          expect(find.text('You paid Sam'), findsOneWidget);

          await tester.tap(find.byTooltip('Settlement options'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          expect(find.text('Delete settlement?'), findsOneWidget);

          await tester.runAsync(() async {
            await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
            await eventually(
              () async => (await dao.getAllSettlementsForGroup(
                'g1',
              )).every((s) => s.deleted),
              tester: tester,
            );
            final all = await dao.getAllSettlementsForGroup('g1');
            expect(all.single.deleted, true);
            ctrl.add(await dao.getSettlementsForRoom('g1'));
          });
          await tester.pump();
          await tester.pump();

          expect(find.text('You paid Sam'), findsNothing);
          expect(find.textContaining('No expenses'), findsOneWidget);
        },
      );

      testWidgets('cancelling the settlement delete keeps it', (tester) async {
        await tester.pumpWidget(
          testApp(
            const ExpensesPage(roomId: _roomId),
            overrides: [
              ...testOverrides(
                isLoggedIn: true,
                settlements: [settlement('s1', t1)],
              ),
              participantNamesProvider.overrideWith((ref, g) => names),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byTooltip('Settlement options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Alex paid Sam'), findsOneWidget);
      });
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

/// Overrides [syncHealthProvider]: healthy, but @bob:y.org had no device.
class _NoDeviceSyncHealth extends SyncHealth {
  @override
  SyncHealthState build() =>
      const SyncHealthState(lastSuccessAt: 1, unreachablePeers: {'@bob:y.org'});
}
