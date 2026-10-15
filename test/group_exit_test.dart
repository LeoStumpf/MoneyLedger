/// G9: the group menu's Leave / Delete entry, its confirmation dialog (with
/// the informative "not settled up" warning) and the pure helpers behind it.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_provider.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_exit_dialog.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

MemberModel member(String id, String? mxid, {String status = 'active'}) =>
    MemberModel(
        groupId: 'g1',
        userId: id,
        displayName: id,
        matrixId: mxid,
        status: status,
        updatedAt: 1);

void main() {
  group('groupExitKind', () {
    test('leave when another claimed account is active', () {
      expect(groupExitKind([member(alice, alice), member(bob, bob)], alice),
          GroupExitKind.leave);
    });
    test('delete for a solo group with only local participants', () {
      expect(groupExitKind([member(alice, alice), member('p1', null)], alice),
          GroupExitKind.delete);
    });
    test('delete when the others are all removed', () {
      expect(
          groupExitKind(
              [member(alice, alice), member(bob, bob, status: 'removed')],
              alice),
          GroupExitKind.delete);
    });
    test('delete when we are no longer an active participant', () {
      expect(
          groupExitKind(
              [member(alice, alice, status: 'removed'), member(bob, bob)],
              alice),
          GroupExitKind.delete);
    });
  });

  group('unsettledWarning', () {
    const debts = [
      DebtEntry(from: 'me', to: 'x', cents: 1250, currency: 'EUR'),
      DebtEntry(from: 'y', to: 'me', cents: 300, currency: 'CHF'),
      DebtEntry(from: 'x', to: 'y', cents: 999, currency: 'EUR'),
    ];
    test('per-currency owe / owed', () {
      expect(unsettledWarning(debts, 'me'),
          'You still owe 12.50 EUR. You are still owed 3.00 CHF.');
    });
    test('null when settled or unknown participant', () {
      expect(unsettledWarning(debts.sublist(2), 'me'), isNull);
      expect(unsettledWarning(debts, null), isNull);
    });
  });

  Future<AppDatabase> seededDb({required bool withBob}) async {
    final db = openTestDatabase();
    await GroupsDao(db).upsertGroupLww(const GroupsCompanion(
        roomId: Value('g1'),
        name: Value('Trip'),
        currency: Value('EUR'),
        updatedAt: Value(1)));
    for (final id in [alice, if (withBob) bob]) {
      await MembersDao(db).upsertMemberLww(MembersCompanion(
          groupId: const Value('g1'),
          userId: Value(id),
          matrixId: Value(id),
          status: const Value('active'),
          updatedAt: const Value(1)));
    }
    return db;
  }

  Widget app(AppDatabase db, List<MemberModel> members, List<DebtEntry> debts) {
    final net = FakeMatrixNetwork();
    final router = GoRouter(
      initialLocation: '/groups/g1/expenses',
      routes: [
        GoRoute(
            path: '/groups',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('groups list')))),
        GoRoute(
            path: '/groups/:id/expenses',
            builder: (_, _) => const ExpensesPage(roomId: 'g1')),
      ],
    );
    return ProviderScope(
      overrides: [
        // Not testOverrides(): it already overrides groupMembersProvider.
        expensesForRoomProvider
            .overrideWith((ref, roomId) => Stream.value(const [])),
        settlementsForRoomProvider
            .overrideWith((ref, roomId) => Stream.value(const [])),
        balanceForRoomProvider.overrideWith((ref, roomId) => debts),
        groupSyncStatusProvider.overrideWith((ref, g) =>
            const GroupSyncStatus(pendingPeers: {}, minPeerInSyncAt: null)),
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(alice)),
        currentUserIdProvider.overrideWith((ref) => alice),
        groupMembersProvider
            .overrideWith((ref, g) => Stream.value(members)),
        currentParticipantProvider.overrideWith(
            (ref, g) => Future<MemberModel?>.value(members.first)),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('shared group: menu offers Leave; dialog warns about an '
      'unsettled balance; cancel keeps the group', (tester) async {
    final db = (await tester.runAsync(() => seededDb(withBob: true)))!;
    addTearDown(db.close);
    await tester.pumpWidget(app(
      db,
      [member(alice, alice), member(bob, bob)],
      const [DebtEntry(from: alice, to: bob, cents: 1250, currency: 'EUR')],
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.text('Delete group'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('Leave group'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('Leave group?'), findsOneWidget);
    expect(find.text('You still owe 12.50 EUR.'), findsOneWidget);
    expect(find.text('Export a CSV backup first'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Leave group?'), findsNothing);
    await tester.runAsync(() async {
      expect(await GroupsDao(db).getGroup('g1'), isNotNull);
    });
  });

  testWidgets('solo group: Delete purges it and returns to the groups list',
      (tester) async {
    final db = (await tester.runAsync(() => seededDb(withBob: false)))!;
    addTearDown(db.close);
    await tester.pumpWidget(app(db, [member(alice, alice)], const []));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Leave group'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('Delete group'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Delete group?'), findsOneWidget);
    expect(find.textContaining('still owe'), findsNothing,
        reason: 'settled: no warning');

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      expect(await GroupsDao(db).getGroup('g1'), isNull);
      expect(await MembersDao(db).getMembers('g1'), isEmpty);
      expect(await SettingsDao(db).leftGroup('g1'), isNotNull);
    });
    await tester.pumpAndSettle();
    expect(find.text('groups list'), findsOneWidget);
  });
}
