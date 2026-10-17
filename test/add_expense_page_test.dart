import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/split_editor.dart';
import 'package:money_ledger/models/expense_category.dart';
import 'package:money_ledger/models/expense_model.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';

void main() {
  group('AddExpensePage', () {
    // Seeds a roomless group 'g1' (CHF) with alice + bob as active members in a
    // shared in-memory DB, and returns it plus the fake network.
    Future<(AppDatabase, FakeMatrixNetwork)> seedGroup({
      List<CustomCategory> categories = const [],
    }) async {
      final db = openTestDatabase();
      await GroupsDao(db).upsertGroupLww(
        GroupsCompanion(
          roomId: const Value('g1'),
          name: const Value('Trip'),
          currency: const Value('CHF'),
          updatedAt: const Value(1000),
          categoriesJson: Value(encodeCategories(categories)),
        ),
      );
      final memberDao = MembersDao(db);
      for (final u in ['@alice:x.org', '@bob:x.org']) {
        await memberDao.upsertMemberLww(
          MembersCompanion(
            groupId: const Value('g1'),
            userId: Value(u),
            matrixId: Value(u), // real members, claimed by their own account
            status: const Value('active'),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
      }
      return (db, FakeMatrixNetwork());
    }

    testWidgets('renders the form with the group currency and member count', (
      tester,
    ) async {
      final (db, net) = await seedGroup();

      await tester.pumpWidget(
        testApp(
          const AddExpensePage(roomId: 'g1'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Description'), findsOneWidget);
      // Defaults to the Equal split editor including both members.
      expect(find.textContaining('Split equally among 2'), findsOneWidget);
      expect(find.text('Equal'), findsOneWidget); // mode segment
      expect(find.text('CHF'), findsWidgets); // amount suffix + share previews
    });

    testWidgets('submitting relays the expense to members and pops back', (
      tester,
    ) async {
      final (db, net) = await seedGroup();
      final bob = net.clientFor('@bob:x.org');
      final received = <TransportMessage>[];
      bob.onMessage.listen(received.add);

      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle(); // navigate + load members

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Pizza',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20',
      );
      // G18 review: "Add" is enabled only once a positive amount is in.
      await tester.pump();
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
      // Defaults to the current user as payer.
      expect(received.first.content['paid_by'], '@alice:x.org');
      // Split equally across the two members.
      expect(received.first.content['split'], {
        '@alice:x.org': 1000,
        '@bob:x.org': 1000,
      });
    });

    testWidgets('German locale: comma decimal input, localized form (G12)', (
      tester,
    ) async {
      final (db, net) = await seedGroup();
      final bob = net.clientFor('@bob:x.org');
      final received = <TransportMessage>[];
      bob.onMessage.listen(received.add);

      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1'),
          locale: const Locale('de'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ausgabe hinzufügen'), findsOneWidget); // app bar
      expect(find.textContaining('Gleichmäßig auf 2 Personen'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Beschreibung'),
        'Pizza',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Betrag'),
        '1.234,50',
      );
      await tester.pump();
      // Previews in German currency format.
      expect(find.text('617,25\u00a0CHF'), findsNWidgets(2));
      await tester.tap(find.widgetWithText(FilledButton, 'Hinzufügen'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      expect(received, hasLength(1));
      expect(received.first.content['amount'], 123450);
      expect(received.first.content['split'], {
        '@alice:x.org': 61725,
        '@bob:x.org': 61725,
      });
    });

    // G18 review (findings 6, 12, 14).
    testWidgets('German: "1.234" reads as 1.234,00 (live preview); 0 and '
        'absurd amounts are refused', (tester) async {
      final (db, net) = await seedGroup();
      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1'),
          locale: const Locale('de'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final amount = find.widgetWithText(TextFormField, 'Betrag');
      FilledButton add() =>
          tester.widget<FilledButton>(find.byKey(const Key('submitExpense')));

      await tester.enterText(amount, '1.234');
      await tester.pump();
      expect(find.text('= 1.234,00\u00a0CHF'), findsOneWidget);
      expect(add().onPressed, isNotNull);

      for (final bad in ['0', '0,00', '-5', '100000000000000']) {
        await tester.enterText(amount, bad);
        await tester.pump();
        expect(add().onPressed, isNull, reason: bad);
        expect(find.textContaining('= '), findsNothing, reason: bad);
      }
    });

    // G61: the Exact rows add up to more than the amount → "Set total to
    // the sum" writes the sum into the amount field (locale format) and the
    // saved expense has that amount and the typed split.
    testWidgets('German: "Gesamtbetrag auf die Summe setzen" updates the '
        'amount and the saved split', (tester) async {
      final (db, net) = await seedGroup();
      final bob = net.clientFor('@bob:x.org');
      final received = <TransportMessage>[];
      bob.onMessage.listen(received.add);

      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1'),
          locale: const Locale('de'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Beschreibung'),
        'Pizza',
      );
      final amount = find.widgetWithText(TextFormField, 'Betrag');
      await tester.enterText(amount, '10');
      await tester.pump();
      await tester.ensureVisible(find.text('Genau'));
      await tester.tap(find.text('Genau'));
      await tester.pumpAndSettle();
      final rows = find.descendant(
        of: find.byType(SplitEditor),
        matching: find.byType(TextField),
      );
      await tester.enterText(rows.at(0), '8,5');
      await tester.enterText(rows.at(1), '5');
      await tester.pumpAndSettle();
      expect(find.text('3,50\u00a0CHF zu viel'), findsOneWidget);
      FilledButton add() =>
          tester.widget<FilledButton>(find.byKey(const Key('submitExpense')));
      expect(add().onPressed, isNull);

      final setTotal = find.byKey(const Key('splitSetTotal'));
      await tester.ensureVisible(setTotal);
      await tester.pumpAndSettle();
      expect(find.text('Gesamtbetrag auf die Summe setzen'), findsOneWidget);
      await tester.tap(setTotal);
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(amount).controller!.text, '13,50');
      expect(find.text('Ergibt den Gesamtbetrag'), findsOneWidget);
      expect(setTotal, findsNothing);
      expect(add().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('submitExpense')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(received, hasLength(1));
      expect(received.first.content['amount'], 1350);
      expect(received.first.content['split'], {
        '@alice:x.org': 850,
        '@bob:x.org': 500,
      });
      final saved = await ExpensesDao(db).getExpensesForRoom('g1');
      expect(saved.single.amountCents, 1350);
    });

    testWidgets('the payer dropdown sets paid_by', (tester) async {
      final (db, net) = await seedGroup();
      final bob = net.clientFor('@bob:x.org');
      final received = <TransportMessage>[];
      bob.onMessage.listen(received.add);

      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Pizza',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20',
      );
      // Switch the payer from alice (default) to bob (the form scrolls).
      await tester.ensureVisible(find.text('Paid by'));
      await tester.tap(find.text('Paid by'));
      await tester.pumpAndSettle();
      // G17: names fall back to the MXID localpart.
      await tester.tap(find.text('bob').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      expect(received, hasLength(1));
      expect(received.first.content['paid_by'], '@bob:x.org');
    });

    // Per-member fields inside the SplitEditor, in member order (alice, bob).
    Finder splitFields() => find.descendant(
      of: find.byType(SplitEditor),
      matching: find.byType(TextField),
    );

    testWidgets('exact mode relays the typed per-person amounts', (
      tester,
    ) async {
      final (db, net) = await seedGroup();
      final received = <TransportMessage>[];
      net.clientFor('@bob:x.org').onMessage.listen(received.add);

      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Taxi',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20',
      );
      await tester.ensureVisible(find.text('Exact'));
      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      await tester.enterText(splitFields().at(0), '15'); // alice
      await tester.enterText(splitFields().at(1), '5'); // bob
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      expect(received, hasLength(1));
      expect(received.first.content['split'], {
        '@alice:x.org': 1500,
        '@bob:x.org': 500,
      });
    });

    testWidgets('shares mode relays a proportional split', (tester) async {
      final (db, net) = await seedGroup();
      final received = <TransportMessage>[];
      net.clientFor('@bob:x.org').onMessage.listen(received.add);

      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Groceries',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20',
      );
      await tester.ensureVisible(find.text('Shares'));
      await tester.tap(find.text('Shares'));
      await tester.pumpAndSettle();
      await tester.enterText(splitFields().at(0), '3'); // alice : 3
      await tester.enterText(splitFields().at(1), '1'); // bob : 1
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      expect(received, hasLength(1));
      expect(received.first.content['split'], {
        '@alice:x.org': 1500,
        '@bob:x.org': 500,
      });
    });

    testWidgets('deselecting a member in Equal mode excludes them', (
      tester,
    ) async {
      final (db, net) = await seedGroup();
      final received = <TransportMessage>[];
      net.clientFor('@bob:x.org').onMessage.listen(received.add);

      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Solo',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20',
      );
      // Uncheck bob (second checkbox) → whole amount falls on alice.
      await tester.ensureVisible(find.byType(Checkbox).at(1));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      expect(received, hasLength(1));
      expect(received.first.content['split'], {'@alice:x.org': 2000});
    });

    testWidgets('an unbalanced exact split disables Add', (tester) async {
      final (db, net) = await seedGroup();
      final received = <TransportMessage>[];
      net.clientFor('@bob:x.org').onMessage.listen(received.add);

      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Oops',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20',
      );
      await tester.ensureVisible(find.text('Exact'));
      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      await tester.enterText(splitFields().at(0), '5'); // only 5 of 20
      await tester.pumpAndSettle();

      // Button is disabled, so tapping relays nothing.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add'),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('5.00 left'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(received, isEmpty);
    });

    testWidgets('editing an unequal expense opens Exact mode prefilled', (
      tester,
    ) async {
      final (db, net) = await seedGroup();
      const initial = ExpenseModel(
        id: 'e9',
        roomId: 'g1',
        description: 'Hotel',
        amountCents: 4200,
        currency: 'CHF',
        paidBy: '@alice:x.org',
        splitsJson: '{"@alice:x.org":3000,"@bob:x.org":1200}',
        createdAt: 1000,
        updatedAt: 1000,
      );

      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1', initial: initial),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Unequal → reopened as exact amounts, prefilled per person.
      expect(find.widgetWithText(TextField, '30.00'), findsOneWidget);
      expect(find.widgetWithText(TextField, '12.00'), findsOneWidget);
    });

    testWidgets('edit mode prefills the form and saves as the same record', (
      tester,
    ) async {
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

      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1', initial: initial),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Prefilled from the initial expense, with edit labels.
      expect(find.text('Edit expense'), findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.text('42.00'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Dinner v2',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '50',
      );
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

    // G29: per-expense currency, defaulting to the group's.
    testWidgets('the currency picker defaults to the group and sets currency', (
      tester,
    ) async {
      final (db, net) = await seedGroup();
      final received = <TransportMessage>[];
      net.clientFor('@bob:x.org').onMessage.listen(received.add);

      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final picker = find.byKey(const Key('expenseCurrency'));
      expect(
        find.descendant(of: picker, matching: find.text('CHF')),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Souvenir',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '10',
      );
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD').last);
      await tester.pumpAndSettle();
      // The split previews follow the chosen currency.
      expect(find.textContaining('USD'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      expect(received, hasLength(1));
      expect(received.first.content['currency'], 'USD');
      expect(received.first.content['amount'], 1000);
    });

    testWidgets('editing keeps the expense\'s own (unlisted) currency', (
      tester,
    ) async {
      final (db, net) = await seedGroup();
      final received = <TransportMessage>[];
      net.clientFor('@bob:x.org').onMessage.listen(received.add);
      const initial = ExpenseModel(
        id: 'e1',
        roomId: 'g1',
        description: 'Noodles',
        amountCents: 2000,
        currency: 'THB', // not in kGroupCurrencies; group is CHF
        paidBy: '@alice:x.org',
        splitsJson: '{"@alice:x.org":1000,"@bob:x.org":1000}',
        createdAt: 1000,
        updatedAt: 1000,
      );

      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1', initial: initial),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('expenseCurrency')),
          matching: find.text('THB'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(received.single.content['currency'], 'THB');
    });

    // ── G16: category + note ──────────────────────────────────────────────
    Future<List<TransportMessage>> pumpForm(
      WidgetTester tester, {
      ExpenseModel? initial,
      Locale? locale,
      List<CustomCategory> categories = const [],
      AppDatabase? database,
    }) async {
      final (seeded, net) = await seedGroup(categories: categories);
      final db = database ?? seeded;
      final received = <TransportMessage>[];
      net.clientFor('@bob:x.org').onMessage.listen(received.add);
      await tester.pumpWidget(
        testRouterApp(
          AddExpensePage(roomId: 'g1', initial: initial),
          locale: locale,
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      return received;
    }

    Future<void> submit(WidgetTester tester, String label) async {
      await tester.pump(); // the amount enables the button (G18 review)
      await tester.tap(find.widgetWithText(FilledButton, label));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
    }

    /// G47: the category selector's shown value.
    String selectedLabel(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('categoryPickerValue'))).data!;

    Future<void> openPicker(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('categoryPickerField')));
      await tester.tap(find.byKey(const Key('categoryPickerField')));
      await tester.pumpAndSettle();
    }

    Finder sheetEntry(String key) => find.byKey(Key('category-$key'));

    Future<void> scrollToEntry(WidgetTester tester, String key) async {
      await tester.scrollUntilVisible(
        sheetEntry(key),
        120,
        scrollable: find.descendant(
          of: find.byKey(const Key('categorySheet')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(sheetEntry(key));
      await tester.pumpAndSettle();
    }

    /// Opens the selector and picks [key] (`none`, a wire id, a custom id or
    /// `new`).
    Future<void> pick(WidgetTester tester, String key) async {
      await openPicker(tester);
      await scrollToEntry(tester, key);
      await tester.tap(sheetEntry(key));
      await tester.pumpAndSettle();
    }

    testWidgets('the description suggests a category; a note is sent', (
      tester,
    ) async {
      final received = await pumpForm(tester);
      expect(find.byKey(const Key('categoryPicker')), findsOneWidget);
      expect(selectedLabel(tester), 'No category');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Pizza',
      );
      await tester.pumpAndSettle();
      expect(selectedLabel(tester), 'Food & drink');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20',
      );
      await tester.enterText(
        find.byKey(const Key('expenseNote')),
        '  Margherita x2  ',
      );
      await submit(tester, 'Add');

      expect(received.single.content['category'], 'food');
      expect(received.single.content['note'], 'Margherita x2');
    });

    testWidgets('a picked category wins over later suggestions; "No '
        'category" clears it', (tester) async {
      final received = await pumpForm(tester);
      await pick(tester, 'health');
      expect(selectedLabel(tester), 'Health');
      // Typing no longer changes the user's choice.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Taxi',
      );
      await tester.pumpAndSettle();
      expect(selectedLabel(tester), 'Health');
      // The sheet marks the selection; "No category" clears it.
      await openPicker(tester);
      await scrollToEntry(tester, 'health');
      expect(tester.widget<ListTile>(sheetEntry('health')).selected, isTrue);
      // Dismissing the sheet changes nothing.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(selectedLabel(tester), 'Health');
      await pick(tester, 'none');
      expect(selectedLabel(tester), 'No category');

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20',
      );
      await submit(tester, 'Add');
      expect(received.single.content.containsKey('category'), isFalse);
      expect(received.single.content.containsKey('note'), isFalse);
    });

    testWidgets('edit: category + note prefilled; no suggestion overrides', (
      tester,
    ) async {
      const initial = ExpenseModel(
        id: 'e1',
        roomId: 'g1',
        description: 'Taxi',
        amountCents: 2000,
        currency: 'CHF',
        paidBy: '@alice:x.org',
        splitsJson: '{"@alice:x.org":1000,"@bob:x.org":1000}',
        createdAt: 1000,
        updatedAt: 1000,
        category: 'pets', // a newer peer's category: kept verbatim
        note: 'From the station',
      );
      final received = await pumpForm(tester, initial: initial);
      expect(find.text('From the station'), findsOneWidget);
      expect(selectedLabel(tester), 'Other'); // unknown → "other"
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Pizza',
      );
      await tester.pumpAndSettle();
      expect(selectedLabel(tester), 'Other');
      await submit(tester, 'Save');
      expect(received.single.content['category'], 'pets');
      expect(received.single.content['note'], 'From the station');
    });

    testWidgets('German: category labels and note field', (tester) async {
      await pumpForm(tester, locale: const Locale('de'));
      expect(find.text('Keine Kategorie'), findsOneWidget);
      expect(find.text('Notiz (optional)'), findsOneWidget);
      await openPicker(tester);
      expect(find.text('Essen & Trinken'), findsOneWidget);
      await scrollToEntry(tester, 'new');
      expect(find.text('Neue Kategorie …'), findsOneWidget);
    });

    // ── G47: custom categories ────────────────────────────────────────────
    const dog = CustomCategory(id: 'c:dog', name: 'Dog', icon: 'pets');
    const kids = CustomCategory(
      id: 'c:kids',
      name: 'Kids',
      icon: 'child',
      hidden: true,
    );

    testWidgets('custom categories are offered; hidden ones are not', (
      tester,
    ) async {
      final received = await pumpForm(tester, categories: [dog, kids]);
      await openPicker(tester);
      await scrollToEntry(tester, 'c:dog');
      expect(find.text('This group'.toUpperCase()), findsOneWidget);
      expect(sheetEntry('c:kids'), findsNothing);
      await tester.tap(sheetEntry('c:dog'));
      await tester.pumpAndSettle();
      expect(selectedLabel(tester), 'Dog');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Vet',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20',
      );
      await submit(tester, 'Add');
      expect(received.single.content['category'], 'c:dog');
    });

    testWidgets('edit: a hidden category still labels the expense', (
      tester,
    ) async {
      const initial = ExpenseModel(
        id: 'e1',
        roomId: 'g1',
        description: 'Toys',
        amountCents: 2000,
        currency: 'CHF',
        paidBy: '@alice:x.org',
        splitsJson: '{"@alice:x.org":1000,"@bob:x.org":1000}',
        createdAt: 1000,
        updatedAt: 1000,
        category: 'c:kids',
      );
      final received = await pumpForm(
        tester,
        initial: initial,
        categories: [dog, kids],
      );
      expect(selectedLabel(tester), 'Kids');
      await submit(tester, 'Save');
      expect(received.single.content['category'], 'c:kids');
    });

    testWidgets('"New category…" creates one in the group meta (relayed) '
        'and selects it', (tester) async {
      final (db, _) = await seedGroup(categories: [dog]);
      final received = await pumpForm(tester, database: db);
      await pick(tester, 'new');
      expect(find.text('New category'), findsOneWidget);
      // Validation: empty and duplicate names are refused.
      await tester.tap(find.byKey(const Key('categoryDialogSave')));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('categoryNameField')), 'dog');
      await tester.tap(find.byKey(const Key('categoryDialogSave')));
      await tester.pumpAndSettle();
      expect(
        find.text('This group already has a category with this name'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('categoryNameField')),
        '  Climbing gym ',
      );
      await tester.tap(find.byKey(const Key('categoryIcon-sports')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('categoryDialogSave')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      await tester.pumpAndSettle();
      expect(selectedLabel(tester), 'Climbing gym');

      final group = await tester.runAsync(() => GroupsDao(db).getGroup('g1'));
      final created = group!.categories.last;
      expect((created.name, created.icon), ('Climbing gym', 'sports'));
      expect(created.id, startsWith('c:'));
      expect(group.categories.first, dog);
      // The new meta version went to the members.
      expect(
        received
            .where((m) => m.type == groupMetaEventType)
            .single
            .content['categories'],
        hasLength(2),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Bouldering',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20',
      );
      await submit(tester, 'Add');
      expect(
        received
            .where((m) => m.type == expenseEventType)
            .single
            .content['category'],
        created.id,
      );
    });

    // ── G49: expense date ─────────────────────────────────────────────────
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    String dateValue(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('expenseDateValue'))).data!;

    Future<void> fillPizza(WidgetTester tester) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Pizza',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20',
      );
    }

    testWidgets('a new expense is dated today: no date on the wire', (
      tester,
    ) async {
      final received = await pumpForm(tester);
      expect(dateValue(tester), 'Today');
      await fillPizza(tester);
      await submit(tester, 'Add');
      expect(received.single.content.containsKey('date'), isFalse);
    });

    testWidgets('picking "Yesterday" back-dates the expense (saved + sent)', (
      tester,
    ) async {
      final (db, _) = await seedGroup();
      final received = await pumpForm(tester, database: db);
      await fillPizza(tester);
      await tester.ensureVisible(find.byKey(const Key('expenseDateYesterday')));
      await tester.tap(find.byKey(const Key('expenseDateYesterday')));
      await tester.pump();
      expect(dateValue(tester), 'Yesterday');
      await submit(tester, 'Add');

      final now = DateTime.now();
      final yesterday = iso(DateTime(now.year, now.month, now.day - 1));
      expect(received.single.content['date'], yesterday);
      final stored = await tester.runAsync(
        () => ExpensesDao(db).getExpensesForRoom('g1'),
      );
      expect(stored!.single.date, yesterday);
    });

    testWidgets('the date field opens a date picker', (tester) async {
      final received = await pumpForm(tester);
      await fillPizza(tester);
      await tester.ensureVisible(find.byKey(const Key('expenseDate')));
      await tester.tap(find.byKey(const Key('expenseDate')));
      await tester.pumpAndSettle();
      expect(find.text('When did it happen?'), findsOneWidget);
      final now = DateTime.now();
      final dayNum = now.day == 1 ? 2 : 1;
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('$dayNum'),
        ),
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await submit(tester, 'Add');
      expect(
        received.single.content['date'],
        iso(DateTime(now.year, now.month, dayNum)),
      );
    });

    const datedInitial = ExpenseModel(
      id: 'e1',
      roomId: 'g1',
      description: 'Dinner',
      amountCents: 4200,
      currency: 'CHF',
      paidBy: '@alice:x.org',
      splitsJson: '{"@alice:x.org":2100,"@bob:x.org":2100}',
      createdAt: 1000,
      updatedAt: 1000,
      date: '2025-10-01',
    );

    testWidgets('edit: the stored date is shown and kept when unchanged', (
      tester,
    ) async {
      final received = await pumpForm(tester, initial: datedInitial);
      expect(dateValue(tester), contains('2025'));
      await submit(tester, 'Save');
      expect(received.single.content['date'], '2025-10-01');
    });

    testWidgets('edit: "Today" re-dates the expense', (tester) async {
      final received = await pumpForm(tester, initial: datedInitial);
      await tester.ensureVisible(find.byKey(const Key('expenseDateToday')));
      await tester.tap(find.byKey(const Key('expenseDateToday')));
      await tester.pump();
      expect(dateValue(tester), 'Today');
      await submit(tester, 'Save');
      // Created in 1970, so "today" is a date of its own.
      expect(received.single.content['date'], iso(DateTime.now()));
    });

    testWidgets('German: date label and quick picks', (tester) async {
      await pumpForm(tester, locale: const Locale('de'));
      expect(find.text('Datum'), findsOneWidget);
      expect(find.text('Heute'), findsWidgets);
      expect(find.text('Gestern'), findsOneWidget);
    });
  });
}
