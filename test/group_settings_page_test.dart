/// G65 (U22): the group settings page (was the 9-entry group ⋮ menu) and
/// the slimmed ⋮ menu — EN + DE at 360 dp, a shared Matrix group, a local
/// group and a read-only (removed) group.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/group_settings_page.dart';
import 'package:money_ledger/models/group_archive.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
const _me = '@me:x.org';
const _bob = '@bob:x.org';

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

const _group = GroupModel(roomId: _g, name: 'Rome 2026', currency: 'EUR');

/// A 360 × 780 dp phone.
void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  addTearDown(tester.view.reset);
}

List<dynamic> _overrides(
  List<MemberModel> members, {
  String me = _me,
  String? localProfile,
  Map<String, GroupArchive> archives = const {},
}) => [
  ...testOverrides(
    isLoggedIn: localProfile == null,
    localProfile: localProfile,
    members: members,
    groups: const [_group],
    archives: archives,
  ),
  currentUserIdProvider.overrideWith((_) => me),
  currentParticipantProvider.overrideWith(
    (ref, g) async => members.where((m) => m.matrixId == me).firstOrNull,
  ),
];

/// Groups list, group page and its settings under one router.
Widget _app(List<dynamic> overrides, {Locale? locale, String? start}) {
  final router = GoRouter(
    initialLocation: start ?? '/groups/$_g/settings',
    routes: [
      GoRoute(
        path: '/groups',
        builder: (_, _) => const Scaffold(body: Text('groups list')),
      ),
      GoRoute(
        path: '/groups/:id/expenses',
        builder: (_, _) => const ExpensesPage(roomId: _g),
      ),
      GoRoute(
        path: '/groups/:id/settings',
        builder: (_, _) => const GroupSettingsPage(roomId: _g),
      ),
      for (final sub in ['members', 'categories', 'reset'])
        GoRoute(
          path: '/groups/:id/$sub',
          builder: (_, _) => Scaffold(body: Text('$sub page')),
        ),
    ],
  );
  return ProviderScope(
    overrides: [...overrides],
    child: MaterialApp.router(
      locale: locale ?? const Locale('en'),
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
    ),
  );
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  final list = find.descendant(
    of: find.byKey(const Key('groupSettingsList')),
    matching: find.byType(Scrollable),
  );
  // Back to the top first: the target may be above the current position.
  await tester.drag(list, const Offset(0, 5000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(finder, 150, scrollable: list);
  await tester.pumpAndSettle();
}

ListTile _tile(WidgetTester tester, String key) =>
    tester.widget<ListTile>(find.byKey(Key(key)));

void main() {
  final shared = [
    _member(_me, 'Me', mxid: _me),
    _member(_bob, 'Bob', mxid: _bob),
  ];

  for (final (locale, l) in [
    (const Locale('en'), en),
    (const Locale('de'), de),
  ]) {
    testWidgets('shared group: every section, Leave last ($locale)', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_app(_overrides(shared), locale: locale));
      await tester.pumpAndSettle();

      expect(find.text(l.groupSettingsTitle), findsOneWidget);
      expect(
        find.text(l.groupNameCurrencyValue('Rome 2026', 'EUR')),
        findsOneWidget,
      );
      expect(_tile(tester, 'editGroupTile').enabled, isTrue);
      for (final header in [
        l.groupSectionGroup,
        l.membersTitle,
        l.settingsSectionData,
        l.groupSectionDevice,
        l.groupSectionExit,
      ]) {
        await _show(tester, find.text(header.toUpperCase()));
      }
      for (final key in [
        'categoriesTile',
        'peopleTile',
        'backupGroupTile',
        'exportCsvTile',
        'resetGroupTile',
        'archiveTile',
        'exitGroupTile',
      ]) {
        await _show(tester, find.byKey(Key(key)));
      }
      expect(_tile(tester, 'resetGroupTile').enabled, isTrue);
      expect(find.text(l.leaveGroup), findsOneWidget);
      expect(find.text(l.deleteGroup), findsNothing);
      expect(find.text(l.archiveGroup), findsOneWidget);
    });
  }

  testWidgets('the order of the sections', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_overrides(shared)));
    await tester.pumpAndSettle();
    final ys = [
      for (final h in ['GROUP', 'PEOPLE', 'DATA', 'ON THIS DEVICE'])
        tester.getTopLeft(find.text(h)).dy,
      tester.getTopLeft(find.text('LEAVE OR DELETE')).dy,
    ];
    expect(ys, [...ys]..sort());
  });

  testWidgets('tiles open the people / categories / reset pages', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_overrides(shared)));
    await tester.pumpAndSettle();
    for (final (key, page) in [
      ('peopleTile', 'members page'),
      ('categoriesTile', 'categories page'),
      ('resetGroupTile', 'reset page'),
    ]) {
      await _show(tester, find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(find.text(page), findsOneWidget);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
      nav.pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('an archived group offers Unarchive', (tester) async {
    await tester.pumpWidget(
      _app([
        ..._overrides(
          shared,
          archives: {_g: const GroupArchive(archivedAt: 1, fingerprint: 'fp')},
        ),
        groupLedgerFingerprintProvider.overrideWith((_, _) => 'fp'),
      ]),
    );
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const Key('archiveTile')));
    expect(find.text('Unarchive group'), findsOneWidget);
    expect(find.text(en.unarchiveTileBody), findsOneWidget);
  });

  testWidgets('read-only (removed) group: no edit, no reset, Delete', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        _overrides([
          _member(_me, 'Me', mxid: _me, status: 'removed'),
          _member(_bob, 'Bob', mxid: _bob),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(_tile(tester, 'editGroupTile').enabled, isFalse);
    await _show(tester, find.byKey(const Key('resetGroupTile')));
    expect(_tile(tester, 'resetGroupTile').enabled, isFalse);
    expect(_tile(tester, 'backupGroupTile').enabled, isTrue);
    await _show(tester, find.byKey(const Key('exitGroupTile')));
    expect(find.text('Delete group'), findsOneWidget);
    expect(find.text('Leave group'), findsNothing);
  });

  for (final (locale, l) in [
    (const Locale('en'), en),
    (const Locale('de'), de),
  ]) {
    testWidgets('local mode: Delete, edit + reset allowed ($locale)', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _app(
          _overrides(
            [_member('p1', 'Lea', mxid: kLocalAccountId), _member('p2', 'Max')],
            me: kLocalAccountId,
            localProfile: 'Lea',
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(_tile(tester, 'editGroupTile').enabled, isTrue);
      await _show(tester, find.byKey(const Key('resetGroupTile')));
      expect(_tile(tester, 'resetGroupTile').enabled, isTrue);
      await _show(tester, find.byKey(const Key('exitGroupTile')));
      expect(find.text(l.deleteGroup), findsOneWidget);
      expect(find.text(l.deleteGroupTileBody), findsOneWidget);
    });
  }

  group('group page ⋮ menu (G65)', () {
    testWidgets('only Add person, Archive and Group settings', (tester) async {
      await tester.pumpWidget(
        _app(_overrides(shared), start: '/groups/$_g/expenses'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      for (final key in [
        'addPersonMenuItem',
        'archiveMenuItem',
        'groupSettingsMenuItem',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      for (final gone in [
        'Edit group',
        'Categories',
        'Export CSV',
        'Back up this group',
        'Reset to an earlier state…',
        'Leave group',
        'Delete group',
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      await tester.tap(find.byKey(const Key('groupSettingsMenuItem')));
      await tester.pumpAndSettle();
      expect(find.byType(GroupSettingsPage), findsOneWidget);
    });

    testWidgets('tapping the title opens the group settings', (tester) async {
      await tester.pumpWidget(
        _app(_overrides(shared), start: '/groups/$_g/expenses'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('groupTitle')));
      await tester.pumpAndSettle();
      expect(find.byType(GroupSettingsPage), findsOneWidget);
    });
  });
}
