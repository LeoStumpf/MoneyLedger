/// RegisterPage (Phase F, M4): in-app sign-up against the FakeAuthGateway —
/// success navigates to groups; a captcha/email/terms server shows the web
/// fallback. No matrix import.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/auth/register_page.dart';

import 'helpers/fake_auth_gateway.dart';

Widget _app(FakeAuthGateway gateway) {
  final router = GoRouter(
    initialLocation: '/register',
    routes: [
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(
          path: '/groups',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('groups-home')))),
      GoRoute(
          path: '/login',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('login-home')))),
    ],
  );
  return ProviderScope(
    overrides: [authGatewayProvider.overrideWith((ref) => gateway)],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('usernameField')), 'alice');
  await tester.enterText(
      find.byKey(const Key('passwordField')), 'password123');
}

void main() {
  testWidgets('renders the registration form', (tester) async {
    await tester.pumpWidget(_app(FakeAuthGateway()));
    await tester.pumpAndSettle();

    expect(find.text('Create account'), findsWidgets);
    expect(find.byKey(const Key('serverField')), findsOneWidget);
    expect(find.byKey(const Key('createAccountBtn')), findsOneWidget);
  });

  testWidgets('a successful registration navigates to groups', (tester) async {
    await tester.pumpWidget(_app(FakeAuthGateway()));
    await tester.pumpAndSettle();

    await _fillForm(tester);
    await tester.tap(find.byKey(const Key('createAccountBtn')));
    await tester.pumpAndSettle();

    expect(find.text('groups-home'), findsOneWidget);
  });

  testWidgets('a captcha/terms server shows the web fallback', (tester) async {
    final gateway = FakeAuthGateway()
      ..registerRequiresWeb = ['a CAPTCHA', 'accepting the terms of service'];
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await _fillForm(tester);
    await tester.tap(find.byKey(const Key('createAccountBtn')));
    await tester.pumpAndSettle();

    expect(find.text('Register on the web'), findsOneWidget);
    expect(find.textContaining('a CAPTCHA'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open homeserver website'),
        findsOneWidget);
    // Stayed on the register page.
    expect(find.text('groups-home'), findsNothing);
  });

  testWidgets('a short password is rejected before any network call',
      (tester) async {
    final gateway = FakeAuthGateway();
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('usernameField')), 'alice');
    await tester.enterText(find.byKey(const Key('passwordField')), 'short');
    await tester.tap(find.byKey(const Key('createAccountBtn')));
    await tester.pumpAndSettle();

    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(gateway.isLoggedIn, isFalse);
  });
}
