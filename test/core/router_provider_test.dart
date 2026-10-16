/// G25 + G15: the real `routerProvider` — its `refreshListenable` re-runs the
/// redirect when the login state or the onboarding flag changes, and a
/// signed-in user whose per-account onboarding flag is still loading sees the
/// neutral splash (never the groups page first, then onboarding later). Also
/// covers [OnboardingGate] (unknown / account switch / timeout). No matrix
/// import: fake auth gateway, in-memory DBs, idle transport.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/router.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/auth/sso_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/onboarding/onboarding_provider.dart';
import 'package:money_ledger/models/login_flows_result.dart';

import '../helpers/fake_auth_gateway.dart';
import '../helpers/l10n.dart';

/// Per-account controllable onboarding flag: the test decides when (and
/// whether) each account's flag "loads".
class _Flags {
  final _controllers = <String?, StreamController<bool>>{};
  StreamController<bool> of(String? account) => _controllers.putIfAbsent(
      account, () => StreamController<bool>.broadcast());
  Future<void> close() async {
    for (final c in _controllers.values) {
      await c.close();
    }
  }
}

void main() {
  late FakeAuthGateway gateway;
  late _Flags flags;
  late ProviderContainer c;

  ProviderContainer makeContainer({Duration? timeout}) {
    final container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWith((ref) => gateway),
      loginFlowsProvider.overrideWith((ref, input) =>
          Future.value(LoginFlowsResult.empty)),
      ssoCallbackProvider.overrideWith((_) => const Stream<Uri>.empty()),
      // Transport never resolves: the sync engines construct but stay idle.
      ledgerTransportProvider
          .overrideWith((ref) => Completer<LedgerTransport>().future),
      accountDatabaseOpenerProvider.overrideWithValue(
          (_) => AppDatabase.forTesting(NativeDatabase.memory())),
      onboardingSeenStreamProvider.overrideWith((ref) {
        final account = ref.watch(accountUserIdProvider);
        if (account == null) return Stream.value(true);
        return flags.of(account).stream;
      }),
      if (timeout != null) onboardingFlagTimeoutProvider.overrideWithValue(timeout),
    ]);
    // The app keeps these alive (appDatabaseProvider / the router listen).
    container.listen(accountUserIdProvider, (_, _) {});
    return container;
  }

  setUp(() {
    gateway = FakeAuthGateway();
    flags = _Flags();
  });

  tearDown(() async {
    c.dispose();
    gateway.dispose();
    await flags.close();
  });

  Future<void> login(String user) => c.read(authProvider.notifier).login(
      resolvedHomeserver: 'https://x.test', username: user, password: 'pw');

  group('OnboardingGate', () {
    setUp(() => c = makeContainer(timeout: const Duration(seconds: 30)));

    OnboardingStatus gate() => c.read(onboardingGateProvider);

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('signed out → seen (router never forces onboarding then)', () {
      c.listen(onboardingGateProvider, (_, _) {});
      expect(gate(), OnboardingStatus.seen);
    });

    test('signed in: unknown until the flag loads, then seen / not seen',
        () async {
      c.listen(onboardingGateProvider, (_, _) {});
      await login('alice');
      await settle();
      expect(gate(), OnboardingStatus.unknown);

      flags.of('@alice:x.test').add(false);
      await settle();
      expect(gate(), OnboardingStatus.notSeen);

      flags.of('@alice:x.test').add(true);
      await settle();
      expect(gate(), OnboardingStatus.seen);
    });

    test("an account switch never reuses the previous account's flag",
        () async {
      c.listen(onboardingGateProvider, (_, _) {});
      await login('alice');
      await settle();
      flags.of('@alice:x.test').add(true);
      await settle();
      expect(gate(), OnboardingStatus.seen);

      await c.read(authProvider.notifier).logout();
      await settle();
      await login('bob');
      await settle();
      // Bob's flag hasn't loaded: unknown, not alice's (or signed-out) "seen".
      expect(gate(), OnboardingStatus.unknown);
      flags.of('@bob:x.test').add(false);
      await settle();
      expect(gate(), OnboardingStatus.notSeen);
    });

    test('a failing flag stream counts as seen', () async {
      c.listen(onboardingGateProvider, (_, _) {});
      await login('alice');
      await settle();
      flags.of('@alice:x.test').addError(StateError('db open failed'));
      await settle();
      expect(gate(), OnboardingStatus.seen);
    });
  });

  test('OnboardingGate: a flag that never loads times out to seen and latches',
      () async {
    c = makeContainer(timeout: const Duration(milliseconds: 50));
    c.listen(onboardingGateProvider, (_, _) {});
    await login('alice');
    await Future<void>.delayed(Duration.zero);
    expect(c.read(onboardingGateProvider), OnboardingStatus.unknown);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(c.read(onboardingGateProvider), OnboardingStatus.seen);

    // A late "not seen" no longer yanks the user to onboarding mid-use.
    flags.of('@alice:x.test').add(false);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(onboardingGateProvider), OnboardingStatus.seen);
  });

  group('routerProvider refreshListenable', () {
    Future<GoRouter> pumpApp(WidgetTester tester) async {
      // The app's root widget watches the router; Riverpod 3 pauses an
      // unlistened provider (and with it its refresh listeners).
      c.listen(routerProvider, (_, _) {});
      final router = c.read(routerProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        routerConfig: router),
      ));
      await tester.pumpAndSettle();
      return router;
    }

    String location(GoRouter r) =>
        r.routerDelegate.currentConfiguration.uri.path;

    Future<void> flush(WidgetTester tester) async {
      // Drift / stream work completes on the real event loop.
      // Not pumpAndSettle: the splash spinner animates forever, and settling
      // would advance the fake clock far enough to fire the flag timeout.
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    testWidgets(
        'login → splash while the flag loads → onboarding → groups; '
        'logout → login', (tester) async {
      c = makeContainer(timeout: const Duration(minutes: 5));
      final router = await pumpApp(tester);
      expect(location(router), '/login');

      await tester.runAsync(() => login('alice'));
      await flush(tester);
      expect(location(router), '/splash');
      expect(find.byKey(const Key('splashPage')), findsOneWidget);

      flags.of('@alice:x.test').add(false);
      await flush(tester);
      expect(location(router), '/onboarding');
      expect(find.text('Welcome to MoneyLedger'), findsOneWidget);

      flags.of('@alice:x.test').add(true);
      await flush(tester);
      expect(location(router), '/groups');

      await tester.runAsync(() => c.read(authProvider.notifier).logout());
      await flush(tester);
      expect(location(router), '/login');
    });

    testWidgets('a returning user goes splash → groups (never onboarding)',
        (tester) async {
      c = makeContainer(timeout: const Duration(minutes: 5));
      final router = await pumpApp(tester);

      await tester.runAsync(() => login('alice'));
      await flush(tester);
      expect(location(router), '/splash');

      flags.of('@alice:x.test').add(true);
      await flush(tester);
      expect(location(router), '/groups');
    });

    testWidgets('a flag that never loads leaves the splash after the timeout',
        (tester) async {
      c = makeContainer(timeout: const Duration(seconds: 1));
      final router = await pumpApp(tester);

      await tester.runAsync(() => login('alice'));
      await flush(tester);
      expect(location(router), '/splash');

      // The gate's timer runs on the fake test clock.
      await tester.pump(const Duration(seconds: 2));
      await flush(tester);
      expect(location(router), '/groups');
    });
  });
}
