/// G64 (U4, U9, U10): people are entered while creating a group (chips),
/// *Add & next* + a duplicate-name hint in the *Add person* dialog, and a
/// balance warning when removing someone with an open balance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/create_group_page.dart';
import 'package:money_ledger/features/groups/group_exit_dialog.dart';
import 'package:money_ledger/features/groups/group_members_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/eventually.dart';
import 'helpers/fake_device_gateway.dart';
import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

/// A phone-sized window (360 × 800 dp).
void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  addTearDown(tester.view.reset);
}

bool _hasFocus(WidgetTester tester, Key key) => tester
    .widget<EditableText>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    )
    .focusNode
    .hasFocus;

/// Records the adder calls instead of writing.
class _FakeAdder extends MemberAdder {
  final added = <String>[];

  @override
  AsyncValue<void> build() => const AsyncData(null);

  @override
  Future<void> addLocal(String groupId, String name) async => added.add(name);

  final renamed = <String>[];

  @override
  Future<void> rename(
    String groupId,
    String participantId,
    String name,
  ) async => renamed.add('$participantId=$name');
}

class _FakeRemover extends MemberRemover {
  final removed = <String>[];

  @override
  AsyncValue<void> build() => const AsyncData(null);

  @override
  Future<void> remove(String groupId, String userId) async =>
      removed.add(userId);
}

MemberModel _member(String id, String name, {String? mxid}) => MemberModel(
  groupId: 'g1',
  userId: id,
  displayName: name,
  matrixId: mxid,
  status: 'active',
  updatedAt: 1,
);

