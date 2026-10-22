/// G75 (review leftovers): *Duplicate expense* (row ⋮ + edit page), the
/// pasted expressions in the amount fields (G79: not advertised), the web limits notice (U31), local-mode
/// delete texts, *Try again* on repeatable action errors.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/background/background_sync_provider.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/l10n/formatting.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/platform/is_web.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/device_prefs.dart';
import 'package:money_ledger/core/widgets/action_error.dart';
import 'package:money_ledger/features/about/about_page.dart';
import 'package:money_ledger/features/backup/backup_providers.dart';
import 'package:money_ledger/features/backup/backup_ui.dart';
import 'package:money_ledger/features/balance/record_payment_dialog.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/features/web/web_limits.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
const _alice = '@alice:x.org';
const _bob = '@bob:x.org';

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  addTearDown(tester.view.reset);
}

MemberModel _m(String id, String name, {String status = 'active'}) =>
    MemberModel(
      groupId: _g,
      userId: id,
      displayName: name,
      matrixId: id,
      status: status,
      updatedAt: 1,
    );

/// A group (CHF) with Alice + Bob in a fresh in-memory DB.
Future<AppDatabase> _seedGroup() async {
  final db = openTestDatabase();
  await GroupsDao(db).upsertGroupLww(
    const GroupsCompanion(
      roomId: Value(_g),
      name: Value('Flat'),
      currency: Value('CHF'),
      updatedAt: Value(1000),
    ),
  );
  for (final (id, name) in [(_alice, 'Alice'), (_bob, 'Bob')]) {
    await MembersDao(db).upsertMemberLww(
      MembersCompanion(
        groupId: const Value(_g),
        userId: Value(id),
        matrixId: Value(id),
        displayName: Value(name),
        status: const Value('active'),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }
  return db;
}

/// Rent from ten days ago, in EUR (not the group's CHF), paid by Bob.
ExpenseModel _rent() {
  final created = DateTime.now()
      .subtract(const Duration(days: 10))
      .millisecondsSinceEpoch;
  return ExpenseModel(
    id: 'src',
    roomId: _g,
    description: 'Rent',
    amountCents: 120000,
    currency: 'EUR',
    paidBy: _bob,
    splitsJson: '{"$_alice":40000,"$_bob":80000}',
    createdAt: created,
    updatedAt: created,
    category: 'home',
    note: 'October',
  );
}

List<dynamic> _formOverrides(AppDatabase db, FakeMatrixNetwork net) => [
  ...signingUiOverrides(),
  appDatabaseProvider.overrideWith((ref) => db),
  ledgerTransportProvider.overrideWith((ref) => net.clientFor(_alice)),
];

String _fieldText(WidgetTester tester, Key key) => tester
    .widget<EditableText>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

Future<void> _pumpSome(WidgetTester tester) async {
  // The in-button spinner never settles — bounded pumps.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  group('duplicate expense', () {
    test('duplicateSplit: as is / spread over who is left / none left', () {
      final rent = _rent();
      expect(duplicateSplit(rent, {_alice, _bob}), {
        _alice: 40000,
        _bob: 80000,
      });
      // Bob left: the amount goes to Alice alone.
      expect(duplicateSplit(rent, {_alice, 'p-x'}), {_alice: 120000});
      expect(duplicateSplit(rent, {'p-x'}), isNull);
      // JPY: whole yen (100 stored hundredths) per person.
      final yen = ExpenseModel(
        id: 'y',
        roomId: _g,
        description: 'Sushi',
        amountCents: 100000,
        currency: 'JPY',
        paidBy: _alice,
        splitsJson: '{"$_alice":30000,"$_bob":30000,"p-c":40000}',
        createdAt: 1,
      );
      expect(duplicateSplit(yen, {_alice, _bob}, step: 100), {
        _alice: 50000,
        _bob: 50000,
      });
    });

    testWidgets('the add form opens prefilled with a copy, dated today; '
        'nothing is saved until Add, then a new expense', (tester) async {
      _phone(tester);
      final db = await _seedGroup();
      addTearDown(db.close);
      final net = FakeMatrixNetwork();
      final rent = _rent();
      await tester.pumpWidget(
        testRouterApp(
          AddExpensePage(roomId: _g, copyFrom: rent),
          overrides: _formOverrides(db, net),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(en.addExpense), findsOneWidget);
      expect(find.byKey(const Key('deleteExpenseButton')), findsNothing);
      expect(find.byKey(const Key('duplicateExpenseButton')), findsNothing);
      expect(_fieldText(tester, const Key('expenseDescription')), 'Rent');
      expect(_fieldText(tester, const Key('expenseAmount')), '1200.00');
      expect(_fieldText(tester, const Key('expenseNote')), 'October');
      expect(
        tester.widget<Text>(find.byKey(const Key('expenseDateValue'))).data,
        en.today,
      );
      late List<ExpenseModel> stored;
      await tester.runAsync(() async {
        stored = await ExpensesDao(db).getExpensesForRoom(_g);
      });
      expect(stored, isEmpty);

      await tester.ensureVisible(find.widgetWithText(FilledButton, en.add));
      await tester.tap(find.widgetWithText(FilledButton, en.add));
      await _pumpSome(tester);
      await tester.runAsync(() async {
        stored = await ExpensesDao(db).getExpensesForRoom(_g);
      });
      expect(stored, hasLength(1));
      final copy = stored.single;
      expect(copy.id, isNot(rent.id));
      expect(copy.description, 'Rent');
      expect(copy.amountCents, 120000);
      expect(copy.currency, 'EUR');
      expect(copy.paidBy, _bob);
      expect(jsonDecode(copy.splitsJson), {_alice: 40000, _bob: 80000});
      expect(copy.category, 'home');
      expect(copy.note, 'October');
      expect(copy.date, isNull, reason: 'dated today');
      expect(
        DateTime.now().millisecondsSinceEpoch - copy.createdAt,
        lessThan(const Duration(minutes: 5).inMilliseconds),
      );
      expect(find.text('host'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('edit page → Duplicate replaces the form with the copy; a '
        'changed form asks first (EN + DE tooltip)', (tester) async {
      _phone(tester);
      final db = await _seedGroup();
      addTearDown(db.close);
      final net = FakeMatrixNetwork();
      final rent = _rent();
      final router = GoRouter(
        initialLocation: '/host',
        routes: [
          GoRoute(
            path: '/host',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('host'))),
          ),
          GoRoute(
            path: '/groups/:roomId/expenses/edit',
            builder: (_, s) => AddExpensePage(
              roomId: s.pathParameters['roomId']!,
              initial: s.extra as ExpenseModel?,
            ),
          ),
          GoRoute(
            path: '/groups/:roomId/expenses/duplicate',
            builder: (_, s) => AddExpensePage(
              roomId: s.pathParameters['roomId']!,
              copyFrom: s.extra as ExpenseModel?,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._formOverrides(db, net)],
          child: MaterialApp.router(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            routerConfig: router,
          ),
        ),
      );
      router.push('/groups/$_g/expenses/edit', extra: rent);
      await tester.pumpAndSettle();
      expect(find.text(en.editExpense), findsOneWidget);
      expect(find.byTooltip(en.duplicateExpense), findsOneWidget);

      // A changed form asks; *Keep editing* stays.
      await tester.enterText(
        find.byKey(const Key('expenseDescription')),
        'Rent (edited)',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('duplicateExpenseButton')));
      await tester.pumpAndSettle();
      expect(find.text(en.discardChangesTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('keepEditing')));
      await tester.pumpAndSettle();
      expect(find.text(en.editExpense), findsOneWidget);

      await tester.tap(find.byKey(const Key('duplicateExpenseButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discardChanges')));
      await tester.pumpAndSettle();
      expect(find.text(en.addExpense), findsOneWidget);
      // The stored expense is copied, not the unsaved edit.
      expect(_fieldText(tester, const Key('expenseDescription')), 'Rent');

      // It replaced the edit page: back → the host.
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('host'), findsOneWidget);
      late List<ExpenseModel> stored;
      await tester.runAsync(() async {
        stored = await ExpensesDao(db).getExpensesForRoom(_g);
      });
      expect(stored, isEmpty, reason: 'nothing written');
      expect(tester.takeException(), isNull);
    });

    Future<void> pumpLedger(
      WidgetTester tester, {
      required bool removed,
      Locale? locale,
    }) async {
      final members = [
        _m(_alice, 'Alice', status: removed ? 'removed' : 'active'),
        _m(_bob, 'Bob'),
      ];
      final router = GoRouter(
        initialLocation: '/groups/$_g/expenses',
        routes: [
          GoRoute(
            path: '/groups/:roomId/expenses',
            builder: (_, _) => const ExpensesPage(roomId: _g),
          ),
          GoRoute(
            path: '/groups/:roomId/expenses/duplicate',
            builder: (_, s) =>
                Text('copy of ${(s.extra! as ExpenseModel).description}'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(
              isLoggedIn: true,
              expenses: [_rent()],
              members: members,
              groups: [
                const GroupModel(roomId: _g, name: 'Flat', currency: 'CHF'),
              ],
            ),
            appDatabaseProvider.overrideWithValue(
              AppDatabase.signedOut(SignedOutExecutor()),
            ),
            ledgerTransportProvider.overrideWith(
              (ref) => FakeMatrixNetwork().clientFor(_alice),
            ),
            currentUserIdProvider.overrideWith((_) => _alice),
            currentParticipantProvider.overrideWith(
              (_, _) async => members.first,
            ),
            groupLedgerFingerprintProvider.overrideWith((_, _) => 'fp'),
          ],
          child: MaterialApp.router(
            locale: locale ?? const Locale('en'),
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final (locale, l) in [
      (const Locale('en'), en),
      (const Locale('de'), de),
    ]) {
      testWidgets('ledger row ⋮ → ${l.duplicateExpense} opens the copy', (
        tester,
      ) async {
        _phone(tester);
        await pumpLedger(tester, removed: false, locale: locale);
        await tester.tap(find.byTooltip(l.expenseOptions));
        await tester.pumpAndSettle();
        expect(find.text(l.duplicateExpense), findsOneWidget);
        await tester.tap(find.byKey(const Key('duplicateExpenseMenuItem')));
        await tester.pumpAndSettle();
        expect(find.text('copy of Rent'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('read-only group: no Duplicate', (tester) async {
      _phone(tester);
      await pumpLedger(tester, removed: true);
      expect(find.byTooltip(en.expenseOptions), findsNothing);
      expect(find.byKey(const Key('duplicateExpenseMenuItem')), findsNothing);
    });
  });

  // G79: the calculator isn't advertised (Gboard's decimal keypad has only
  // `-`), but a pasted expression is still read.
  group('pasted expression in the amount fields (not advertised)', () {
    testWidgets('expense form (DE): "12,50+8" previews 20,50 CHF and saves '
        '2050; "12+" is invalid', (tester) async {
      _phone(tester);
      final db = await _seedGroup();
      addTearDown(db.close);
      final net = FakeMatrixNetwork();
      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: _g),
          locale: const Locale('de'),
          overrides: _formOverrides(db, net),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('expenseDescription')),
        'Pizza',
      );
      // G79: decimal keypad, no hint / helper about operators.
      final amountField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('expenseAmount')),
          matching: find.byType(TextField),
        ),
      );
      expect(
        amountField.keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
      expect(amountField.decoration?.helperText, isNull);
      expect(amountField.decoration?.hintText, '0,00');
      await tester.enterText(find.byKey(const Key('expenseAmount')), '12+');
      await tester.pump();
      final add = find.widgetWithText(FilledButton, de.add);
      expect(tester.widget<FilledButton>(add).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('expenseAmount')), '12,50+8');
      await tester.pump();
      expect(
        find.text(de.amountPreview(formatMoney(2050, 'CHF', 'de'))),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(add).onPressed, isNotNull);
      await tester.ensureVisible(add);
      await tester.tap(add);
      await _pumpSome(tester);
      late List<ExpenseModel> stored;
      await tester.runAsync(() async {
        stored = await ExpensesDao(db).getExpensesForRoom(_g);
      });
      expect(stored.single.amountCents, 2050);
      expect(jsonDecode(stored.single.splitsJson), {_alice: 1025, _bob: 1025});
    });

    testWidgets('payment dialog (EN): "10/4" previews €2.50; "5/0" is an '
        'invalid number', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        testApp(
          const Scaffold(
            body: RecordPaymentDialog(
              participants: {'a': 'Anna', 'b': 'Bob'},
              initialFrom: 'a',
              initialTo: 'b',
              currency: 'EUR',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('paymentAmount')), '10/4');
      await tester.pump();
      expect(
        find.text(en.amountPreview(formatMoney(250, 'EUR', 'en'))),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('paymentAmount')), '5/0');
      await tester.pump();
      expect(find.text(en.invalidNumber), findsOneWidget);
    });
  });

  group('web limits (U31)', () {
    Widget banner(
      InMemoryDevicePrefsStore store, {
      bool web = true,
      Locale? locale,
    }) => testApp(
      const Scaffold(body: WebLimitsBanner()),
      locale: locale,
      overrides: [
        isWebProvider.overrideWithValue(web),
        devicePrefsStoreProvider.overrideWithValue(store),
      ],
    );

    for (final (locale, l) in [
      (const Locale('en'), en),
      (const Locale('de'), de),
    ]) {
      testWidgets('${locale.languageCode}: shown once on the web, *Got it* '
          'stores it for this browser', (tester) async {
        _phone(tester);
        final store = InMemoryDevicePrefsStore({'welcome_seen': '1'});
        await tester.pumpWidget(banner(store, locale: locale));
        await tester.pumpAndSettle();
        expect(find.text(l.webLimitsTitle), findsOneWidget);
        expect(find.text(l.webLimitsBody), findsOneWidget);
        expect(find.text(l.webLimitsBackup), findsOneWidget);
        await tester.tap(find.byKey(const Key('webLimitsDismiss')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('webLimitsBanner')), findsNothing);
        expect(store.values['web_notice_seen'], '1');
        expect(store.values['welcome_seen'], '1', reason: 'kept');

        // A new start: still gone.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(banner(store, locale: locale));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('webLimitsBanner')), findsNothing);
      });
    }

    testWidgets('never on Android', (tester) async {
      await tester.pumpWidget(banner(InMemoryDevicePrefsStore({}), web: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('webLimitsBanner')), findsNothing);
    });

    for (final linkGroups in [false, true]) {
      testWidgets(
        linkGroups
            ? 'local mode with a link group (DEV-J): it syncs too → the '
                  'full text'
            : 'local mode: the text without "while the tab is open"',
        (tester) async {
          _phone(tester);
          await tester.pumpWidget(
            testApp(
              const Scaffold(body: WebLimitsBanner()),
              locale: const Locale('de'),
              overrides: [
                isWebProvider.overrideWithValue(true),
                linkGroupsExistProvider.overrideWith(
                  (_) => Stream.value(linkGroups),
                ),
                devicePrefsStoreProvider.overrideWithValue(
                  InMemoryDevicePrefsStore({
                    'welcome_seen': '1',
                    'local_profile': jsonEncode({
                      'name': 'Lea',
                      'created_at': 1,
                    }),
                  }),
                ),
              ],
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(de.webLimitsBodyLocal),
            linkGroups ? findsNothing : findsOneWidget,
          );
          expect(
            find.text(de.webLimitsBody),
            linkGroups ? findsOneWidget : findsNothing,
          );
        },
      );
    }

    testWidgets('on the groups page (web), above the list', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          overrides: [
            ...testOverrides(isLoggedIn: true),
            isWebProvider.overrideWithValue(true),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('webLimitsBanner')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('About shows it again on the web only', (tester) async {
      _phone(tester);
      for (final web in [false, true]) {
        await tester.pumpWidget(
          testApp(
            const AboutPage(),
            overrides: [
              appVersionProvider.overrideWith((_) async => '1.0.0'),
              isWebProvider.overrideWithValue(web),
              devicePrefsStoreProvider.overrideWithValue(
                InMemoryDevicePrefsStore({'web_notice_seen': '1'}),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('webLimitsTile')),
          web ? findsOneWidget : findsNothing,
        );
      }
      await tester.tap(find.byKey(const Key('webLimitsTile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('webLimitsDialogBody')), findsOneWidget);
      expect(find.text(en.webLimitsBody), findsOneWidget);
    });
  });

  group('local-mode delete texts (G64 leftover)', () {
    for (final local in [false, true]) {
      testWidgets(
        'edit form → Delete: ${local ? '"from this device"' : '"for '
                  'everyone"'} (EN + DE)',
        (tester) async {
          _phone(tester);
          final db = await _seedGroup();
          addTearDown(db.close);
          final net = FakeMatrixNetwork();
          for (final (locale, l) in [
            (const Locale('en'), en),
            (const Locale('de'), de),
          ]) {
            await tester.pumpWidget(
              testApp(
                AddExpensePage(roomId: _g, initial: _rent()),
                locale: locale,
                overrides: [
                  ..._formOverrides(db, net),
                  localModeActiveProvider.overrideWithValue(local),
                ],
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('deleteExpenseButton')));
            await tester.pumpAndSettle();
            expect(
              find.text(
                local
                    ? l.deleteExpenseBodyLocal('Rent')
                    : l.deleteExpenseBody('Rent'),
              ),
              findsOneWidget,
            );
            await tester.tap(find.text(l.cancel));
            await tester.pumpAndSettle();
            await tester.pumpWidget(const SizedBox());
          }
        },
      );
    }
  });

  group('Try again (G67 leftover)', () {
    testWidgets('ActionErrors: *Try again* re-runs, *Details* still there', (
      tester,
    ) async {
      _phone(tester);
      var runs = 0;
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showActionError(
                  context,
                  Exception('boom'),
                  what: en.exportFailedTitle,
                  retry: () => runs++,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text(en.exportFailedTitle), findsOneWidget);
      expect(find.text(en.errorTryAgain), findsOneWidget);
      await tester.tap(find.byKey(const Key('actionErrorDetails')));
      await tester.pumpAndSettle();
      expect(find.text('Exception: boom'), findsOneWidget);
      await tester.tap(find.text(en.ok));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('actionErrorRetry')));
      await tester.pumpAndSettle();
      expect(runs, 1);
    });

    testWidgets('restore: a file that can\'t be read → *Try again* picks '
        'again (DE)', (tester) async {
      _phone(tester);
      var picks = 0;
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => restoreFullBackup(context, ref),
                child: const Text('go'),
              ),
            ),
          ),
          locale: const Locale('de'),
          overrides: [
            ...testOverrides(isLoggedIn: true),
            appDatabaseProvider.overrideWithValue(
              AppDatabase.signedOut(SignedOutExecutor()),
            ),
            ledgerTransportProvider.overrideWith(
              (ref) => FakeMatrixNetwork().clientFor(_alice),
            ),
            currentUserIdProvider.overrideWith((_) => _alice),
            backupFilePickerProvider.overrideWithValue(() async {
              picks++;
              if (picks == 1) throw const FileSystemLikeError();
              return null; // cancelled the second time
            }),
          ],
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text(de.restoreFailedTitle), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);
      await tester.tap(find.byKey(const Key('actionErrorRetry')));
      await tester.pumpAndSettle();
      expect(picks, 2);
      expect(tester.takeException(), isNull);
    });
  });
}

class FileSystemLikeError implements Exception {
  const FileSystemLikeError();
  @override
  String toString() => 'could not read the file';
}
