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
  });
}