void main() {
  group('create group with people (U4)', () {
    Future<List<MemberModel>> createWith(
      WidgetTester tester, {
      required AppDatabase db,
      required List<dynamic> overrides,
      Locale? locale,
      required Future<void> Function() addPeople,
    }) async {
      _phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db), ...overrides],
          child: MaterialApp.router(
            locale: locale ?? const Locale('en'),
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            routerConfig: GoRouter(
              initialLocation: '/new',
              routes: [
                GoRoute(
                  path: '/new',
                  builder: (_, _) => const CreateGroupPage(),
                ),
                GoRoute(
                  path: '/groups/:id/expenses',
                  builder: (_, _) =>
                      const Scaffold(body: Center(child: Text('opened'))),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Rom 2026');
      await addPeople();
      expect(tester.takeException(), isNull);
      late List<MemberModel> members;
      await tester.runAsync(() async {
        await tester.tap(find.byType(FilledButton));
        await eventually(
          () async => (await GroupsDao(db).getAllGroups()).isNotEmpty,
          tester: tester,
        );
        final groupId = (await GroupsDao(db).getAllGroups()).single.roomId;
        await eventually(
          () async => (await MembersDao(db).getMembers(groupId)).length >= 3,
          tester: tester,
        );
        members = await MembersDao(db).getMembers(groupId);
      });
      await tester.pumpAndSettle();
      // G46: the new group opens right away.
      expect(find.text('opened'), findsOneWidget);
      return members;
    }

    testWidgets('Matrix account: Enter adds a chip and keeps the focus, '
        '✕ removes one, a typed-but-not-added name counts too', (tester) async {
      final net = FakeMatrixNetwork();
      final db = openTestDatabase();
      addTearDown(db.close);
      const field = Key('createGroupPersonField');
      final members = await createWith(
        tester,
        db: db,
        overrides: [
          ledgerTransportProvider.overrideWith(
            (ref) => net.clientFor('@alice:x.org'),
          ),
        ],
        addPeople: () async {
          expect(find.text("Who's in?"), findsOneWidget);
          expect(find.byKey(const Key('createGroupYouChip')), findsOneWidget);
          await tester.tap(find.byKey(field));
          await tester.enterText(find.byKey(field), '  Anna ');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(find.widgetWithText(InputChip, 'Anna'), findsOneWidget);
          expect(_hasFocus(tester, field), isTrue);
          // Blank → nothing.
          await tester.enterText(find.byKey(field), '   ');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(find.byType(InputChip), findsOneWidget);
          // The + button adds as well.
          await tester.enterText(find.byKey(field), 'Ben');
          await tester.tap(find.byKey(const Key('createGroupPersonAdd')));
          await tester.pumpAndSettle();
          expect(find.byType(InputChip), findsNWidgets(2));
          // A long name wraps / ellipsizes without overflowing at 360 dp.
          await tester.enterText(
            find.byKey(field),
            'Maximiliane Theodora von Hohenzollern-Sigmaringen',
          );
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          // Remove Ben.
          await tester.tap(find.byTooltip('Remove Ben'));
          await tester.pumpAndSettle();
          expect(find.widgetWithText(InputChip, 'Ben'), findsNothing);
          // Typed, not added: still part of the group.
          await tester.enterText(find.byKey(field), 'Chris');
          await tester.pump();
        },
      );
      final byName = {for (final m in members) m.displayName: m};
      expect(members, hasLength(4));
      final me = members.singleWhere((m) => m.matrixId == '@alice:x.org');
      expect(me.userId, '@alice:x.org');
      for (final name in [
        'Anna',
        'Maximiliane Theodora von Hohenzollern-Sigmaringen',
        'Chris',
      ]) {
        final m = byName[name]!;
        expect(m.matrixId, isNull);
        expect(m.isActive, isTrue);
        // Signed by this device like any local edit (G6).
        expect(m.sig, isNotNull);
        expect(m.pendingSign, isFalse);
      }
      expect(byName.containsKey('Ben'), isFalse);
    });

    testWidgets('German, local mode: "Wer ist dabei?", "Du", people stored '
        'pendingSign, me claimed by the local account', (tester) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      const field = Key('createGroupPersonField');
      final members = await createWith(
        tester,
        db: db,
        locale: const Locale('de'),
        overrides: [
          ledgerTransportProvider.overrideWith(
            (ref) async => LocalOnlyTransport('Lea'),
          ),
        ],
        addPeople: () async {
          expect(find.text('Wer ist dabei?'), findsOneWidget);
          expect(find.widgetWithText(Chip, 'Du'), findsOneWidget);
          for (final name in ['Anna', 'Ben']) {
            await tester.enterText(find.byKey(field), name);
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await tester.pumpAndSettle();
          }
          // Duplicate hint (case-insensitive), adding stays possible.
          await tester.enterText(find.byKey(field), 'anna');
          await tester.pump();
          expect(
            find.textContaining('In dieser Gruppe gibt es schon Anna'),
            findsOneWidget,
          );
          await tester.enterText(find.byKey(field), '');
          await tester.pump();
        },
      );
      expect(members, hasLength(3));
      final me = members.singleWhere((m) => m.matrixId == kLocalAccountId);
      expect(me.displayName, 'Lea');
      final others = members.where((m) => m.matrixId == null).toList();
      expect(
        others.map((m) => m.displayName),
        unorderedEquals(['Anna', 'Ben']),
      );
      // Local mode can't sign: stored pendingSign, signed on connect (G40).
      expect(others.every((m) => m.pendingSign && m.sig == null), isTrue);
    });
  });

  group('members page (U9, U10)', () {
    List<Object> overrides(
      List<MemberModel> members, {
      _FakeAdder? adder,
      _FakeRemover? remover,
      List<ExpenseModel> expenses = const [],
    }) => [
      currentUserIdProvider.overrideWithValue('@alice:x.org'),
      groupMembersProvider('g1').overrideWith((ref) => Stream.value(members)),
      expensesForRoomProvider.overrideWith((ref, _) => Stream.value(expenses)),
      settlementsForRoomProvider.overrideWith(
        (ref, _) => Stream.value(const <SettlementModel>[]),
      ),
      if (adder != null) memberAdderProvider.overrideWith(() => adder),
      if (remover != null) memberRemoverProvider.overrideWith(() => remover),
      ...FakeTrustStore().overrides(FakeDeviceGateway(const [])),
    ];

    final people = [
      _member('@alice:x.org', 'Alice', mxid: '@alice:x.org'),
      _member('p-ben', 'Ben'),
    ];

    for (final locale in [const Locale('en'), const Locale('de')]) {
      testWidgets('${locale.languageCode}: Add & next keeps the dialog open '
          'for the next person; duplicate names get a hint', (tester) async {
        _phone(tester);
        final adder = _FakeAdder();
        final de = locale.languageCode == 'de';
        await tester.pumpWidget(
          testApp(
            const GroupMembersPage(roomId: 'g1'),
            overrides: overrides(people, adder: adder),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(de ? 'Personen' : 'People'), findsOneWidget);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        const name = Key('addPersonName');
        await tester.enterText(find.byKey(name), ' ben ');
        await tester.pump();
        expect(
          find.textContaining(
            de
                ? 'In dieser Gruppe gibt es schon Ben'
                : 'There is already a Ben in this group',
          ),
          findsOneWidget,
        );
        await tester.enterText(find.byKey(name), 'Chris');
        await tester.pump();
        await tester.tap(find.byKey(const Key('addPersonNext')));
        await tester.pumpAndSettle();
        expect(adder.added, ['Chris']);
        // Still open, empty, focused, "Added Chris".
        expect(find.byKey(name), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byKey(name)).controller!.text,
          isEmpty,
        );
        expect(_hasFocus(tester, name), isTrue);
        expect(
          find.text(de ? 'Chris hinzugefügt' : 'Added Chris'),
          findsOneWidget,
        );
        // A name added in this dialog counts for the hint too.
        await tester.enterText(find.byKey(name), 'chris');
        await tester.pump();
        expect(find.textContaining('Chris B.'), findsOneWidget);
        // …and can still be added (warn, allow).
        await tester.tap(find.byKey(const Key('addPersonSubmit')));
        await tester.pumpAndSettle();
        expect(adder.added, ['Chris', 'chris']);
        expect(find.byKey(name), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    // G75 (G64 leftover): renaming warns about a name another person has.
    for (final locale in [const Locale('en'), const Locale('de')]) {
      testWidgets('${locale.languageCode}: rename shows the duplicate-name '
          'hint, still allows it', (tester) async {
        _phone(tester);
        final adder = _FakeAdder();
        final l = locale.languageCode == 'de' ? de : en;
        final three = [...people, _member('p-chris', 'Chris')];
        await tester.pumpWidget(
          testApp(
            const GroupMembersPage(roomId: 'g1'),
            overrides: overrides(three, adder: adder),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        // Chris's ⋮ (the last one; Alice is "You").
        await tester.tap(find.byTooltip(l.options).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.rename));
        await tester.pumpAndSettle();
        const field = Key('textPromptField');
        // Its own name is no duplicate.
        expect(find.text(l.duplicatePersonRenameHint('Chris')), findsNothing);
        await tester.enterText(find.byKey(field), 'ben ');
        await tester.pump();
        expect(find.text(l.duplicatePersonRenameHint('Ben')), findsOneWidget);
        await tester.enterText(find.byKey(field), 'Christoph');
        await tester.pump();
        expect(find.text(l.duplicatePersonRenameHint('Ben')), findsNothing);
        await tester.enterText(find.byKey(field), 'Ben');
        await tester.pump();
        await tester.tap(find.text(l.ok));
        await tester.pumpAndSettle();
        expect(adder.renamed, ['p-chris=Ben']);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('local mode: Add & next with names only', (tester) async {
      _phone(tester);
      final adder = _FakeAdder();
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: [
            ...overrides(people, adder: adder),
            localModeActiveProvider.overrideWithValue(true),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addPersonMatrixId')), findsNothing);
      for (final n in ['Dora', 'Emil']) {
        await tester.enterText(find.byKey(const Key('addPersonName')), n);
        await tester.tap(find.byKey(const Key('addPersonNext')));
        await tester.pumpAndSettle();
      }
      expect(adder.added, ['Dora', 'Emil']);
      expect(find.text('Added Dora, Emil'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addPersonName')), findsNothing);
    });

    Future<void> openRemove(WidgetTester tester) async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from group'));
      await tester.pumpAndSettle();
    }

    testWidgets('removing someone with an open balance warns, and removing '
        'stays possible (U10)', (tester) async {
      _phone(tester);
      final remover = _FakeRemover();
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overrides(
            people,
            remover: remover,
            expenses: [
              const ExpenseModel(
                id: 'e1',
                roomId: 'g1',
                description: 'Dinner',
                amountCents: 4700,
                currency: 'EUR',
                paidBy: 'p-ben',
                splitsJson: '{"@alice:x.org":2350,"p-ben":2350}',
                createdAt: 1,
                updatedAt: 1,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openRemove(tester);
      expect(find.text('Ben still gets €23.50 back.'), findsOneWidget);
      expect(find.byKey(const Key('removeSettleFirst')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('removeConfirm')));
      await tester.pumpAndSettle();
      expect(remover.removed, ['p-ben']);
    });

    testWidgets('"Settle up first" opens the prefilled payment dialog and '
        'removes nobody', (tester) async {
      _phone(tester);
      final remover = _FakeRemover();
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overrides(
            people,
            remover: remover,
            expenses: [
              const ExpenseModel(
                id: 'e1',
                roomId: 'g1',
                description: 'Dinner',
                amountCents: 1000,
                currency: 'EUR',
                paidBy: '@alice:x.org',
                splitsJson: '{"@alice:x.org":500,"p-ben":500}',
                createdAt: 1,
                updatedAt: 1,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openRemove(tester);
      expect(find.text('Ben still owes €5.00.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('removeSettleFirst')));
      await tester.pumpAndSettle();
      expect(find.text('Record payment'), findsWidgets);
      expect(remover.removed, isEmpty);
    });

    testWidgets('a settled person: no warning, no "Settle up first"', (
      tester,
    ) async {
      final remover = _FakeRemover();
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overrides(people, remover: remover),
        ),
      );
      await tester.pumpAndSettle();
      await openRemove(tester);
      expect(find.byKey(const Key('removeBalanceWarning')), findsNothing);
      expect(find.byKey(const Key('removeSettleFirst')), findsNothing);
    });
  });

  group('pure helpers', () {
    test('duplicateNameOf: trimmed, case-insensitive', () {
      expect(duplicateNameOf(' alex ', ['Alex', 'Ben']), 'Alex');
      expect(duplicateNameOf('Alexa', ['Alex']), isNull);
      expect(duplicateNameOf('  ', ['']), isNull);
    });

    test('removalBalanceWarning per currency, EN + DE', () {
      final expenses = [
        const ExpenseModel(
          id: 'e1',
          roomId: 'g1',
          description: 'a',
          amountCents: 4700,
          currency: 'EUR',
          paidBy: 'p-ben',
          splitsJson: '{"me":2350,"p-ben":2350}',
          createdAt: 1,
        ),
        const ExpenseModel(
          id: 'e2',
          roomId: 'g1',
          description: 'b',
          amountCents: 1000,
          currency: 'CHF',
          paidBy: 'me',
          splitsJson: '{"me":500,"p-ben":500}',
          createdAt: 1,
        ),
      ];
      expect(
        removalBalanceWarning('p-ben', 'Ben', expenses, const [], en),
        'Ben still gets €23.50 back. Ben still owes CHF 5.00.',
      );
      expect(
        removalBalanceWarning('p-ben', 'Ben', expenses, const [], de),
        contains('Ben bekommt noch 23,50 € zurück.'),
      );
      expect(removalBalanceWarning('me', 'Me', const [], const [], en), isNull);
    });
  });
}
