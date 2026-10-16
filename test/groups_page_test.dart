import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_ledger/core/background/background_sync_provider.dart';
import 'package:money_ledger/core/sync/self_recovery.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/features/balance/balance_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/models/login_flows_result.dart';

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

    testWidgets('settings sheet links to the About page', (tester) async {
      await tester.pumpWidget(
        testApp(const GroupsPage(), overrides: testOverrides(isLoggedIn: true)),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aboutTile')), findsOneWidget);
      expect(find.text('About MoneyLedger'), findsOneWidget);
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

    testWidgets('sync settings: Android shows the background-sync switch', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          overrides: [
            ...testOverrides(isLoggedIn: true),
            backgroundSyncSupportedProvider.overrideWithValue(true),
            backgroundSyncEnabledProvider.overrideWith(
              (_) => Stream.value(true),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Background sync'), findsOneWidget);
      final sw = tester.widget<SwitchListTile>(
        find.byKey(const Key('backgroundSyncSwitch')),
      );
      expect(sw.value, isTrue);
    });

    testWidgets('sync settings: web explains there is no background sync', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          overrides: [
            ...testOverrides(isLoggedIn: true),
            backgroundSyncSupportedProvider.overrideWithValue(false),
            backgroundSyncEnabledProvider.overrideWith(
              (_) => Stream.value(true),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('No background sync here'), findsOneWidget);
      expect(find.byKey(const Key('backgroundSyncSwitch')), findsNothing);
    });

    testWidgets('shows logout icon button in app bar', (tester) async {
      await tester.pumpWidget(
        testApp(const GroupsPage(), overrides: testOverrides(isLoggedIn: true)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.logout), findsOneWidget);
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

    // G29: signing out asks first and explains the data stays on the device.
    for (final confirm in [false, true]) {
      testWidgets('sign out asks for confirmation (confirm: $confirm)', (
        tester,
      ) async {
        final spy = _SpyAuth();
        await tester.pumpWidget(
          testApp(
            const GroupsPage(),
            overrides: [
              ...testOverrides(isLoggedIn: true),
              authProvider.overrideWith(() => spy),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byIcon(Icons.logout));
        await tester.pumpAndSettle();
        expect(find.text('Sign out?'), findsOneWidget);
        expect(find.textContaining('stay on this device'), findsOneWidget);
        expect(spy.logouts, 0, reason: 'nothing happens before confirming');

        await tester.tap(
          confirm
              ? find.widgetWithText(FilledButton, 'Sign out')
              : find.text('Cancel'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Sign out?'), findsNothing);
        expect(spy.logouts, confirm ? 1 : 0);
      });
    }
  });

  testWidgets('a failed sign-out is reported, not swallowed (G15)', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        const GroupsPage(),
        overrides: [
          ...testOverrides(isLoggedIn: true),
          authProvider.overrideWith(_FailingLogoutAuth.new),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Failed: Bad state: server unreachable'), findsOneWidget);
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

class _FailingLogoutAuth extends AuthNotifier {
  @override
  Future<void> logout() async {
    state = AsyncError(StateError('server unreachable'), StackTrace.current);
  }
}

class _SpyAuth extends AuthNotifier {
  int logouts = 0;

  @override
  Future<void> logout() async => logouts++;
}

class _Restoring extends SelfRecovery {
  @override
  bool build() => true;
}
