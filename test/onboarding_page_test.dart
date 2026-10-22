/// OnboardingPage (Phase F, M5): the one-time intro marks the flag seen and
/// routes to groups. No matrix import — backed by an in-memory Drift DB.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/session/device_prefs.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/onboarding/onboarding_page.dart';
import 'package:money_ledger/features/onboarding/onboarding_provider.dart';

import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/eventually.dart';

void main() {
  testWidgets('renders the decentralized-model intro', (tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    // G39: the app was explained before login — only what's new now.
    expect(find.text("You're all set"), findsOneWidget);
    expect(find.text('Add anyone — Matrix or not'), findsOneWidget);
    expect(find.text('Syncs while you are away'), findsOneWidget);
    expect(find.text('Keep a copy'), findsOneWidget);
    expect(find.text('What is Matrix?'), findsNothing);
    expect(find.byKey(const Key('getStartedBtn')), findsOneWidget);
  });

  testWidgets(
    'no account (G40, G54): device-only, invite with a link, backup',
    (tester) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await tester.pumpWidget(
        _app(
          db,
          overrides: [
            devicePrefsStoreProvider.overrideWithValue(
              InMemoryDevicePrefsStore({
                'welcome_seen': '1',
                'local_profile': '{"name":"Lea","created_at":1}',
              }),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No account needed'), findsOneWidget);
      expect(find.text('Keep a copy'), findsOneWidget);
      // G54: "invite with a link" replaces "share later".
      expect(find.text('Invite with a link'), findsOneWidget);
      expect(find.textContaining('no account needed'), findsOneWidget);
      expect(find.text('Share later'), findsNothing);
      expect(find.textContaining('everything stays'), findsNothing);
      expect(find.text('Syncs while you are away'), findsNothing);
    },
  );

  testWidgets('"Get started" marks onboarding seen and navigates to groups', (
    tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('getStartedBtn')));
    // Drift writes resolve on the real event loop, not the fake test clock.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('getStartedBtn')));
      await eventually(
        () => SettingsDao(db).watchOnboardingSeen().first,
        tester: tester,
      );

      expect(await SettingsDao(db).watchOnboardingSeen().first, isTrue);
    });
    await tester.pumpAndSettle();
    expect(find.text('groups-home'), findsOneWidget);
  });

  testWidgets('a failed flag write shows an error and stays (G15)', (
    tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      _app(
        db,
        overrides: [
          onboardingControllerProvider.overrideWith(_FailingController.new),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('getStartedBtn')));
    await tester.tap(find.byKey(const Key('getStartedBtn')));
    await tester.pumpAndSettle();

    // G67: friendly text; the raw error only behind Details.
    expect(find.text("Couldn't save on this device"), findsOneWidget);
    expect(find.textContaining('disk full'), findsNothing);
    expect(find.text('groups-home'), findsNothing);
  });
}

class _FailingController extends OnboardingController {
  @override
  Future<void> markSeen() async => throw StateError('disk full');
}

Widget _app(AppDatabase db, {List<Object> overrides = const []}) {
  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
      GoRoute(
        path: '/groups',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('groups-home'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db), ...overrides.cast()],
    child: MaterialApp.router(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
    ),
  );
}
