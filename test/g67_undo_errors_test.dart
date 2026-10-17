/// G67 widget tests (360 dp, EN + DE): delete → "Deleted · Undo" snackbar
/// whose Undo writes the earlier version back (U13); *Delete* in the edit
/// form and the edit-payment dialog; the read-only details sheet (U15);
/// friendly action errors with the raw text only behind *Details* (U25).
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/widgets/action_error.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/eventually.dart';
import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
const _alice = '@alice:x.org';
const _bob = '@bob:y.org';

MemberModel _m(String id, String name, {String status = 'active'}) =>
    MemberModel(
      groupId: _g,
      userId: id,
      displayName: name,
      matrixId: id,
      status: status,
      updatedAt: 1,
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  late AppDatabase db;
  late FakeMatrixNetwork net;

  setUp(() {
    db = openTestDatabase();
    net = FakeMatrixNetwork();
    net.clientFor(_alice);
    net.clientFor(_bob);
  });
  tearDown(() => db.close());

  /// Group + both members in the DB; [write] runs with Alice's ExpenseAdder.
  Future<T> seed<T>(
    WidgetTester tester,
    Future<T> Function(ExpenseAdder adder) write,
  ) async {
    late T result;
    await tester.runAsync(() async {
      await GroupsDao(db).upsertGroupLww(
        const GroupsCompanion(
          roomId: Value(_g),
          name: Value('Trip'),
          currency: Value('EUR'),
          updatedAt: Value(1),
        ),
      );
      for (final id in [_alice, _bob]) {
        await MembersDao(db).upsertMemberLww(
          MembersCompanion(
            groupId: const Value(_g),
            userId: Value(id),
            matrixId: Value(id),
            displayName: Value(id == _alice ? 'Alice' : 'Bob'),
            status: const Value('active'),
            updatedAt: const Value(1),
          ),
        );
      }
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(_alice)),
        ],
      );
      c.listen(expenseAdderProvider, (_, _) {});
      result = await write(c.read(expenseAdderProvider.notifier));
      c.dispose();
    });
    return result;
  }

  Future<SettlementModel> seedPayment(WidgetTester tester) async {
    await seed(
      tester,
      (a) => a.addSettlement(
        roomId: _g,
        amountCents: 1500,
        currency: 'EUR',
        fromUser: _bob,
        toUser: _alice,
      ),
    );
    late SettlementModel p;
    await tester.runAsync(() async {
      p = (await ExpensesDao(db).getSettlementsForRoom(_g)).single;
    });
    return p;
  }

  Future<ExpenseModel> seedExpense(WidgetTester tester) async {
    await seed(
      tester,
      (a) => a.addExpense(
        roomId: _g,
        description: 'Dinner',
        amountCents: 4200,
        currency: 'EUR',
        paidBy: _alice,
        splits: {_alice: 1200, _bob: 3000},
        note: 'Tip incl.',
      ),
    );
    late ExpenseModel e;
    await tester.runAsync(() async {
      e = (await ExpensesDao(db).getExpensesForRoom(_g)).single;
    });
    return e;
  }

  Future<void> pumpLedger(
    WidgetTester tester, {
    List<ExpenseModel> expenses = const [],
    List<SettlementModel> settlements = const [],
    bool removed = false,
    Locale? locale,
  }) async {
    _phone(tester);
    final members = [
      _m(_alice, 'Alice', status: removed ? 'removed' : 'active'),
      _m(_bob, 'Bob'),
    ];
    await tester.pumpWidget(
      testApp(
        const ExpensesPage(roomId: _g),
        locale: locale,
        overrides: [
          ...testOverrides(
            isLoggedIn: true,
            expenses: expenses,
            settlements: settlements,
            members: members,
            groups: [
              const GroupModel(roomId: _g, name: 'Trip', currency: 'EUR'),
            ],
          ),
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(_alice)),
          currentUserIdProvider.overrideWith((_) => _alice),
          currentParticipantProvider.overrideWith(
            (_, _) async => members.first,
          ),
          groupLedgerFingerprintProvider.overrideWith((_, _) => 'fp'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<SettlementModel> storedPayment(WidgetTester tester, String id) async {
    late SettlementModel row;
    await tester.runAsync(() async {
      row = (await ExpensesDao(db).getSettlementById(id))!;
    });
    return row;
  }

  Future<ExpenseModel> storedExpense(WidgetTester tester, String id) async {
    late ExpenseModel row;
    await tester.runAsync(() async {
      row = (await ExpensesDao(db).getExpenseById(id))!;
    });
    return row;
  }

  group('payment', () {
    testWidgets('⋮ → Delete → confirm → "Payment deleted · Undo"; Undo '
        'restores it as a new signed version', (tester) async {
      final payment = await seedPayment(tester);
      await pumpLedger(tester, settlements: [payment]);

      await tester.tap(find.byTooltip(en.settlementOptions));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.delete));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('confirmDelete')));
        await eventually(
          () async =>
              (await ExpensesDao(db).getSettlementById(payment.id))!.deleted,
          tester: tester,
        );
      });
      await tester.pumpAndSettle();
      expect(find.text(en.paymentDeletedSnack), findsOneWidget);
      expect(find.byKey(const Key('undoAction')), findsOneWidget);
      final tomb = await storedPayment(tester, payment.id);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('undoAction')));
        await eventually(
          () async =>
              !(await ExpensesDao(db).getSettlementById(payment.id))!.deleted,
          tester: tester,
        );
        await net.settle(); // the relay of the undo version
      });
      await tester.pumpAndSettle();
      expect(find.text(en.undoDone), findsOneWidget);
      final row = await storedPayment(tester, payment.id);
      expect(row.amountCents, 1500);
      expect(row.updatedAt, greaterThan(tomb.updatedAt));
      expect(row.origin!.sig, payment.origin!.sig);
      expect(row.sig, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('edit dialog → Delete payment → confirm → deleted + Undo', (
      tester,
    ) async {
      final payment = await seedPayment(tester);
      await pumpLedger(tester, settlements: [payment]);
      await tester.tap(find.byKey(const Key('settlementTitle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paymentDelete')), findsOneWidget);
      await tester.tap(find.byKey(const Key('paymentDelete')));
      await tester.pumpAndSettle();
      expect(find.text(en.deleteSettlementTitle), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('confirmDelete')));
        await eventually(
          () async =>
              (await ExpensesDao(db).getSettlementById(payment.id))!.deleted,
          tester: tester,
        );
      });
      await tester.pumpAndSettle();
      expect(find.text(en.paymentDeletedSnack), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('German: "Zahlung löschen" in the dialog, snackbar', (
      tester,
    ) async {
      final payment = await seedPayment(tester);
      await pumpLedger(
        tester,
        settlements: [payment],
        locale: const Locale('de'),
      );
      await tester.tap(find.byKey(const Key('settlementTitle')));
      await tester.pumpAndSettle();
      expect(find.text('Zahlung löschen'), findsOneWidget);
      await tester.tap(find.byKey(const Key('paymentDelete')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('confirmDelete')));
        await eventually(
          () async =>
              (await ExpensesDao(db).getSettlementById(payment.id))!.deleted,
          tester: tester,
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('Zahlung gelöscht'), findsOneWidget);
      expect(find.text('Rückgängig'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('read-only group: tap opens the details sheet (EN + DE)', (
      tester,
    ) async {
      final payment = await seedPayment(tester);
      for (final (locale, l) in [
        (const Locale('en'), en),
        (const Locale('de'), de),
      ]) {
        await pumpLedger(
          tester,
          settlements: [payment],
          removed: true,
          locale: locale,
        );
        await tester.tap(find.byKey(const Key('settlementTitle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('settlementDetailsSheet')), findsOneWidget);
        Finder inSheet(String text) => find.descendant(
          of: find.byKey(const Key('settlementDetailsSheet')),
          matching: find.text(text),
        );
        expect(inSheet(l.paymentDetailsTitle), findsOneWidget);
        expect(inSheet(l.settlementTitle('Bob', 'Alice')), findsOneWidget);
        expect(inSheet(l.detailsReadOnlyHint), findsOneWidget);
        expect(find.text(l.editPayment), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(10, 10)); // close the sheet
        await tester.pumpAndSettle();
      }
    });
  });

  group('expense', () {
    testWidgets('list ⋮ → Delete → Undo brings it back', (tester) async {
      final expense = await seedExpense(tester);
      await pumpLedger(tester, expenses: [expense]);
      await tester.tap(find.byTooltip(en.expenseOptions));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.delete));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('confirmDelete')));
        await eventually(
          () async =>
              (await ExpensesDao(db).getExpenseById(expense.id))!.deleted,
          tester: tester,
        );
      });
      await tester.pumpAndSettle();
      expect(find.text(en.expenseDeletedSnack('Dinner')), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('undoAction')));
        await eventually(
          () async =>
              !(await ExpensesDao(db).getExpenseById(expense.id))!.deleted,
          tester: tester,
        );
        await net.settle(); // the relay of the undo version
      });
      await tester.pumpAndSettle();
      final row = await storedExpense(tester, expense.id);
      expect(row.note, 'Tip incl.');
      expect(row.origin!.sig, expense.origin!.sig);
      expect(find.text(en.undoDone), findsOneWidget);
    });

    for (final (locale, l) in [
      (const Locale('en'), en),
      (const Locale('de'), de),
    ]) {
      testWidgets('edit form: Delete → confirm → leaves the form, deleted, '
          'Undo snackbar (${locale.languageCode})', (tester) async {
        final expense = await seedExpense(tester);
        _phone(tester);
        await tester.pumpWidget(
          testRouterApp(
            AddExpensePage(roomId: _g, initial: expense),
            locale: locale,
            overrides: [
              ...signingUiOverrides(),
              appDatabaseProvider.overrideWith((ref) => db),
              ledgerTransportProvider.overrideWith(
                (ref) => net.clientFor(_alice),
              ),
            ],
          ),
        );
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(find.byTooltip(l.deleteExpenseAction), findsOneWidget);
        await tester.tap(find.byKey(const Key('deleteExpenseButton')));
        await tester.pumpAndSettle();
        expect(find.text(l.deleteExpenseTitle), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const Key('confirmDelete')));
          await eventually(
            () async =>
                (await ExpensesDao(db).getExpenseById(expense.id))!.deleted,
            tester: tester,
          );
        });
        await tester.pumpAndSettle();
        // Back on the page underneath, no "Discard changes?".
        expect(find.text('host'), findsOneWidget);
        expect(find.text(l.discardChangesTitle), findsNothing);
        expect(find.text(l.expenseDeletedSnack('Dinner')), findsOneWidget);
        expect(find.text(l.undo), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('edit form: cancelling the delete keeps everything', (
      tester,
    ) async {
      final expense = await seedExpense(tester);
      _phone(tester);
      await tester.pumpWidget(
        testRouterApp(
          AddExpensePage(roomId: _g, initial: expense),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor(_alice),
            ),
          ],
        ),
      );
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteExpenseButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.cancel));
      await tester.pumpAndSettle();
      expect(find.text(en.editExpense), findsOneWidget);
      final row = await storedExpense(tester, expense.id);
      expect(row.deleted, isFalse);
      expect(row.updatedAt, expense.updatedAt);
    });

    testWidgets('read-only group: tap shows amount, split and note', (
      tester,
    ) async {
      final expense = await seedExpense(tester);
      await pumpLedger(tester, expenses: [expense], removed: true);
      await tester.tap(find.byKey(const Key('expenseTitle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('expenseDetailsSheet')), findsOneWidget);
      expect(find.byKey(const Key('detailsAmount')), findsOneWidget);
      expect(find.text('€42.00'), findsWidgets);
      expect(find.text('€12.00'), findsOneWidget);
      expect(find.text('€30.00'), findsOneWidget);
      expect(find.text('Tip incl.'), findsOneWidget);
      expect(find.text(en.detailsReadOnlyHint), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('action errors', () {
    Widget host(Object error, {Locale? locale, String? Function()? what}) =>
        MaterialApp(
          locale: locale ?? const Locale('en'),
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showActionError(context, error, what: what?.call()),
                child: const Text('go'),
              ),
            ),
          ),
        );

    testWidgets('friendly snackbar; raw text only behind Details', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(host(StateError('db closed')));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text(en.errorInterruptedTitle), findsOneWidget);
      expect(find.text(en.errorInterruptedHint), findsOneWidget);
      expect(find.textContaining('StateError'), findsNothing);
      expect(find.textContaining('Bad state'), findsNothing);

      await tester.tap(find.text(en.errorDetails));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('actionErrorDetailsDialog')), findsOneWidget);
      expect(find.text('Bad state: db closed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('German, with what failed first', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        host(
          const FormatException('x'),
          locale: const Locale('de'),
          what: () => de.exportFailedTitle,
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Export fehlgeschlagen'), findsOneWidget);
      expect(find.text(de.errorInvalidDataTitle), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('inline view: details collapsed until opened', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: ActionErrorView(
              error: Exception('boom'),
              what: en.loadFailedTitle,
            ),
          ),
        ),
      );
      expect(find.text(en.loadFailedTitle), findsOneWidget);
      expect(find.text(en.errorUnknownTitle), findsOneWidget);
      expect(find.text('Exception: boom'), findsNothing);
      await tester.tap(find.text(en.errorDetails));
      await tester.pumpAndSettle();
      expect(find.text('Exception: boom'), findsOneWidget);
    });
  });
}
