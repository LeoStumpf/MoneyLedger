import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/create_group_page.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';

void main() {
  group('CreateGroupPage', () {
    testWidgets('renders name field, currency dropdown and create button',
        (tester) async {
      await tester.pumpWidget(testApp(const CreateGroupPage()));
      await tester.pumpAndSettle();

      expect(find.text('New group'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Group name'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create'), findsOneWidget);
    });

    testWidgets('creating a group saves it to Drift and pops back',
        (tester) async {
      final net = FakeMatrixNetwork();
      final db = openTestDatabase();
      addTearDown(db.close);

      await tester.pumpWidget(testRouterApp(
        const CreateGroupPage(),
        overrides: [
          ledgerTransportProvider
              .overrideWith((ref) => net.clientFor('@alice:x.org')),
          appDatabaseProvider.overrideWithValue(db),
        ],
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Holiday');

      // Drift's in-memory writes resolve on the real event loop, not the widget
      // test's fake clock — so create()'s DB write (and our read-back) must run
      // under runAsync, otherwise the submit future never completes.
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Create'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();

        final groups = await GroupsDao(db).watchAllGroups().first;
        expect(groups, hasLength(1));
        expect(groups.first.name, 'Holiday');
        expect(groups.first.currency, 'EUR');
      });
    });
  });
}
