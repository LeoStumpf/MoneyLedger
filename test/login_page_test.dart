import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/auth/login_page.dart';
import 'package:money_ledger/models/login_flows_result.dart';

import 'helpers/test_providers.dart';

void main() {
  group('LoginPage', () {
    testWidgets('renders homeserver field, username, password and sign-in button',
        (tester) async {
      await tester.pumpWidget(testApp(
        const LoginPage(),
        overrides: testOverrides(isLoggedIn: false),
      ));
      await tester.pump();

      expect(find.byKey(const Key('serverField')), findsOneWidget);
      expect(find.byKey(const Key('usernameField')), findsOneWidget);
      expect(find.byKey(const Key('passwordField')), findsOneWidget);
      expect(find.byKey(const Key('signInBtn')), findsOneWidget);
    });

    testWidgets('shows SSO button when server supports SSO', (tester) async {
      final ssoFlows = LoginFlowsResult(
        resolvedUrl: 'https://matrix.org',
        hasSso: true,
        hasPassword: true,
        ssoProviders: [],
      );

      await tester.pumpWidget(testApp(
        const LoginPage(),
        overrides: testOverrides(isLoggedIn: false, loginFlows: ssoFlows),
      ));
      await tester.pump(); // build
      await tester.pump(); // FutureProvider settles

      expect(find.byKey(const Key('ssoBtn')), findsOneWidget);
      expect(find.byKey(const Key('signInBtn')), findsOneWidget);
    });

    testWidgets('shows per-provider SSO buttons when identity_providers present',
        (tester) async {
      final ssoFlows = LoginFlowsResult(
        resolvedUrl: 'https://example.org',
        hasSso: true,
        hasPassword: false,
        ssoProviders: [
          const SsoProvider(id: 'oidc-google', name: 'Google', brand: 'google'),
          const SsoProvider(id: 'oidc-github', name: 'GitHub', brand: 'github'),
        ],
      );

      await tester.pumpWidget(testApp(
        const LoginPage(),
        overrides: testOverrides(isLoggedIn: false, loginFlows: ssoFlows),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('ssoBtn_oidc-google')), findsOneWidget);
      expect(find.byKey(const Key('ssoBtn_oidc-github')), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with GitHub'), findsOneWidget);
    });

    testWidgets('hides password form when server only offers SSO',
        (tester) async {
      final ssoOnly = LoginFlowsResult(
        resolvedUrl: 'https://sso-only.example',
        hasSso: true,
        hasPassword: false,
        ssoProviders: [],
      );

      await tester.pumpWidget(testApp(
        const LoginPage(),
        overrides: testOverrides(isLoggedIn: false, loginFlows: ssoOnly),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('signInBtn')), findsNothing);
      expect(find.byKey(const Key('passwordField')), findsNothing);
      expect(find.byKey(const Key('ssoBtn')), findsOneWidget);
    });

    testWidgets('typing a Matrix ID auto-fills the server field',
        (tester) async {
      await tester.pumpWidget(testApp(
        const LoginPage(),
        overrides: testOverrides(isLoggedIn: false),
      ));
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('usernameField')), '@leo:mozilla.modular.im');
      await tester.pump();

      final serverField = tester.widget<TextFormField>(
          find.byKey(const Key('serverField')));
      expect(serverField.controller?.text, 'mozilla.modular.im');
    });

    testWidgets('password field toggles visibility on eye icon tap',
        (tester) async {
      await tester.pumpWidget(testApp(
        const LoginPage(),
        overrides: testOverrides(isLoggedIn: false),
      ));
      await tester.pump();

      // Initially shows visibility icon (password is obscured)
      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsNothing);

      // Tap to reveal password
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump();

      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsNothing);
    });

    testWidgets(
        'shows SSO button for token-only server (no m.login.sso in flows)',
        (tester) async {
      // Native-OIDC / token-only servers return hasSso:false, hasPassword:false.
      // _toResult infers ssoAvailable = hasSso || !hasPassword = true.
      final tokenOnly = LoginFlowsResult(
        resolvedUrl: 'https://mozilla.modular.im',
        hasSso: true,
        hasPassword: false,
        ssoProviders: [],
      );

      await tester.pumpWidget(testApp(
        const LoginPage(),
        overrides: testOverrides(isLoggedIn: false, loginFlows: tokenOnly),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('ssoBtn')), findsOneWidget);
      expect(find.byKey(const Key('signInBtn')), findsNothing);
    });

    testWidgets(
        'shows SSO button when login flows cannot be fetched (CORS fallback)',
        (tester) async {
      // Simulates the catch-block fallback: hasSso:true so the button appears
      // even when the server can't be probed (e.g. chat.mozilla.org).
      final fallback = LoginFlowsResult(
        resolvedUrl: 'https://mozilla.modular.im',
        hasSso: true,
        hasPassword: true,
        ssoProviders: [],
      );

      await tester.pumpWidget(testApp(
        const LoginPage(),
        overrides: testOverrides(isLoggedIn: false, loginFlows: fallback),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('ssoBtn')), findsOneWidget);
      expect(find.byKey(const Key('signInBtn')), findsOneWidget);
      expect(find.text('Continue with mozilla.modular.im'), findsOneWidget);
    });

    testWidgets(
        'form is usable while homeserver discovery is still loading',
        (tester) async {
      // Just-launched state: loginFlows future hasn't resolved yet. The form
      // must be interactive immediately, not greyed out behind discovery.
      await tester.pumpWidget(testApp(
        const LoginPage(),
        overrides: testOverrides(isLoggedIn: false, loginFlowsLoading: true),
      ));
      await tester.pump(); // build; discovery future never completes

      // Optimistic form: generic SSO + password, both enabled.
      expect(find.byKey(const Key('ssoBtn')), findsOneWidget);
      expect(find.byKey(const Key('signInBtn')), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget); // not a spinner

      final ssoButton = tester.widget<OutlinedButton>(find.descendant(
        of: find.byKey(const Key('ssoBtn')),
        matching: find.byType(OutlinedButton),
      ));
      expect(ssoButton.onPressed, isNotNull, reason: 'SSO must be tappable');

      final signIn =
          tester.widget<FilledButton>(find.byKey(const Key('signInBtn')));
      expect(signIn.onPressed, isNotNull, reason: 'Sign in must be tappable');
    });

    testWidgets('shows "or" divider between SSO and password form',
        (tester) async {
      final mixed = LoginFlowsResult(
        resolvedUrl: 'https://matrix.org',
        hasSso: true,
        hasPassword: true,
        ssoProviders: [],
      );

      await tester.pumpWidget(testApp(
        const LoginPage(),
        overrides: testOverrides(isLoggedIn: false, loginFlows: mixed),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('or'), findsOneWidget);
    });
  });
}
