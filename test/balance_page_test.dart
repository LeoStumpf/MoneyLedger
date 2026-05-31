import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_page.dart';

import 'helpers/test_providers.dart';

const _roomId = '!test:matrix.org';

void main() {
  group('BalancePage', () {
    testWidgets('shows "All settled up!" when there are no debts',
        (tester) async {
      await tester.pumpWidget(testApp(
        const BalancePage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true, debts: []),
      ));
      await tester.pump();

      expect(find.textContaining('All settled up'), findsOneWidget);
    });

    testWidgets('renders debt cards when debts exist', (tester) async {
      final debts = [
        const DebtEntry(
            from: '@bob:matrix.org', to: '@alice:matrix.org', cents: 2100),
        const DebtEntry(
            from: '@carol:matrix.org', to: '@alice:matrix.org', cents: 1050),
      ];

      await tester.pumpWidget(testApp(
        const BalancePage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true, debts: debts),
      ));
      await tester.pump();

      expect(find.text('@bob:matrix.org'), findsOneWidget);
      expect(find.text('@carol:matrix.org'), findsOneWidget);
    });

    testWidgets('shows "Balance" AppBar title', (tester) async {
      await tester.pumpWidget(testApp(
        const BalancePage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true),
      ));
      await tester.pump();

      expect(find.text('Balance'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows arrow_forward icon for each debt', (tester) async {
      final debts = [
        const DebtEntry(
            from: '@bob:matrix.org', to: '@alice:matrix.org', cents: 500),
      ];

      await tester.pumpWidget(testApp(
        const BalancePage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true, debts: debts),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });
  });
}
