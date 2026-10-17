/// G46: UX quick wins — the claim picker's dismiss is a cancel, a new group
/// opens right away, an empty group with only me offers "Add people".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/create_group_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/settings/settings_page.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/eventually.dart';
import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';

MemberModel _member(String id, String name, {String? mxid}) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  matrixId: mxid,
  status: 'active',
  updatedAt: 1,
);

void main() {
  group('claim picker (dismiss = cancel)', () {
    Widget app() => testApp(
      const ExpensesPage(roomId: _g),
      overrides: [
        ...testOverrides(
          isLoggedIn: true,
          // A local participant exists, but this device claims nobody.
          members: [_member('p-bobby', 'Bobby')],
        ),
        currentParticipantProvider.overrideWith(
          (ref, g) => Future<MemberModel?>.value(null),
        ),
      ],
    );

    testWidgets('tapping outside the picker does nothing', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Choose'));
      await tester.pumpAndSettle();
      expect(find.text("I'm someone new"), findsOneWidget);

      // Barrier tap (top-left corner, outside the dialog).
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text("I'm someone new"), findsNothing);
      // No name prompt — dismissing isn't "I'm someone new".
      expect(find.text('Your name'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      // The banner is still there to choose later.
      expect(find.widgetWithText(TextButton, 'Choose'), findsOneWidget);
    });

    testWidgets('Back closes the picker without asking for a name', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Choose'));
      await tester.pumpAndSettle();

      final nav = Navigator.of(tester.element(find.text("I'm someone new")));
      await nav.maybePop();
      await tester.pumpAndSettle();
      expect(find.text("I'm someone new"), findsNothing);
      expect(find.text('Your name'), findsNothing);
    });

    testWidgets('"I\'m someone new" still asks for a name', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'm someone new"));
      await tester.pumpAndSettle();
      expect(find.text('Your name'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('empty group → "Add people"', () {
    Widget app(
      List<MemberModel> members, {
      String? localProfile,
      Locale? locale,
    }) => testApp(
      const ExpensesPage(roomId: _g),
      locale: locale,
      overrides: [
        ...testOverrides(
          isLoggedIn: localProfile == null,
          localProfile: localProfile,
          members: members,
        ),
        currentParticipantProvider.overrideWith(
          (ref, g) => Future<MemberModel?>.value(members.first),
        ),
      ],
    );

    final me = _member('@me:x.org', 'Me', mxid: '@me:x.org');

    testWidgets('only me → CTA opens the add-person dialog (Matrix ID too)', (
      tester,
    ) async {
      await tester.pumpWidget(app([me]));
      await tester.pumpAndSettle();
      expect(find.textContaining("It's just you so far"), findsOneWidget);
      await tester.tap(find.byKey(const Key('emptyAddPeople')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addPersonName')), findsOneWidget);
      expect(find.byKey(const Key('addPersonMatrixId')), findsOneWidget);
    });

    testWidgets('local mode → name only', (tester) async {
      final self = _member('p-me', 'Lea', mxid: 'local:self');
      await tester.pumpWidget(app([self], localProfile: 'Lea'));
      await tester.pumpAndSettle();
      expect(find.text('Add people'), findsOneWidget);
      await tester.tap(find.byKey(const Key('emptyAddPeople')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addPersonName')), findsOneWidget);
      expect(find.byKey(const Key('addPersonMatrixId')), findsNothing);
    });

    testWidgets('German', (tester) async {
      await tester.pumpWidget(app([me], locale: const Locale('de')));
      await tester.pumpAndSettle();
      expect(find.text('Personen hinzufügen'), findsOneWidget);
      expect(find.textContaining('Bisher bist nur du'), findsOneWidget);
    });

    testWidgets('someone else in the group → the normal empty state', (
      tester,
    ) async {
      await tester.pumpWidget(app([me, _member('p-max', 'Max')]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('expensesEmpty')), findsOneWidget);
      expect(find.byKey(const Key('emptyAddPeople')), findsNothing);
      expect(find.textContaining('Add the first expense'), findsOneWidget);
    });
  });

  group('create group', () {
    testWidgets('opens the new group; Back lands on the groups list', (
      tester,
    ) async {
      final net = FakeMatrixNetwork();
      final db = openTestDatabase();
      addTearDown(db.close);
      final router = GoRouter(
        initialLocation: '/groups',
        routes: [
          GoRoute(
            path: '/groups',
            builder: (_, _) => const Scaffold(body: Text('groups list')),
          ),
          GoRoute(
            path: '/groups/create',
            builder: (_, _) => const CreateGroupPage(),
          ),
          GoRoute(
            path: '/groups/:id/expenses',
            builder: (_, s) =>
                Scaffold(body: Text('group:${s.pathParameters['id']}')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
            appDatabaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            routerConfig: router,
          ),
        ),
      );
      router.push('/groups/create');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Holiday');

      late String id;
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Create'));
        await eventually(
          () async => (await GroupsDao(db).getAllGroups()).isNotEmpty,
          tester: tester,
        );
        id = (await GroupsDao(db).getAllGroups()).single.roomId;
        await eventually(
          () async => find.text('group:$id').evaluate().isNotEmpty,
          tester: tester,
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('group:$id'), findsOneWidget);

      // The create page was replaced: Back goes to the list.
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('groups list'), findsOneWidget);
      expect(find.text('New group'), findsNothing);
    });
  });

  testWidgets('Delete local data → a signed-out device lands on the welcome', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        const SettingsPage(),
        overrides: testOverrides(localProfile: 'Lea'),
      ),
    );
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    expect(c.read(signedOutLandingProvider), SignedOutLanding.login);

    await tester.tap(find.byKey(const Key('deleteLocalDataTile')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('deleteLocalDataConfirm')));
      await eventually(
        () async => c.read(localProfileProvider) == null,
        tester: tester,
      );
    });
    expect(c.read(signedOutLandingProvider), SignedOutLanding.welcome);
    expect(c.read(appSessionProvider), AppSessionKind.signedOut);
  });
}
