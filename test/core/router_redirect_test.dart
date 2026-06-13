import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/router.dart';

// Most cases assume onboarding is already done; the onboarding group covers the
// first-run branch explicitly.
String? redirect(bool isLoggedIn, String location, {bool onboardingSeen = true}) =>
    routerRedirect(isLoggedIn, onboardingSeen, location);

void main() {
  group('routerRedirect — not logged in', () {
    test('redirects / to /login', () {
      expect(redirect(false, '/'), '/login');
    });

    test('redirects /groups to /login', () {
      expect(redirect(false, '/groups'), '/login');
    });

    test('redirects /groups/r1/expenses to /login', () {
      expect(redirect(false, '/groups/r1/expenses'), '/login');
    });

    test('stays on /login (no redirect)', () {
      expect(redirect(false, '/login'), isNull);
    });

    test('stays on /register (in-app sign-up is reachable while signed out)',
        () {
      expect(redirect(false, '/register'), isNull);
    });

    test('redirects /onboarding to /login (not an auth page when signed out)',
        () {
      expect(redirect(false, '/onboarding'), '/login');
    });
  });

  group('routerRedirect — logged in', () {
    test('redirects /login to /groups', () {
      expect(redirect(true, '/login'), '/groups');
    });

    test('redirects bare / to /groups', () {
      expect(redirect(true, '/'), '/groups');
    });

    test('redirects /register to /groups (already signed in)', () {
      expect(redirect(true, '/register'), '/groups');
    });

    test('stays on /groups (no redirect)', () {
      expect(redirect(true, '/groups'), isNull);
    });

    test('stays on /groups/r1/expenses (no redirect)', () {
      expect(redirect(true, '/groups/r1/expenses'), isNull);
    });

    test('stays on /groups/r1/balance (no redirect)', () {
      expect(redirect(true, '/groups/r1/balance'), isNull);
    });

    test('redirects /onboarding to /groups once onboarding is seen', () {
      expect(redirect(true, '/onboarding'), '/groups');
    });
  });

  group('routerRedirect — logged in, onboarding not seen', () {
    test('forces /onboarding from the groups list', () {
      expect(redirect(true, '/groups', onboardingSeen: false), '/onboarding');
    });

    test('forces /onboarding from a deep link', () {
      expect(redirect(true, '/groups/r1/expenses', onboardingSeen: false),
          '/onboarding');
    });

    test('stays on /onboarding (no redirect)', () {
      expect(redirect(true, '/onboarding', onboardingSeen: false), isNull);
    });
  });
}
