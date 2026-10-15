import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/member_model.dart';

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
            from: '@bob:matrix.org', to: '@alice:matrix.org', cents: 2100, currency: 'EUR'),
        const DebtEntry(
            from: '@carol:matrix.org', to: '@alice:matrix.org', cents: 1050, currency: 'EUR'),
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
            from: '@bob:matrix.org', to: '@alice:matrix.org', cents: 500, currency: 'EUR'),
      ];

      await tester.pumpWidget(testApp(
        const BalancePage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true, debts: debts),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    // G26: a participant removed by another member can't record settlements.
    for (final status in ['active', 'removed']) {
      testWidgets('own debt is settleable only while active ($status)',
          (tester) async {
        const me = '@bob:matrix.org';
        await tester.pumpWidget(testApp(
          const BalancePage(roomId: _roomId),
          overrides: [
            ...testOverrides(isLoggedIn: true, debts: const [
              DebtEntry(
                  from: me, to: '@alice:matrix.org', cents: 500, currency: 'EUR'),
            ]),
            currentParticipantProvider.overrideWith((ref, g) =>
                Future<MemberModel?>.value(MemberModel(
                    groupId: g,
                    userId: me,
                    matrixId: me,
                    status: status,
                    updatedAt: 1))),
          ],
        ));
        await tester.pump();
        await tester.pump();

        final tile = tester.widget<ListTile>(find.byType(ListTile));
        expect(tile.onTap != null, status == 'active');
      });
    }
  });
}
