import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/models/expense_model.dart';

import 'helpers/test_providers.dart';

const _roomId = '!test:matrix.org';

void main() {
  group('ExpensesPage', () {
    testWidgets('shows empty-state text when no expenses', (tester) async {
      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true, expenses: []),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('No expenses'), findsOneWidget);
    });

    testWidgets('shows FAB to add an expense', (tester) async {
      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Add expense'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows balance icon button in app bar', (tester) async {
      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.balance), findsOneWidget);
    });

    testWidgets('renders expense list tiles when expenses exist',
        (tester) async {
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

      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true, expenses: expenses),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text("Dinner at Luigi's"), findsOneWidget);
      expect(find.text('Taxi home'), findsOneWidget);
      expect(find.text('42.00 EUR'), findsOneWidget);
      expect(find.text('15.00 EUR'), findsOneWidget);
    });

    testWidgets('shows "Expenses" in the app bar', (tester) async {
      await tester.pumpWidget(testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: testOverrides(isLoggedIn: true),
      ));
      await tester.pump();

      expect(find.text('Expenses'), findsOneWidget);
    });
  });
}
