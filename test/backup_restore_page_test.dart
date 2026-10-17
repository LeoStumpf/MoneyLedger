/// G70 (U23): the "Backup & restore" page — decision aid + three blocks
/// (backup file, restore points, undo in one group), EN + DE at 360 dp,
/// Matrix vs local mode vs web (no snapshot store), and the navigation from
/// the settings page / to the restore points and a group's reset page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/features/backup/backup_restore_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/history/restore_points.dart';
import 'package:money_ledger/features/history/restore_points_page.dart';
import 'package:money_ledger/features/settings/settings_page.dart';
import 'package:money_ledger/models/group_model.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _me = '@anna:example.org';

const _groups = [
  GroupModel(
    roomId: 'g-rome',
    name: 'Rome 2026',
    currency: 'EUR',
    updatedAt: 1,
  ),
  GroupModel(roomId: 'g-flat', name: 'Flat', currency: 'EUR', updatedAt: 1),
];

/// A 360 × 780 dp phone.
void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  addTearDown(tester.view.reset);
}

List<dynamic> _matrix({
  bool snapshots = true,
  List<GroupModel> groups = _groups,
  int? lastBackupAt,
}) => [
  ...testOverrides(
    isLoggedIn: true,
    groups: groups,
    lastBackupAt: lastBackupAt,
  ),
  currentUserIdProvider.overrideWith((_) => _me),
  snapshotsSupportedProvider.overrideWithValue(snapshots),
];

List<dynamic> _local({bool snapshots = true}) => [
  ...testOverrides(localProfile: 'Lea', groups: _groups),
  snapshotsSupportedProvider.overrideWithValue(snapshots),
];

/// The page under a router with stubs for where it leads.
Widget _app(
  List<dynamic> overrides, {
  Locale? locale,
  String initial = kBackupLocation,
}) {
  final router = GoRouter(
    initialLocation: '/host',
    routes: [
      GoRoute(
        path: '/host',
        builder: (_, _) => const Scaffold(body: Text('host')),
      ),
      GoRoute(path: kSettingsLocation, builder: (_, _) => const SettingsPage()),
      GoRoute(
        path: kBackupLocation,
        builder: (_, _) => const BackupRestorePage(),
      ),
      GoRoute(
        path: kRestorePointsLocation,
        builder: (_, _) => const Scaffold(body: Text('restore points stub')),
      ),
      GoRoute(
        path: '/groups/:id/reset',
        builder: (_, s) =>
            Scaffold(body: Text('reset ${s.pathParameters['id']}')),
      ),
    ],
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => router.push(initial));
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

Finder get _list => find.descendant(
  of: find.byKey(const Key('backupPageList')),
  matching: find.byType(Scrollable),
);

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 150, scrollable: _list);
  await tester.pumpAndSettle();
}

