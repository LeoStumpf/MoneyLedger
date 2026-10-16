/// OnboardingPage (Phase F, M5): the one-time intro marks the flag seen and
/// routes to groups. No matrix import — backed by an in-memory Drift DB.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/onboarding/onboarding_page.dart';

import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';

void main() {
  testWidgets('renders the decentralized-model intro', (tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to MoneyLedger'), findsOneWidget);
    expect(find.textContaining('lives on your device'), findsOneWidget);
    expect(find.byKey(const Key('getStartedBtn')), findsOneWidget);
  });

  testWidgets('"Get started" marks onboarding seen and navigates to groups',
      (tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('getStartedBtn')));
    // Drift writes resolve on the real event loop, not the fake test clock.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('getStartedBtn')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();

      expect(await SettingsDao(db).watchOnboardingSeen().first, isTrue);
    });
    await tester.pumpAndSettle();
    expect(find.text('groups-home'), findsOneWidget);
  });
}

Widget _app(AppDatabase db) {
  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
          path: '/onboarding', builder: (_, _) => const OnboardingPage()),
      GoRoute(
          path: '/groups',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('groups-home')))),
    ],
  );
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp.router(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        routerConfig: router),
  );
}
