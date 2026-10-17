import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/router.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/features/onboarding/onboarding_provider.dart';

// Most cases assume onboarding and the welcome are already done; the
// onboarding / welcome / local-mode groups cover the other branches.
String? redirect(
  bool isLoggedIn,
  String location, {
  bool onboardingSeen = true,
  OnboardingStatus? status,
  AppSessionKind? session,
  WelcomeStatus welcome = WelcomeStatus.seen,
  bool connecting = false,
  SignedOutLanding landing = SignedOutLanding.login,
}) => routerRedirect(
  session:
      session ??
      (isLoggedIn ? AppSessionKind.matrix : AppSessionKind.signedOut),
  welcome: welcome,
  onboarding:
      status ??
      (onboardingSeen ? OnboardingStatus.seen : OnboardingStatus.notSeen),
  connecting: connecting,
  landing: landing,
  location: location,
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
    test('redirects /splash to /login (welcome seen)', () {
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

  group('routerRedirect — device preferences loading (G39)', () {
    const loading = AppSessionKind.loading;
    test('every page waits on the splash', () {
      for (final loc in ['/', '/login', '/groups', '/welcome', '/about']) {
        expect(redirect(false, loc, session: loading), '/splash', reason: loc);
      }
      expect(redirect(false, '/splash', session: loading), isNull);
    });
  });

  group('routerRedirect — first open, welcome not seen (G39)', () {
    const notSeen = WelcomeStatus.notSeen;
    test('everything leads to the welcome', () {
      for (final loc in ['/', '/login', '/register', '/groups', '/splash']) {
        expect(redirect(false, loc, welcome: notSeen), '/welcome', reason: loc);
      }
    });
    test('the welcome itself and the public pages stay', () {
      for (final loc in [
        '/welcome',
        '/about',
        '/about/privacy',
        '/how-it-works',
      ]) {
        expect(redirect(false, loc, welcome: notSeen), isNull, reason: loc);
      }
    });
    test('local setup needs the welcome first', () {
      expect(redirect(false, '/local-setup', welcome: notSeen), '/welcome');
    });
    test('an unknown welcome flag shows the splash', () {
      expect(
        redirect(false, '/login', welcome: WelcomeStatus.unknown),
        '/splash',
      );
    });
  });

  group('routerRedirect — signed out, welcome seen (G39/G40)', () {
    test('login, register, welcome, local setup and public pages stay', () {
      for (final loc in [
        '/login',
        '/register',
        '/welcome',
        '/local-setup',
        '/how-it-works',
        '/about',
      ]) {
        expect(redirect(false, loc), isNull, reason: loc);
      }
    });
    test('app pages lead to the login', () {
      expect(redirect(false, '/groups'), '/login');
      expect(redirect(false, '/devices'), '/login');
    });
    test('G46: after "Delete local data" app pages lead to the welcome', () {
      const welcome = SignedOutLanding.welcome;
      expect(redirect(false, '/groups', landing: welcome), '/welcome');
      expect(
        redirect(false, '/groups/g1/expenses', landing: welcome),
        '/welcome',
      );
      // Allowed pages stay where they are.
      expect(redirect(false, '/login', landing: welcome), isNull);
      expect(redirect(false, '/welcome', landing: welcome), isNull);
      // Only for a signed-out device: in local mode / signed in it's moot.
      expect(redirect(true, '/groups', landing: welcome), isNull);
      // The first open still goes to the welcome either way.
      expect(
        redirect(false, '/groups', welcome: WelcomeStatus.notSeen),
        '/welcome',
      );
    });
  });

  group('routerRedirect — local mode (G40)', () {
    const local = AppSessionKind.local;
    test('is "in": the app pages stay, entry pages lead to the groups', () {
      expect(redirect(false, '/groups', session: local), isNull);
      expect(redirect(false, '/groups/g1/expenses', session: local), isNull);
      for (final loc in [
        '/',
        '/login',
        '/register',
        '/welcome',
        '/local-setup',
      ]) {
        expect(redirect(false, loc, session: local), '/groups', reason: loc);
      }
    });
    test('has no devices page', () {
      expect(redirect(false, '/devices', session: local), '/groups');
    });
    test('its own onboarding gate applies', () {
      expect(
        redirect(false, '/groups', session: local, onboardingSeen: false),
        '/onboarding',
      );
      expect(
        redirect(
          false,
          '/groups',
          session: local,
          status: OnboardingStatus.unknown,
        ),
        '/splash',
      );
    });
    test('"How it works" stays reachable', () {
      expect(redirect(false, '/how-it-works', session: local), isNull);
    });
    test('connecting: only login / register / public pages', () {
      expect(
        redirect(false, '/groups', session: local, connecting: true),
        '/login',
      );
      for (final loc in ['/login', '/register', '/about', '/how-it-works']) {
        expect(
          redirect(false, loc, session: local, connecting: true),
          isNull,
          reason: loc,
        );
      }
    });
    test('the connect sign-in succeeded: a Matrix session goes in', () {
      expect(redirect(true, '/login', connecting: true), '/groups');
    });
  });

  // G65: the settings pages (were a sheet / the group ⋮ menu) are ordinary
  // "in" pages.
  group('routerRedirect — settings pages (G65)', () {
    const local = AppSessionKind.local;
    const pages = ['/settings', '/groups/g1/settings'];
    test('signed out → login (or the welcome)', () {
      for (final loc in pages) {
        expect(redirect(false, loc), '/login', reason: loc);
        expect(
          redirect(false, loc, welcome: WelcomeStatus.notSeen),
          '/welcome',
          reason: loc,
        );
      }
    });
    test('reachable with a Matrix account and in local mode', () {
      for (final loc in pages) {
        expect(redirect(true, loc), isNull, reason: loc);
        expect(redirect(false, loc, session: local), isNull, reason: loc);
      }
    });
    test('onboarding first', () {
      expect(redirect(true, '/settings', onboardingSeen: false), '/onboarding');
    });
    test('connecting an account: back to the login page', () {
      for (final loc in pages) {
        expect(
          redirect(false, loc, session: local, connecting: true),
          '/login',
          reason: loc,
        );
      }
    });
  });
}
