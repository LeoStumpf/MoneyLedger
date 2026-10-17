import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/sync/self_recovery.dart';
import 'package:money_ledger/core/sync/sync_health.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/features/balance/balance_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/features/settings/settings_page.dart';
import 'package:money_ledger/models/login_flows_result.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

void main() {
  group('GroupsPage', () {
    testWidgets('shows empty-state text when user has no groups', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(const GroupsPage(), overrides: testOverrides(isLoggedIn: true)),
      );
      await tester.pump(); // build
      await tester.pump(); // stream emits []

      expect(find.textContaining('No groups yet'), findsOneWidget);
    });

    testWidgets('German locale: title, empty state and FAB (G12)', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          locale: const Locale('de'),
          overrides: testOverrides(isLoggedIn: true),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Gruppen'), findsOneWidget);
      expect(find.textContaining('Noch keine Gruppen'), findsOneWidget);
      expect(find.text('Neue Gruppe'), findsOneWidget);
      expect(find.byTooltip('Einstellungen'), findsOneWidget);
    });

    testWidgets('G35: refused legacy records show a dismissible hint', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          overrides: [
            ...testOverrides(isLoggedIn: true),
            syncHealthProvider.overrideWith(_LegacyRefusedHealth.new),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('legacyRefusalBanner')), findsOneWidget);
      expect(find.text("Some data couldn't be received"), findsOneWidget);
      expect(
        find.textContaining('@alice:x sent 3 entries of “Old flat”'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('legacyRefusalDismiss')));
      await tester.pump();
      expect(find.byKey(const Key('legacyRefusalBanner')), findsNothing);
    });

    testWidgets('shows FAB to create a new group', (tester) async {
      await tester.pumpWidget(
        testApp(const GroupsPage(), overrides: testOverrides(isLoggedIn: true)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('New group'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    // G65 (U21): only the settings gear (and local mode's chip) stay in the
    // app bar — CSV import and sign-out moved to the settings page.
    testWidgets('app bar: settings only, no sign-out / CSV icons', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(const GroupsPage(), overrides: testOverrides(isLoggedIn: true)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('settingsButton')), findsOneWidget);
      final bar = find.byType(AppBar);
      expect(
        find.descendant(of: bar, matching: find.byIcon(Icons.logout)),
        findsNothing,
      );
      expect(
        find.descendant(of: bar, matching: find.byIcon(Icons.upload_file)),
        findsNothing,
      );
      // The empty state keeps its own Import CSV button.
      expect(find.text('Import CSV'), findsOneWidget);
      expect(find.byTooltip('Sign out'), findsNothing);
    });

    testWidgets('the gear opens the settings page (G65)', (tester) async {
      final router = GoRouter(
        initialLocation: '/groups',
        routes: [
          GoRoute(path: '/groups', builder: (_, _) => const GroupsPage()),
          GoRoute(
            path: kSettingsLocation,
            builder: (_, _) => const SettingsPage(),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [...testOverrides(isLoggedIn: true)],
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.byKey(const Key('signOutTile')), findsOneWidget);
    });

    testWidgets('shows loading indicator while groups are loading', (
      tester,
    ) async {
      // Replace the default emptyGroupsOverride with one that never emits.
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          overrides: [
            isLoggedInProvider.overrideWith((ref) => true),
            loadingGroupsOverride(), // never emits → stays AsyncLoading
            loginFlowsProvider.overrideWith(
              (ref, input) async => LoginFlowsResult.empty,
            ),
            expensesForRoomProvider.overrideWith(
              (ref, roomId) => Stream.value([]),
            ),
            settlementsForRoomProvider.overrideWith(
              (ref, roomId) => Stream.value([]),
            ),
            balanceForRoomProvider.overrideWith((ref, roomId) => []),
          ],
        ),
      );
      await tester.pump(); // one pump — stream never emits, stays loading

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows "Groups" in the app bar', (tester) async {
      await tester.pumpWidget(
        testApp(const GroupsPage(), overrides: testOverrides(isLoggedIn: true)),
      );
      await tester.pump();

      expect(find.text('Groups'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('GroupsPage first-login recovery (G30)', () {
    testWidgets(
      'shows "Restoring your groups…" while recovery is outstanding',
      (tester) async {
        await tester.pumpWidget(
          testApp(
            const GroupsPage(),
            overrides: [
              ...testOverrides(isLoggedIn: true),
              selfRecoveryProvider.overrideWith(_Restoring.new),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.textContaining('Restoring your groups'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.textContaining('No groups yet'), findsNothing);
      },
    );

    testWidgets('restored groups are listed even while still "restoring"', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          overrides: [
            isLoggedInProvider.overrideWith((ref) => true),
            ledgerGroupsProvider.overrideWith(
              (_) => Stream.value(const [
                GroupModel(roomId: 'g1', name: 'Trip', currency: 'EUR'),
              ]),
            ),
            selfRecoveryProvider.overrideWith(_Restoring.new),
            // G16: no archived groups (no drift stream in widget tests).
            groupArchivesProvider.overrideWith((_) => Stream.value(const {})),
            // The group card's overview reads these (G17).
            groupMembersProvider.overrideWith(
              (ref, g) => Stream.value(const []),
            ),
            expensesForRoomProvider.overrideWith((ref, g) => Stream.value([])),
            settlementsForRoomProvider.overrideWith(
              (ref, g) => Stream.value([]),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Trip'), findsOneWidget);
      expect(find.textContaining('Restoring your groups'), findsNothing);
    });

    testWidgets('falls back to the empty state once recovery is over', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          overrides: [
            ...testOverrides(isLoggedIn: true),
            selfRecoveryProvider.overrideWith(_Restoring.new),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      final element = tester.element(find.byType(GroupsPage));
      ProviderScope.containerOf(
        element,
      ).read(selfRecoveryProvider.notifier).finish();
      await tester.pump();

      expect(find.textContaining('Restoring your groups'), findsNothing);
      expect(find.textContaining('No groups yet'), findsOneWidget);
    });
  });
}

class _Restoring extends SelfRecovery {
  @override
  bool build() => true;
}

class _LegacyRefusedHealth extends SyncHealth {
  @override
  SyncHealthState build() => const SyncHealthState(
    legacyRefusals: {
      'old': LegacyRefusal(
        groupId: 'old',
        groupName: 'Old flat',
        relayedBy: '@alice:x',
        count: 3,
      ),
    },
  );
}
