/// G43: opening the login / register page contacts no homeserver — the
/// prefilled matrix.org included. Login flows are looked up only once the
/// user acts (confirms / edits the server, taps *Sign in* or SSO).
/// No matrix import: the real `loginFlowsProvider` runs on a FakeAuthGateway
/// that counts every lookup.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/auth/login_page.dart';
import 'package:money_ledger/features/auth/register_page.dart';
import 'package:money_ledger/features/auth/sso_provider.dart';
import 'package:money_ledger/models/login_flows_result.dart';

import '../helpers/fake_auth_gateway.dart';
import '../helpers/l10n.dart';

Widget _app(FakeAuthGateway gateway, String initial) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(
        path: '/groups',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('groups-home'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authGatewayProvider.overrideWith((ref) => gateway),
      ssoCallbackProvider.overrideWith((_) => const Stream<Uri>.empty()),
    ],
    child: MaterialApp.router(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
    ),
  );
}

const _ssoOnly = LoginFlowsResult(
  resolvedUrl: 'https://matrix-client.example.org',
  hasPassword: false,
  hasSso: true,
  ssoProviders: [],
);

void main() {
  testWidgets('the untouched login page performs zero gateway calls', (
    tester,
  ) async {
    final gateway = FakeAuthGateway();
    await tester.pumpWidget(_app(gateway, '/login'));
    await tester.pumpAndSettle();
    // Focus the server field and leave it without typing: no lookup either.
    await tester.tap(find.byKey(const Key('serverField')));
    await tester.pump();
    await tester.tapAt(Offset.zero);
    await tester.pump(const Duration(seconds: 2)); // past any debounce
    await tester.pumpAndSettle();

    expect(gateway.loginFlowsRequests, isEmpty);
    expect(gateway.requestsStarted, 0);
    // The optimistic form is usable all the same.
    expect(find.byKey(const Key('ssoBtn')), findsOneWidget);
    expect(find.byKey(const Key('signInBtn')), findsOneWidget);
    expect(find.byKey(const Key('checkServerBtn')), findsOneWidget);
  });

  testWidgets('the untouched register page performs zero gateway calls', (
    tester,
  ) async {
    final gateway = FakeAuthGateway();
    await tester.pumpWidget(_app(gateway, '/register'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(gateway.loginFlowsRequests, isEmpty);
    expect(gateway.requestsStarted, 0);
  });

  testWidgets('"Check server" looks the flows up and refines the form', (
    tester,
  ) async {
    final gateway = FakeAuthGateway(flows: _ssoOnly);
    await tester.pumpWidget(_app(gateway, '/login'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('checkServerBtn')));
    await tester.pumpAndSettle();

    expect(gateway.loginFlowsRequests, ['matrix.org']);
    expect(find.byKey(const Key('passwordField')), findsNothing);
    expect(find.byKey(const Key('ssoBtn')), findsOneWidget);
    expect(find.byKey(const Key('checkServerBtn')), findsNothing);
    expect(
      find.text(en.resolvedTo('https://matrix-client.example.org')),
      findsOneWidget,
    );
  });

  testWidgets('editing the server looks it up once typing pauses', (
    tester,
  ) async {
    final gateway = FakeAuthGateway();
    await tester.pumpWidget(_app(gateway, '/login'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('serverField')), 'example.org');
    await tester.pump(const Duration(milliseconds: 100));
    expect(gateway.loginFlowsRequests, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(gateway.loginFlowsRequests, ['example.org']);
  });

  testWidgets('Sign in without checking first: lookup, then login on the '
      'resolved server', (tester) async {
    final gateway = FakeAuthGateway(); // resolves to https://fake.test
    await tester.pumpWidget(_app(gateway, '/login'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('usernameField')), 'alice');
    await tester.enterText(find.byKey(const Key('passwordField')), 'pw');
    await tester.tap(find.byKey(const Key('signInBtn')));
    await tester.pumpAndSettle();

    expect(gateway.loginFlowsRequests, ['matrix.org']);
    expect(gateway.requestsStarted, 1);
    expect(gateway.userId, '@alice:fake.test');
    expect(find.text('groups-home'), findsOneWidget);
  });

  testWidgets('Sign in on an SSO-only server: no doomed password attempt — '
      'the form switches to SSO', (tester) async {
    final gateway = FakeAuthGateway(flows: _ssoOnly);
    await tester.pumpWidget(_app(gateway, '/login'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('usernameField')), 'alice');
    await tester.enterText(find.byKey(const Key('passwordField')), 'pw');
    await tester.tap(find.byKey(const Key('signInBtn')));
    await tester.pumpAndSettle();

    expect(gateway.loginFlowsRequests, ['matrix.org']);
    expect(gateway.requestsStarted, 0);
    expect(find.byKey(const Key('passwordField')), findsNothing);
    expect(find.byKey(const Key('ssoBtn')), findsOneWidget);
  });
}
