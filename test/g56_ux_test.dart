/// G56: UX follow-ups — short account lines on the members page, Devices in
/// the settings sheet, "Add people" above a ledger where I'm alone, and the
/// discard confirmation on the expense form.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';

MemberModel _member(
  String id,
  String name, {
  String? mxid,
  String status = 'active',
}) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  matrixId: mxid,
  status: status,
  updatedAt: 1,
);

ExpenseModel _expense(String paidBy) => ExpenseModel(
  id: 'e1',
  roomId: _g,
  description: 'Dinner',
  amountCents: 4000,
  currency: 'EUR',
  paidBy: paidBy,
  splitsJson: '{"$paidBy":4000}',
  createdAt: 5000,
);

void main() {
  group('memberAccountLine', () {
    final alice = _member('@alice:x.org', 'Alice', mxid: '@alice:x.org');

    test('local participant → none', () {
      expect(memberAccountLine(_member('p1', 'Cash'), [alice]), isNull);
    });

    test('normally the @localpart only', () {
      expect(memberAccountLine(alice, [alice]), '@alice');
    });

    test('same name (case-insensitive) → full MXID', () {
      final other = _member('@ali:y.org', ' alice ', mxid: '@ali:y.org');
      expect(memberAccountLine(alice, [alice, other]), '@alice:x.org');
      expect(memberAccountLine(other, [alice, other]), '@ali:y.org');
    });

    test('a local person with the same name counts too', () {
      final cash = _member('p1', 'Alice');
      expect(memberAccountLine(alice, [alice, cash]), '@alice:x.org');
    });

    test('same localpart on another server → full MXID', () {
      final other = _member('@alice:y.org', 'Ali', mxid: '@alice:y.org');
      expect(memberAccountLine(alice, [alice, other]), '@alice:x.org');
    });

    test('a non-MXID claim is shown as is', () {
      final weird = _member('p1', 'Lea', mxid: 'local:self');
      expect(memberAccountLine(weird, [weird]), 'local:self');
    });
  });

  group('settings sheet: Devices & security', () {
    Widget app({Locale? locale}) {
      final router = GoRouter(
        initialLocation: '/groups',
        routes: [
          GoRoute(path: '/groups', builder: (_, _) => const GroupsPage()),
          GoRoute(
            path: '/devices',
            builder: (_, _) => const Scaffold(body: Text('devices page')),
          ),
        ],
      );
      return ProviderScope(
        overrides: [...testOverrides(isLoggedIn: true)],
        child: MaterialApp.router(
          locale: locale ?? const Locale('en'),
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          routerConfig: router,
        ),
      );
    }

    testWidgets('no app-bar icon; the sheet tile opens /devices', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.byTooltip('Devices & security'), findsNothing);
      expect(find.byIcon(Icons.devices), findsNothing);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final tile = find.byKey(const Key('devicesTile'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: tile, matching: find.text('Devices & security')),
        findsOneWidget,
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.text('devices page'), findsOneWidget);
      expect(find.byKey(const Key('devicesTile')), findsNothing);
    });

    testWidgets('German', (tester) async {
      await tester.pumpWidget(app(locale: const Locale('de')));
      await tester.pump();
      await tester.tap(find.byTooltip('Einstellungen'));
      await tester.pumpAndSettle();
      expect(find.text(de.devicesTooltip), findsOneWidget);
      expect(find.text(de.devicesSettingsBody), findsOneWidget);
    });
  });

  group('"Add people" above a ledger where I am alone', () {
    final me = _member('@me:x.org', 'Me', mxid: '@me:x.org');

    Widget app(List<MemberModel> members, {Locale? locale}) => testApp(
      const ExpensesPage(roomId: _g),
      locale: locale,
      overrides: [
        ...testOverrides(
          isLoggedIn: true,
          members: members,
          expenses: [_expense(me.userId)],
        ),
        currentParticipantProvider.overrideWith(
          (ref, g) => Future<MemberModel?>.value(members.first),
        ),
      ],
    );

    testWidgets('shows the card; it opens the add-person dialog', (
      tester,
    ) async {
      await tester.pumpWidget(app([me]));
      await tester.pumpAndSettle();
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.byKey(const Key('addPeopleCard')), findsOneWidget);
      expect(find.text("It's just you in this group so far."), findsOneWidget);
      await tester.tap(find.byKey(const Key('cardAddPeople')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addPersonName')), findsOneWidget);
    });

    testWidgets('dismiss hides it for the session', (tester) async {
      await tester.pumpWidget(app([me]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dismissAddPeople')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addPeopleCard')), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ExpensesPage)),
      );
      expect(container.read(addPeopleHintDismissedProvider), {_g});
    });

    testWidgets('not with someone else in the group', (tester) async {
      await tester.pumpWidget(app([me, _member('p-max', 'Max')]));
      await tester.pumpAndSettle();
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.byKey(const Key('addPeopleCard')), findsNothing);
    });

    testWidgets('not in a group I was removed from (read-only)', (
      tester,
    ) async {
      final removedMe = _member(
        '@me:x.org',
        'Me',
        mxid: '@me:x.org',
        status: 'removed',
      );
      await tester.pumpWidget(app([removedMe, _member('p-max', 'Max')]));
      await tester.pumpAndSettle();
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.byKey(const Key('addPeopleCard')), findsNothing);
    });

    testWidgets('German', (tester) async {
      await tester.pumpWidget(app([me], locale: const Locale('de')));
      await tester.pumpAndSettle();
      expect(find.text(de.addPeopleHint), findsOneWidget);
      expect(find.text(de.addPeople), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('expense form: discard changes?', () {
    Future<AppDatabase> seed() async {
      final db = openTestDatabase();
      await GroupsDao(db).upsertGroupLww(
        const GroupsCompanion(
          roomId: Value(_g),
          name: Value('Trip'),
          currency: Value('EUR'),
          updatedAt: Value(1000),
        ),
      );
      for (final u in ['@alice:x.org', '@bob:x.org']) {
        await MembersDao(db).upsertMemberLww(
          MembersCompanion(
            groupId: const Value(_g),
            userId: Value(u),
            matrixId: Value(u),
            status: const Value('active'),
            updatedAt: const Value(1000),
          ),
        );
      }
      return db;
    }

    Future<void> pumpForm(
      WidgetTester tester, {
      ExpenseModel? initial,
      Locale? locale,
    }) async {
      final db = await seed();
      addTearDown(db.close);
      final net = FakeMatrixNetwork();
      await tester.pumpWidget(
        testRouterApp(
          AddExpensePage(roomId: _g, initial: initial),
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
    }

    Finder field(String label) => find.widgetWithText(TextFormField, label);

    testWidgets('clean form: ← leaves without asking', (tester) async {
      await pumpForm(tester);
      expect(field('Description'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('host'), findsOneWidget);
    });

    testWidgets('clean form: Android back leaves without asking', (
      tester,
    ) async {
      await pumpForm(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('host'), findsOneWidget);
    });

    testWidgets('dirty form: ← asks; Keep editing stays, Discard leaves', (
      tester,
    ) async {
      await pumpForm(tester);
      await tester.enterText(field('Description'), 'Pizza');
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('keepEditing')));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('Pizza'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discardChanges')));
      await tester.pumpAndSettle();
      expect(find.text('host'), findsOneWidget);
      expect(find.text('Pizza'), findsNothing);
    });

    testWidgets('dirty form: Android back asks too (only a note typed)', (
      tester,
    ) async {
      await pumpForm(tester);
      await tester.enterText(find.byKey(const Key('expenseNote')), 'x');
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discardChanges')));
      await tester.pumpAndSettle();
      expect(find.text('host'), findsOneWidget);
    });

    testWidgets('typing and erasing again counts as clean', (tester) async {
      await pumpForm(tester);
      await tester.enterText(field('Amount'), '12');
      await tester.pump();
      await tester.enterText(field('Amount'), '');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('host'), findsOneWidget);
    });

    testWidgets('a changed split counts as a change', (tester) async {
      await pumpForm(tester);
      await tester.ensureVisible(find.text('Exact'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
    });

    testWidgets('edit: unchanged → no dialog; changed → asks (German)', (
      tester,
    ) async {
      final e = ExpenseModel(
        id: 'e1',
        roomId: _g,
        description: 'Dinner',
        amountCents: 4000,
        currency: 'EUR',
        paidBy: '@alice:x.org',
        splitsJson: '{"@alice:x.org":2000,"@bob:x.org":2000}',
        createdAt: 5000,
      );
      await pumpForm(tester, initial: e, locale: const Locale('de'));
      expect(find.text('Dinner'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(de.discardChangesTitle), findsNothing);
      expect(find.text('host'), findsOneWidget);

      // Open it again and change the description.
      await pumpForm(tester, initial: e, locale: const Locale('de'));
      await tester.enterText(find.text('Dinner'), 'Abendessen');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(de.discardChangesTitle), findsOneWidget);
      expect(find.text(de.keepEditing), findsOneWidget);
      expect(find.text(de.discard), findsOneWidget);
    });

    testWidgets('saving never asks', (tester) async {
      await pumpForm(tester);
      await tester.enterText(field('Description'), 'Pizza');
      await tester.enterText(field('Amount'), '20');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('host'), findsOneWidget);
    });
  });
}