void main() {
  for (final (locale, l) in [
    (const Locale('en'), en),
    (const Locale('de'), de),
  ]) {
    testWidgets('Matrix: decision aid + three blocks at 360 dp ($locale)', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_app(_matrix(), locale: locale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text(l.settingsSectionBackup), findsOneWidget); // app bar
      expect(find.text(l.backupDecisionTitle), findsOneWidget);
      expect(find.text(l.backupDecisionUndo), findsOneWidget);
      expect(find.text(l.backupDecisionGroup), findsOneWidget);
      expect(find.text(l.backupDecisionDevice), findsOneWidget);
      expect(find.text(l.backupDecisionPhone), findsOneWidget);
      // A Matrix account: shared groups come back from the others.
      expect(find.text(l.backupDecisionPhoneMatrix), findsOneWidget);

      for (final f in [
        find.text(l.backupFileSection.toUpperCase()),
        find.text(l.backupFileIntro),
        find.text(l.lastBackupNever),
        find.byKey(const Key('backupExportTile')),
        find.byKey(const Key('backupRestoreTile')),
        find.text(l.backupFileGroupHint),
        find.text(l.restorePointsTitle.toUpperCase()),
        find.text(l.backupRestorePointsIntro),
        find.byKey(const Key('restorePointsTile')),
        find.text(l.backupUndoSection.toUpperCase()),
        find.text(l.backupUndoIntro),
        find.byKey(const Key('resetPickGroupTile')),
      ]) {
        await _show(tester, f);
        expect(f, findsOneWidget);
      }
      expect(find.byKey(const Key('noSnapshotsHint')), findsNothing);
      expect(find.text(l.backupUndoPickGroupBody), findsOneWidget);
      // Nothing overflows on a 360 dp phone.
      expect(tester.takeException(), isNull);
    });

    testWidgets('local mode: no "comes back from the others" ($locale)', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_app(_local(), locale: locale));
      await tester.pumpAndSettle();
      expect(find.text(l.backupDecisionPhone), findsOneWidget);
      expect(find.text(l.backupDecisionPhoneMatrix), findsNothing);
      await _show(tester, find.byKey(const Key('backupExportTile')));
      await _show(tester, find.byKey(const Key('resetPickGroupTile')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('web / no snapshots: restore points explained away '
        '($locale)', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(_matrix(snapshots: false), locale: locale));
      await tester.pumpAndSettle();
      expect(find.text(l.backupDecisionDeviceWeb), findsOneWidget);
      expect(find.text(l.backupDecisionDevice), findsNothing);
      await _show(tester, find.byKey(const Key('noSnapshotsHint')));
      expect(find.text(l.backupRestorePointsWeb), findsOneWidget);
      expect(find.byKey(const Key('restorePointsTile')), findsNothing);
      // The other blocks stay.
      await _show(tester, find.byKey(const Key('resetPickGroupTile')));
      await tester.drag(_list, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await _show(tester, find.byKey(const Key('backupExportTile')));
      expect(find.byKey(const Key('backupExportTile')), findsOneWidget);
    });
  }

  testWidgets('shows the last backup date', (tester) async {
    final at = DateTime(2026, 10, 1, 12).millisecondsSinceEpoch;
    await tester.pumpWidget(_app(_matrix(lastBackupAt: at)));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const Key('lastBackupText')));
    expect(find.textContaining('Last backup: '), findsOneWidget);
    expect(find.text('Last backup: never'), findsNothing);
  });

  testWidgets('restore points tile opens the restore points page', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_matrix()));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const Key('restorePointsTile')));
    await tester.tap(find.byKey(const Key('restorePointsTile')));
    await tester.pumpAndSettle();
    expect(find.text('restore points stub'), findsOneWidget);
  });

  testWidgets('undo in one group: pick a group → its reset page', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_app(_matrix()));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const Key('resetPickGroupTile')));
    await tester.tap(find.byKey(const Key('resetPickGroupTile')));
    await tester.pumpAndSettle();

    expect(find.text(en.backupUndoPickTitle), findsOneWidget);
    // Sorted by name.
    final flat = tester.getTopLeft(find.text('Flat')).dy;
    final rome = tester.getTopLeft(find.text('Rome 2026')).dy;
    expect(flat, lessThan(rome));

    await tester.tap(find.byKey(const Key('resetPickGroup-g-rome')));
    await tester.pumpAndSettle();
    expect(find.text('reset g-rome'), findsOneWidget);
  });

  testWidgets('no groups: the pick-group tile is disabled', (tester) async {
    await tester.pumpWidget(_app(_matrix(groups: const [])));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const Key('resetPickGroupTile')));
    final tile = tester.widget<ListTile>(
      find.byKey(const Key('resetPickGroupTile')),
    );
    expect(tile.enabled, isFalse);
    expect(find.text(en.backupUndoNoGroups), findsOneWidget);
  });

  testWidgets('the settings page has one compact entry that opens the page', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_app(_matrix(), initial: kSettingsLocation));
    await tester.pumpAndSettle();
    final settingsList = find.descendant(
      of: find.byKey(const Key('settingsList')),
      matching: find.byType(Scrollable),
    );
    final tile = find.byKey(const Key('backupPageTile'));
    await tester.scrollUntilVisible(tile, 150, scrollable: settingsList);
    await tester.pumpAndSettle();
    expect(find.text(en.lastBackupNever), findsOneWidget);
    expect(find.text(en.settingsBackupTileBody), findsOneWidget);
    // The flows themselves moved to the page.
    expect(find.byKey(const Key('backupExportTile')), findsNothing);
    expect(find.byKey(const Key('restorePointsTile')), findsNothing);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(BackupRestorePage), findsOneWidget);
  });
}
