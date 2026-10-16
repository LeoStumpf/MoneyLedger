import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/router.dart';
import 'package:money_ledger/features/onboarding/onboarding_provider.dart';

// Most cases assume onboarding is already done; the onboarding groups cover the
// first-run and still-loading branches explicitly.
String? redirect(
  bool isLoggedIn,
  String location, {
  bool onboardingSeen = true,
  OnboardingStatus? status,
}) => routerRedirect(
  isLoggedIn,
  status ?? (onboardingSeen ? OnboardingStatus.seen : OnboardingStatus.notSeen),
  location,
);

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

    test(
      'stays on /register (in-app sign-up is reachable while signed out)',
      () {
        expect(redirect(false, '/register'), isNull);
      },
    );

    test('About + privacy policy are reachable signed out (G12)', () {
      expect(redirect(false, '/about'), isNull);
      expect(redirect(false, '/about/privacy'), isNull);
      expect(redirect(true, '/about'), isNull);
    });

    test(
      'redirects /onboarding to /login (not an auth page when signed out)',
      () {
        expect(redirect(false, '/onboarding'), '/login');
      },
    );
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
      expect(
        redirect(true, '/groups/r1/expenses', onboardingSeen: false),
        '/onboarding',
      );
    });

    test('stays on /onboarding (no redirect)', () {
      expect(redirect(true, '/onboarding', onboardingSeen: false), isNull);
    });
  });

  group('routerRedirect — signed out, splash', () {
    test('redirects /splash to /login', () {
      expect(redirect(false, '/splash'), '/login');
    });

    test('an unknown flag is irrelevant while signed out', () {
      expect(
        redirect(false, '/login', status: OnboardingStatus.unknown),
        isNull,
      );
    });
  });

  group('routerRedirect — logged in, onboarding flag still loading (G25)', () {
    const unknown = OnboardingStatus.unknown;

    test('shows the splash instead of the groups list', () {
      expect(redirect(true, '/groups', status: unknown), '/splash');
    });

    test('shows the splash right after login (from /login)', () {
      expect(redirect(true, '/login', status: unknown), '/splash');
    });

    test('shows the splash instead of onboarding', () {
      expect(redirect(true, '/onboarding', status: unknown), '/splash');
    });

    test('stays on /splash (no redirect loop)', () {
      expect(redirect(true, '/splash', status: unknown), isNull);
    });

    test('leaves the splash for /groups once the flag is seen', () {
      expect(redirect(true, '/splash'), '/groups');
    });

    test('leaves the splash for /onboarding once the flag is not seen', () {
      expect(redirect(true, '/splash', onboardingSeen: false), '/onboarding');
    });
  });
}
