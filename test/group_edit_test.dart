/// G10: the "Edit group" dialog (name + default currency) and its entry in the
/// expenses page overflow menu; G26: the read-only state once another member
/// removed us.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/features/balance/balance_provider.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_edit_dialog.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';
import 'helpers/l10n.dart';
import 'helpers/eventually.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

MemberModel member(String mxid, {String status = 'active'}) => MemberModel(
  groupId: 'g1',
  userId: mxid,
  displayName: mxid,
  matrixId: mxid,
  status: status,
  updatedAt: 1,
);

void main() {
  group('showEditGroupDialog', () {
    /// Opens the dialog over a host page (result not needed here).
    Future<void> open(
      WidgetTester tester, {
      String name = 'Trip',
      String currency = 'EUR',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showEditGroupDialog(
                  context,
                  name: name,
                  currency: currency,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('prefilled; says currency only affects new expenses; '
        'returns the edited values', (tester) async {
      ({String name, String currency})? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await showEditGroupDialog(
                  context,
                  name: 'Trip',
                  currency: 'EUR',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit group'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Trip'), findsOneWidget);
      expect(
        find.textContaining('Only applies to new expenses'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextFormField), '  Ski trip ');
      await tester.tap(find.text('EUR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CHF').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Edit group'), findsNothing);
      expect(result, (name: 'Ski trip', currency: 'CHF'));
    });

    testWidgets('an empty name is rejected; cancel returns null', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      expect(find.text('Edit group'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Edit group'), findsNothing);
    });

    testWidgets('a currency outside the list stays selectable', (tester) async {
      await open(tester, currency: 'SEK');
      expect(find.text('SEK'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('expenses page', () {
    late FakeMatrixNetwork net;

    Future<AppDatabase> seededDb() async {
      final db = openTestDatabase();
      await GroupsDao(db).upsertGroupLww(
        const GroupsCompanion(
          roomId: Value('g1'),
          name: Value('Trip'),
          currency: Value('EUR'),
          updatedAt: Value(1),
        ),
      );
      for (final id in [alice, bob]) {
        await MembersDao(db).upsertMemberLww(
          MembersCompanion(
            groupId: const Value('g1'),
            userId: Value(id),
            matrixId: Value(id),
            status: const Value('active'),
            updatedAt: const Value(1),
          ),
        );
      }
      return db;
    }

    Widget app(
      AppDatabase db,
      List<MemberModel> members, {
      List<ExpenseModel> expenses = const [],
    }) {
      net = FakeMatrixNetwork();
      net.clientFor(bob);
      final router = GoRouter(
        initialLocation: '/groups/g1/expenses',
        routes: [
          GoRoute(
            path: '/groups',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('groups list'))),
          ),
          GoRoute(
            path: '/groups/:id/expenses',
            builder: (_, _) => const ExpensesPage(roomId: 'g1'),
          ),
        ],
      );
      return ProviderScope(
        overrides: [
          ...signingUiOverrides(),
          expensesForRoomProvider.overrideWith(
            (ref, roomId) => Stream.value(expenses),
          ),
          settlementsForRoomProvider.overrideWith(
            (ref, roomId) => Stream.value(const []),
          ),
          balanceForRoomProvider.overrideWith((ref, roomId) => const []),
          groupSyncStatusProvider.overrideWith(
            (ref, g) =>
                const GroupSyncStatus(pendingPeers: {}, minPeerInSyncAt: null),
          ),
          appDatabaseProvider.overrideWithValue(db),
          ledgerGroupsProvider.overrideWith(
            (ref) => Stream.value(const [
              GroupModel(roomId: 'g1', name: 'Trip', currency: 'EUR'),
            ]),
          ),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(alice)),
          currentUserIdProvider.overrideWith((ref) => alice),
          groupMembersProvider.overrideWith((ref, g) => Stream.value(members)),
          currentParticipantProvider.overrideWith(
            (ref, g) => Future<MemberModel?>.value(members.first),
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          routerConfig: router,
        ),
      );
    }

    testWidgets('Edit group renames + changes currency and relays the meta', (
      tester,
    ) async {
      final db = (await tester.runAsync(seededDb))!;
      addTearDown(db.close);
      await tester.pumpWidget(app(db, [member(alice), member(bob)]));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Edit group'));
        await eventually(
          () =>
              find.widgetWithText(TextFormField, 'Trip').evaluate().isNotEmpty,
          tester: tester,
        );
      });
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Trip'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Ski trip');
      await tester.tap(find.text('EUR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await eventually(
          () => net.sent.any((s) => s.type == groupMetaEventType),
          tester: tester,
        );
      });
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final g = (await GroupsDao(db).getGroup('g1'))!;
        expect(g.name, 'Ski trip');
        expect(g.currency, 'USD');
        expect(g.updatedAt, greaterThan(1));
      });
      final meta = net.sent.where((s) => s.type == groupMetaEventType).single;
      expect(meta.targets, {alice, bob});
      expect(meta.content['name'], 'Ski trip');
      expect(meta.content['currency'], 'USD');
    });

    testWidgets('removed by another member: banner, read-only, no edit', (
      tester,
    ) async {
      final db = (await tester.runAsync(seededDb))!;
      addTearDown(db.close);
      await tester.pumpWidget(
        app(
          db,
          [member(alice, status: 'removed'), member(bob)],
          expenses: const [
            ExpenseModel(
              id: 'e1',
              roomId: 'g1',
              description: 'Dinner',
              amountCents: 4000,
              currency: 'EUR',
              paidBy: alice,
              splitsJson: '{"$alice":2000,"$bob":2000}',
              createdAt: 1,
              updatedAt: 1,
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // FAB exit animation

      expect(
        find.textContaining('You were removed from this group'),
        findsOneWidget,
      );
      expect(find.text('Delete from this device'), findsOneWidget);
      expect(find.text('Add expense'), findsNothing);
      // History stays readable, but can't be edited / deleted.
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.byTooltip('Expense options'), findsNothing);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      final addMember = tester.widget<PopupMenuItem<Object?>>(
        find.ancestor(
          of: find.text('Add person'),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      );
      expect(addMember.enabled, isFalse);
      final edit = tester.widget<PopupMenuItem<Object?>>(
        find.ancestor(
          of: find.text('Edit group'),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      );
      expect(edit.enabled, isFalse);
      expect(find.text('Delete group'), findsOneWidget);
    });
  });
}
