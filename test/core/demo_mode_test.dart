/// G15 offline demo mode: the seeded dataset and a smoke boot of the real
/// `App` with the demo overrides (in-memory DB instead of the demo file).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/models/group_archive.dart';
import 'package:money_ledger/app.dart';
import 'package:money_ledger/core/background/background_sync.dart'
    show backgroundSyncSupported;
import 'package:money_ledger/core/background/background_sync_provider.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/database/daos/sync_states_dao.dart';
import 'package:money_ledger/core/demo/demo_auth_gateway.dart';
import 'package:money_ledger/core/demo/demo_mode.dart';
import 'package:money_ledger/core/demo/demo_overrides.dart';
import 'package:money_ledger/core/demo/demo_seed.dart';
import 'package:money_ledger/core/demo/demo_transport.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/history/group_history.dart';
import 'package:money_ledger/models/expense_date.dart';

import '../helpers/eventually.dart';
import '../helpers/in_memory_database.dart';

void main() {
  test('demo mode is off unless OFFLINE_DEMO is defined', () {
    expect(kOfflineDemo, isFalse);
  });

  group('seedDemoLedger', () {
    test('four groups, real names, several currencies, all in sync', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final now = DateTime(2026, 10, 16, 12);
      await seedDemoLedger(db, now: now);

      final groups = await GroupsDao(db).getAllGroups();
      expect(groups.map((g) => g.name).toSet(), {
        'Lisbon trip',
        'Flat share',
        'Ski weekend',
        'Board game night',
      });

      final currencies = <String>{};
      var settlementCount = 0;
      for (final g in groups) {
        final expenses = await ExpensesDao(db).getExpensesForRoom(g.roomId);
        final settlements = await ExpensesDao(
          db,
        ).getSettlementsForRoom(g.roomId);
        expect(expenses, isNotEmpty);
        settlementCount += settlements.length;
        for (final e in expenses) {
          currencies.add(e.currency);
          final split = splitsOf(e);
          expect(
            split.values.fold(0, (a, b) => a + b),
            e.amountCents,
            reason: '${e.description}: split sums to the amount',
          );
          expect(e.createdAt, lessThan(now.millisecondsSinceEpoch));
          expect(
            e.createdAt,
            greaterThan(
              now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
            ),
          );
        }
        // Every participant in the ledger is a member of the group.
        final ids = {
          for (final m in await MembersDao(db).getMembers(g.roomId)) m.userId,
        };
        for (final e in expenses) {
          expect(ids, containsAll({e.paidBy, ...splitsOf(e).keys}));
        }
        // Sync icons show "synced" for every group.
        final members = await MembersDao(db).getMembers(g.roomId);
        final states = await SyncStatesDao(db).getSyncStates(g.roomId);
        final status = computeSyncStatus(
          selfId: kDemoUserId,
          members: members,
          peerInSyncAt: {for (final s in states) s.userId: s.lastInSyncAt},
          maxRecordUpdatedAt: expenses
              .map((e) => e.updatedAt)
              .fold(0, (a, b) => a > b ? a : b),
        );
        expect(status.synced, isTrue, reason: g.name);
      }
      expect(currencies, containsAll(['EUR', 'CHF']));
      expect(settlementCount, greaterThanOrEqualTo(3));
      expect(await SettingsDao(db).watchOnboardingSeen().first, isTrue);

      // G16: categorised expenses (README screenshots), a note, and the
      // settled-up board game night archived — its fingerprint still holds.
      final all = [
        for (final g in groups)
          ...await ExpensesDao(db).getExpensesForRoom(g.roomId),
      ];
      expect(all.where((e) => e.category != null).length, all.length);
      expect(all.where((e) => e.note != null), isNotEmpty);
      final archives = await SettingsDao(db).watchArchivedGroups().first;
      expect(archives.keys, ['demo-group-games']);
      expect(
        archives['demo-group-games']!.holdsFor(
          ledgerFingerprint(
            await ExpensesDao(db).getAllExpensesForGroup('demo-group-games'),
            await ExpensesDao(db).getAllSettlementsForGroup('demo-group-games'),
          ),
        ),
        isTrue,
      );
    });

    test('screenshot extras: custom category, back-dated expense and '
        'payment (G47 / G49 / G60)', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final now = DateTime(2026, 10, 16, 12);
      await seedDemoLedger(db, now: now);
      final dao = ExpensesDao(db);

      final lisbon = (await GroupsDao(db).getGroup('demo-group-lisbon'))!;
      expect(lisbon.categories.map((c) => c.name), ['Souvenirs']);
      final custom = lisbon.categories.single.id;
      expect(
        (await dao.getExpensesForRoom(
          'demo-group-lisbon',
        )).where((e) => e.category == custom),
        hasLength(1),
      );

      DateTime createdDay(int ms) =>
          dayOf(DateTime.fromMillisecondsSinceEpoch(ms));
      final dated = [
        for (final g in await GroupsDao(db).getAllGroups())
          ...await dao.getExpensesForRoom(g.roomId),
      ].where((e) => e.date != null).toList();
      expect(dated, hasLength(1));
      expect(
        dated.single.displayDay,
        isNot(createdDay(dated.single.createdAt)),
      );
      expect(dated.single.displayDay.isBefore(dayOf(now)), isTrue);

      final datedPayments = [
        for (final g in await GroupsDao(db).getAllGroups())
          ...await dao.getSettlementsForRoom(g.roomId),
      ].where((s) => s.date != null).toList();
      expect(datedPayments, hasLength(1));
      expect(
        datedPayments.single.displayDay,
        isNot(createdDay(datedPayments.single.createdAt)),
      );
    });

    test('G48: every record has history; the reset page offers restore '
        'points incl. an edit and a deletion', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await seedDemoLedger(db, now: DateTime(2026, 10, 16, 12));
      final history = HistoryDao(db);
      final dao = ExpensesDao(db);
      for (final g in await GroupsDao(db).getAllGroups()) {
        final entries = await history.entriesForGroup(g.roomId);
        final keys = {for (final e in entries) '${e.kind.wire}|${e.recordId}'};
        for (final e in await dao.getAllExpensesForGroup(g.roomId)) {
          expect(keys, contains('expense|${e.id}'));
        }
        for (final s in await dao.getAllSettlementsForGroup(g.roomId)) {
          expect(keys, contains('settlement|${s.id}'));
        }
        // Each record's newest history entry is its stored version.
        final newestAt = <String, int>{
          for (final e in entries) '${e.kind.wire}|${e.recordId}': e.updatedAt,
        };
        for (final e in await dao.getAllExpensesForGroup(g.roomId)) {
          expect(newestAt['expense|${e.id}'], e.updatedAt);
        }
        final batches = changeBatches(entries, me: kDemoUserId);
        expect(batches.last.base, isTrue, reason: g.name);
        expect(
          batches.where((b) => b.resettable),
          isNotEmpty,
          reason: '${g.name}: the reset page has restore points',
        );
        // Resetting to before the newest batch is a sensible plan.
        final newest = batches.firstWhere((b) => b.resettable);
        final plan = planGroupReset(
          groupId: g.roomId,
          beforeId: newest.firstId,
          entries: entries,
          expenses: await dao.getAllExpensesForGroup(g.roomId),
          settlements: await dao.getAllSettlementsForGroup(g.roomId),
          meta: g,
        );
        expect(plan.isEmpty, isFalse, reason: g.name);
        expect(plan.skipped, 0);
      }

      final lisbon = changeBatches(
        await history.entriesForGroup('demo-group-lisbon'),
        me: kDemoUserId,
      );
      expect(lisbon.where((b) => b.deleted == 1), hasLength(1));
      final flat = changeBatches(
        await history.entriesForGroup('demo-group-flat'),
        me: kDemoUserId,
      );
      expect(flat.where((b) => b.changed == 1), hasLength(1));
      expect(flat.where((b) => b.byMe), isNotEmpty);
    });

    test('reseeding replaces the data instead of duplicating it', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await seedDemoLedger(db);
      await seedDemoLedger(db);
      expect(await GroupsDao(db).getAllGroups(), hasLength(4));
    });
  });

  test('G79: demo restore points live in memory on native (one store per '
      'DB), none on the web — like the real platform', () async {
    final native = demoSnapshotStores(web: false);
    final a = native(kDemoDatabaseName)!;
    await a.write('2026-10-18.json', '{}');
    expect(identical(native(kDemoDatabaseName), a), isTrue);
    expect(await native(kDemoDatabaseName)!.list(), ['2026-10-18.json']);
    expect(identical(native('other'), a), isFalse);
    expect(demoSnapshotStores(web: true)(kDemoDatabaseName), isNull);
  });

  test("G79: the demo shows the platform's background-sync setting", () {
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    expect(c.read(backgroundSyncSupportedProvider), backgroundSyncSupported);
  });

  test('demo fakes: signed in as Anna; sends reach peers, not self', () async {
    final auth = DemoAuthGateway();
    expect(auth.userId, kDemoUserId);
    await auth.logout();
    expect(auth.isLoggedIn, isFalse);
    await auth.loginWithPassword(
      homeserver: 'https://example.org',
      username: 'x',
      password: 'y',
    );
    expect(auth.userId, kDemoUserId);

    final t = DemoTransport(kDemoUserId);
    final r = await t.sendToUsers(
      {kDemoUserId, '@ben:example.org'},
      digestEventType,
      const {},
    );
    expect(r.deviceCount, 1);
    expect(r.unreachableUsers, isEmpty);
    expect(
      (await t.sendToUsers(
        {kDemoUserId},
        resyncRequestEventType,
        const {},
      )).deviceCount,
      0,
      reason: 'no other own device: new-device recovery ends at once',
    );
  });

  testWidgets('the demo app boots signed in, straight to the groups list', (
    tester,
  ) async {
    // Closed by appDatabaseProvider's onDispose when the container is disposed.
    final db = openTestDatabaseWithHook((db) => seedDemoLedger(db));
    // An external container, disposed after the test body (outside the fake
    // clock), like the real `main()` — drift's stream-close timers then don't
    // trip the pending-timer check.
    final container = ProviderContainer(
      overrides: demoOverrides(openDatabase: () => db),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    // Drift + the auth/onboarding chain resolve on the real event loop.
    await tester.runAsync(
      () => eventually(
        () => find.text('Lisbon trip').evaluate().isNotEmpty,
        tester: tester,
      ),
    );
    await tester.pump();
    expect(find.text('Lisbon trip'), findsOneWidget);
    expect(find.text('Flat share'), findsOneWidget);
    expect(find.text('Ski weekend'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
