import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/balance/balance_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/models/login_flows_result.dart';

import 'helpers/test_providers.dart';

void main() {
  group('GroupsPage', () {
    testWidgets('shows empty-state text when user has no groups',
        (tester) async {
      await tester.pumpWidget(testApp(
        const GroupsPage(),
        overrides: testOverrides(isLoggedIn: true),
      ));
      await tester.pump(); // build
      await tester.pump(); // stream emits []

      expect(find.textContaining('No groups yet'), findsOneWidget);
    });

    testWidgets('shows FAB to create a new group', (tester) async {
      await tester.pumpWidget(testApp(
        const GroupsPage(),
        overrides: testOverrides(isLoggedIn: true),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('New group'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows logout icon button in app bar', (tester) async {
      await tester.pumpWidget(testApp(
        const GroupsPage(),
        overrides: testOverrides(isLoggedIn: true),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('shows loading indicator while groups are loading',
        (tester) async {
      // Replace the default emptyGroupsOverride with one that never emits.
      await tester.pumpWidget(testApp(
        const GroupsPage(),
        overrides: [
          isLoggedInProvider.overrideWith((ref) => true),
          loadingGroupsOverride(), // never emits → stays AsyncLoading
          loginFlowsProvider.overrideWith(
              (ref, input) async => LoginFlowsResult.empty),
          expensesForRoomProvider
              .overrideWith((ref, roomId) => Stream.value([])),
          settlementsForRoomProvider
              .overrideWith((ref, roomId) => Stream.value([])),
          balanceForRoomProvider.overrideWith((ref, roomId) => []),
        ],
      ));
      await tester.pump(); // one pump — stream never emits, stays loading

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows "Groups" in the app bar', (tester) async {
      await tester.pumpWidget(testApp(
        const GroupsPage(),
        overrides: testOverrides(isLoggedIn: true),
      ));
      await tester.pump();

      expect(find.text('Groups'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    // G29: signing out asks first and explains the data stays on the device.
    for (final confirm in [false, true]) {
      testWidgets('sign out asks for confirmation (confirm: $confirm)',
          (tester) async {
        final spy = _SpyAuth();
        await tester.pumpWidget(testApp(
          const GroupsPage(),
          overrides: [
            ...testOverrides(isLoggedIn: true),
            authProvider.overrideWith(() => spy),
          ],
        ));
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byIcon(Icons.logout));
        await tester.pumpAndSettle();
        expect(find.text('Sign out?'), findsOneWidget);
        expect(find.textContaining('stay on this device'), findsOneWidget);
        expect(spy.logouts, 0, reason: 'nothing happens before confirming');

        await tester.tap(confirm
            ? find.widgetWithText(FilledButton, 'Sign out')
            : find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Sign out?'), findsNothing);
        expect(spy.logouts, confirm ? 1 : 0);
      });
    }
  });
}

class _SpyAuth extends AuthNotifier {
  int logouts = 0;

  @override
  Future<void> logout() async => logouts++;
}
