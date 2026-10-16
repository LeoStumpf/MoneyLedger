/// G20 widget tests: login / SSO callback / register pages show friendly error
/// cards (raw text only behind "Details"), and the register page's web
/// fallback opens the server's sign-up page. No matrix import.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/matrix/auth_gateway.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/auth/login_page.dart';
import 'package:money_ledger/features/auth/register_page.dart';
import 'package:money_ledger/features/auth/sso_provider.dart';
import 'package:money_ledger/models/login_flows_result.dart';

import 'helpers/fake_auth_gateway.dart';
import 'helpers/l10n.dart';
import 'package:money_ledger/features/auth/register_flows.dart';

Widget _app(FakeAuthGateway gateway, String initial, {Stream<Uri>? ssoLinks}) {
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
      loginFlowsProvider.overrideWith(
        (ref, input) => Future.value(
          const LoginFlowsResult(
            resolvedUrl: 'https://matrix.org',
            hasPassword: true,
            hasSso: false,
            ssoProviders: [],
          ),
        ),
      ),
      ssoCallbackProvider.overrideWith(
        (_) => ssoLinks ?? const Stream<Uri>.empty(),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
    ),
  );
}

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('usernameField')), 'alice');
  await tester.enterText(find.byKey(const Key('passwordField')), 'secret');
  await tester.ensureVisible(find.byKey(const Key('signInBtn')));
  await tester.tap(find.byKey(const Key('signInBtn')));
  await tester.pumpAndSettle();
}

Future<void> _register(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('usernameField')), 'alice');
  await tester.enterText(find.byKey(const Key('passwordField')), 'password123');
  await tester.ensureVisible(find.byKey(const Key('createAccountBtn')));
  await tester.tap(find.byKey(const Key('createAccountBtn')));
  await tester.pumpAndSettle();
}

void main() {
  group('login page', () {
    testWidgets('wrong password: friendly title, raw text only in Details', (
      tester,
    ) async {
      final gateway = FakeAuthGateway()
        ..failWith = const AuthServerException(
          'M_FORBIDDEN',
          serverMessage: 'Invalid username or password',
        );
      await tester.pumpWidget(_app(gateway, '/login'));
      await tester.pumpAndSettle();

      await _signIn(tester);

      expect(find.byKey(const Key('authErrorCard')), findsOneWidget);
      expect(find.text(en.authWrongCredentialsTitle), findsOneWidget);
      // Raw server text hidden until "Details" is expanded.
      expect(find.textContaining('M_FORBIDDEN'), findsNothing);
      await tester.tap(find.text(en.authErrorDetails));
      await tester.pumpAndSettle();
      expect(find.textContaining('M_FORBIDDEN'), findsOneWidget);
      expect(find.text('groups-home'), findsNothing);
    });

    testWidgets('raw network error → "No internet connection"', (tester) async {
      final gateway = FakeAuthGateway()
        ..failWith = Exception(
          'ClientException with SocketException: '
          "Failed host lookup: 'matrix.org'",
        );
      await tester.pumpWidget(_app(gateway, '/login'));
      await tester.pumpAndSettle();

      await _signIn(tester);

      expect(find.text(en.authOfflineTitle), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
    });

    testWidgets('the error card clears on a successful retry', (tester) async {
      final gateway = FakeAuthGateway()
        ..failWith = const AuthServerException(
          'M_LIMIT_EXCEEDED',
          retryAfterMs: 5000,
        );
      await tester.pumpWidget(_app(gateway, '/login'));
      await tester.pumpAndSettle();
      await _signIn(tester);
      expect(find.text(en.authRateLimitedTitle), findsOneWidget);
      expect(find.text(en.authRateLimitedRetry(5)), findsOneWidget);

      gateway.failWith = null;
      await _signIn(tester);
      expect(find.text('groups-home'), findsOneWidget);
    });

    testWidgets('SSO callback with a rejected token → friendly message', (
      tester,
    ) async {
      final gateway = FakeAuthGateway()
        ..failWith = const AuthServerException(
          'M_FORBIDDEN',
          serverMessage: 'Invalid login token',
        );
      await tester.pumpWidget(
        _app(
          gateway,
          '/login',
          ssoLinks: Stream.value(
            Uri.parse(
              'moneyledger://sso-callback/?loginToken=t1&hs=https%3A%2F%2Fmatrix.org',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(en.authSsoTokenTitle), findsOneWidget);
      expect(find.textContaining('SSO login failed'), findsNothing);
      expect(find.textContaining('Invalid login token'), findsNothing);
    });
  });

  group('register page', () {
    testWidgets('username taken → friendly message', (tester) async {
      final gateway = FakeAuthGateway()
        ..failWith = const AuthServerException(
          'M_USER_IN_USE',
          serverMessage: 'User ID already taken.',
        );
      await tester.pumpWidget(_app(gateway, '/register'));
      await tester.pumpAndSettle();

      await _register(tester);

      expect(find.text(en.authUsernameTakenTitle), findsOneWidget);
      expect(find.textContaining('Registration failed'), findsNothing);
      expect(find.textContaining('M_USER_IN_USE'), findsNothing);
    });

    testWidgets('web fallback opens the advertised sign-up page', (
      tester,
    ) async {
      final launched = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          launched.add(call.arguments);
          return true;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        ),
      );

      final gateway = FakeAuthGateway()
        ..registerRequiresWeb = [kWebSignupStage]
        ..registerSignUpUrl = 'https://account.matrix.org/register';
      await tester.pumpWidget(_app(gateway, '/register'));
      await tester.pumpAndSettle();

      await _register(tester);
      await tester.ensureVisible(find.byKey(const Key('openSignUpWebsiteBtn')));
      await tester.tap(find.byKey(const Key('openSignUpWebsiteBtn')));
      await tester.pumpAndSettle();

      expect(
        launched.toString(),
        contains('https://account.matrix.org/register'),
      );
    });
  });
}
