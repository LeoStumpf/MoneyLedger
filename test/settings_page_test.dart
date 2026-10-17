/// G65 (U28, U21): the settings page (was a bottom sheet on the groups page)
/// — sections for a Matrix account and for local mode, EN + DE at 360 dp,
/// sign-out (moved from the app bar), CSV import (moved from the app bar),
/// background sync (G31 / G33 / G36).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/background/background_scheduler.dart';
import 'package:money_ledger/core/background/background_sync_provider.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/settings/settings_page.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _me = '@anna:example.org';

/// A 360 × 780 dp phone.
void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  addTearDown(tester.view.reset);
}

List<dynamic> _matrix({List<dynamic> extra = const []}) => [
  ...testOverrides(isLoggedIn: true),
  currentUserIdProvider.overrideWith((_) => _me),
  ...extra,
];

Future<void> _pump(
  WidgetTester tester,
  List<dynamic> overrides, {
  Locale? locale,
}) async {
  await tester.pumpWidget(
    testApp(const SettingsPage(), overrides: overrides, locale: locale),
  );
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view in the settings list.
Future<void> _show(WidgetTester tester, Finder finder) async {
  final list = find.descendant(
    of: find.byKey(const Key('settingsList')),
    matching: find.byType(Scrollable),
  );
  // Back to the top first: the target may be above the current position.
  await tester.drag(list, const Offset(0, 5000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(finder, 150, scrollable: list);
  await tester.pumpAndSettle();
}

void main() {
  group('Matrix account', () {
    for (final (locale, l) in [
      (const Locale('en'), en),
      (const Locale('de'), de),
    ]) {
      testWidgets('sections in order, account + sign-out first ($locale)', (
        tester,
      ) async {
        _phone(tester);
        await _pump(tester, _matrix(), locale: locale);

        expect(find.text(l.settingsTitle), findsOneWidget);
        expect(find.text(l.settingsMatrixAccount), findsOneWidget);
        expect(find.text(_me), findsOneWidget);
        expect(find.byKey(const Key('signOutTile')), findsOneWidget);
        expect(find.byKey(const Key('localProfileNameTile')), findsNothing);

        final headers = [
          l.settingsSectionAccount,
          l.settingsSectionSync,
          l.settingsSectionBackup,
          l.settingsSectionData,
          l.settingsSectionAbout,
        ].map((h) => h.toUpperCase()).toList();
        for (final h in headers) {
          await _show(tester, find.text(h));
          expect(find.text(h), findsOneWidget, reason: h);
        }

        for (final key in [
          'verifiedOnlySwitch',
          'devicesTile',
          'backupPageTile', // G70: one entry → the backup page
          'importCsvTile',
          'aboutTile',
        ]) {
          await _show(tester, find.byKey(Key(key)));
          expect(find.byKey(Key(key)), findsOneWidget, reason: key);
        }
        expect(find.text(l.importCsv), findsOneWidget);
      });
    }

    testWidgets('the sections come in the documented order', (tester) async {
      // A tall surface: every header on screen at once.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 3000);
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        _matrix(
          extra: [backgroundSyncSupportedProvider.overrideWithValue(true)],
        ),
      );
      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      final order = [
        'ACCOUNT',
        'SYNC & DEVICES',
        'BACKUP & RESTORE',
        'DATA',
        'ABOUT',
        'DEBUG', // tests run in debug mode — release builds hide it
      ];
      final ys = [for (final h in order) y(h)];
      expect(ys, [...ys]..sort());
    });

    // G29: signing out asks first and explains the data stays on the device.
    for (final confirm in [false, true]) {
      testWidgets('sign out asks for confirmation (confirm: $confirm)', (
        tester,
      ) async {
        final spy = _SpyAuth();
        await _pump(
          tester,
          _matrix(extra: [authProvider.overrideWith(() => spy)]),
        );
        await tester.tap(find.byKey(const Key('signOutTile')));
        await tester.pumpAndSettle();
        expect(find.text('Sign out?'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('stay on this device'),
          ),
          findsOneWidget,
        );
        expect(spy.logouts, 0, reason: 'nothing happens before confirming');

        await tester.tap(
          confirm
              ? find.byKey(const Key('signOutConfirm'))
              : find.text('Cancel'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Sign out?'), findsNothing);
        expect(spy.logouts, confirm ? 1 : 0);
      });
    }

    testWidgets('a failed sign-out is reported, not swallowed (G15)', (
      tester,
    ) async {
      await _pump(
        tester,
        _matrix(extra: [authProvider.overrideWith(_FailingLogoutAuth.new)]),
      );
      await tester.tap(find.byKey(const Key('signOutTile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('signOutConfirm')));
      await tester.pumpAndSettle();
      // G67: a friendly message, the raw text only behind Details.
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.textContaining('server unreachable'), findsNothing);
      expect(find.byKey(const Key('actionErrorDetails')), findsOneWidget);
    });

    testWidgets('CSV import runs on the page and reports a failure', (
      tester,
    ) async {
      await _pump(tester, _matrix());
      await _show(tester, find.byKey(const Key('importCsvTile')));
      await tester.tap(find.byKey(const Key('importCsvTile')));
      await tester.pumpAndSettle();
      // No file picker in widget tests → the pick fails → a snackbar on the
      // settings page (G15: never silently).
      expect(find.textContaining('Import failed'), findsOneWidget);
    });

    testWidgets('Android shows the background-sync switch', (tester) async {
      await _pump(
        tester,
        _matrix(
          extra: [
            backgroundSyncSupportedProvider.overrideWithValue(true),
            backgroundSyncEnabledProvider.overrideWith(
              (_) => Stream.value(true),
            ),
          ],
        ),
      );
      expect(find.text('Background sync'), findsOneWidget);
      final sw = tester.widget<SwitchListTile>(
        find.byKey(const Key('backgroundSyncSwitch')),
      );
      expect(sw.value, isTrue);
    });

    testWidgets('web explains there is no background sync', (tester) async {
      await _pump(
        tester,
        _matrix(
          extra: [
            backgroundSyncSupportedProvider.overrideWithValue(false),
            backgroundSyncEnabledProvider.overrideWith(
              (_) => Stream.value(true),
            ),
          ],
        ),
      );
      expect(find.text('No background sync here'), findsOneWidget);
      expect(find.byKey(const Key('backgroundSyncSwitch')), findsNothing);
      expect(find.byKey(const Key('debugRunBackgroundSync')), findsNothing);
      expect(find.text('DEBUG'), findsNothing);
    });

    testWidgets('G36: debug builds offer a one-off background round', (
      tester,
    ) async {
      final scheduler = _OnceScheduler();
      await _pump(
        tester,
        _matrix(
          extra: [
            backgroundSyncSupportedProvider.overrideWithValue(true),
            backgroundSchedulerProvider.overrideWithValue(scheduler),
            backgroundSyncEnabledProvider.overrideWith(
              (_) => Stream.value(true),
            ),
          ],
        ),
      );
      // Tests run in debug mode (kDebugMode) — release builds hide it.
      final tile = find.byKey(const Key('debugRunBackgroundSync'));
      await _show(tester, tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(scheduler.runs, [kDebugBackgroundRunDelay]);
      expect(find.text('Background round queued.'), findsOneWidget);
    });
  });

  group('local mode', () {
    for (final (locale, l) in [
      (const Locale('en'), en),
      (const Locale('de'), de),
    ]) {
      testWidgets('account = local profile; no sync / devices / sign-out '
          '($locale)', (tester) async {
        _phone(tester);
        await _pump(tester, [
          ...testOverrides(localProfile: 'Lea'),
          backgroundSyncSupportedProvider.overrideWithValue(true),
        ], locale: locale);
        expect(
          find.text(l.settingsSectionAccount.toUpperCase()),
          findsOneWidget,
        );
        expect(find.text(l.localProfileName('Lea')), findsOneWidget);
        expect(find.byKey(const Key('connectAccountTile')), findsOneWidget);
        expect(find.byKey(const Key('signOutTile')), findsNothing);
        expect(find.byKey(const Key('accountTile')), findsNothing);
        expect(find.text(l.settingsSectionSync.toUpperCase()), findsNothing);
        expect(find.byKey(const Key('backgroundSyncSwitch')), findsNothing);
        expect(find.byKey(const Key('verifiedOnlySwitch')), findsNothing);
        expect(find.byKey(const Key('devicesTile')), findsNothing);
        for (final key in [
          'deleteLocalDataTile',
          'backupPageTile',
          'importCsvTile',
          'aboutTile',
        ]) {
          await _show(tester, find.byKey(Key(key)));
          expect(find.byKey(Key(key)), findsOneWidget, reason: key);
        }
        expect(find.byKey(const Key('debugRunBackgroundSync')), findsNothing);
      });
    }
  });
}

class _FailingLogoutAuth extends AuthNotifier {
  @override
  Future<void> logout() async {
    state = AsyncError(StateError('server unreachable'), StackTrace.current);
  }
}

class _SpyAuth extends AuthNotifier {
  int logouts = 0;

  @override
  Future<void> logout() async => logouts++;
}

class _OnceScheduler implements BackgroundScheduler {
  final runs = <Duration>[];
  @override
  Future<void> schedule() async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<void> runOnce({Duration delay = Duration.zero}) async =>
      runs.add(delay);
}
