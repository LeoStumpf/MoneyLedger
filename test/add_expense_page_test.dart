import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/models/expense_model.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';

void main() {
  group('AddExpensePage', () {
    // Seeds a roomless group 'g1' (CHF) with alice + bob as active members in a
    // shared in-memory DB, and returns it plus the fake network.
    Future<(AppDatabase, FakeMatrixNetwork)> seedGroup() async {
      final db = openTestDatabase();
      await GroupsDao(db).upsertGroupLww(const GroupsCompanion(
          roomId: Value('g1'),
          name: Value('Trip'),
          currency: Value('CHF'),
          updatedAt: Value(1000)));
      final memberDao = MembersDao(db);
      for (final u in ['@alice:x.org', '@bob:x.org']) {
        await memberDao.upsertMemberLww(MembersCompanion(
          groupId: const Value('g1'),
          userId: Value(u),
          status: const Value('active'),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ));
      }
      return (db, FakeMatrixNetwork());
    }

    testWidgets('renders the form with the group currency and member count',
        (tester) async {
      final (db, net) = await seedGroup();

      await tester.pumpWidget(testApp(
        const AddExpensePage(roomId: 'g1'),
        overrides: [
          appDatabaseProvider.overrideWith((ref) => db),
          ledgerTransportProvider
              .overrideWith((ref) => net.clientFor('@alice:x.org')),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Description'), findsOneWidget);
      expect(find.textContaining('Split equally among 2 member'),
          findsOneWidget);
      expect(find.text('CHF'), findsWidgets); // amount suffix
    });

    testWidgets('submitting relays the expense to members and pops back',
        (tester) async {
      final (db, net) = await seedGroup();
      final bob = net.clientFor('@bob:x.org');
      final received = <TransportMessage>[];
      bob.onMessage.listen(received.add);

      await tester.pumpWidget(testRouterApp(
        const AddExpensePage(roomId: 'g1'),
        overrides: [
          appDatabaseProvider.overrideWith((ref) => db),
          ledgerTransportProvider
              .overrideWith((ref) => net.clientFor('@alice:x.org')),
        ],
      ));
      await tester.pumpAndSettle(); // navigate + load members

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Description'), 'Pizza');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount'), '20');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      // Bounded pumps rather than pumpAndSettle: the in-button progress spinner
      // is a perpetual animation, so pumpAndSettle would never return. (Don't
      // use net.settle() here — its Future.delayed never fires under the
      // widget-test fake clock; pumping drains the microtask delivery instead.)
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      expect(received, hasLength(1));
      expect(received.first.type, expenseEventType);
      expect(received.first.content['description'], 'Pizza');
      expect(received.first.content['amount'], 2000);
      // Split equally across the two members.
      expect(received.first.content['split'],
          {'@alice:x.org': 1000, '@bob:x.org': 1000});
    });

    testWidgets('edit mode prefills the form and saves as the same record',
        (tester) async {
      final (db, net) = await seedGroup();
      final bob = net.clientFor('@bob:x.org');
      final received = <TransportMessage>[];
      bob.onMessage.listen(received.add);

      const initial = ExpenseModel(
        id: 'e1',
        roomId: 'g1',
        description: 'Dinner',
        amountCents: 4200,
        currency: 'CHF',
        paidBy: '@alice:x.org',
        splitsJson: '{"@alice:x.org":2100,"@bob:x.org":2100}',
        createdAt: 1000,
        updatedAt: 1000,
      );

      await tester.pumpWidget(testRouterApp(
        const AddExpensePage(roomId: 'g1', initial: initial),
        overrides: [
          appDatabaseProvider.overrideWith((ref) => db),
          ledgerTransportProvider
              .overrideWith((ref) => net.clientFor('@alice:x.org')),
        ],
      ));
      await tester.pumpAndSettle();

      // Prefilled from the initial expense, with edit labels.
      expect(find.text('Edit expense'), findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.text('42.00'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Description'), 'Dinner v2');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount'), '50');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      // Relayed as an edit: same record id, original payer, new content.
      expect(received, hasLength(1));
      expect(received.first.type, expenseEventType);
      expect(received.first.content['id'], 'e1');
      expect(received.first.content['paid_by'], '@alice:x.org');
      expect(received.first.content['description'], 'Dinner v2');
      expect(received.first.content['amount'], 5000);
      expect(received.first.content['deleted'], false);
    });
  });
}
