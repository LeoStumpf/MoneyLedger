import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/about/about_page.dart';
import '../features/local/local_setup_page.dart';
import '../features/welcome/welcome_page.dart';
import 'session/app_session.dart';
import '../models/expense_model.dart';
import 'error_page.dart';
import 'splash_page.dart';
import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/devices/devices_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/onboarding/onboarding_provider.dart';
import '../features/balance/balance_page.dart';
import '../features/expenses/add_expense_page.dart';
import '../features/expenses/expenses_page.dart';
import '../features/groups/create_group_page.dart';
import '../features/groups/group_members_page.dart';
import '../features/groups/groups_page.dart';

part 'router.g.dart';

/// Pages reachable while signed out (login + in-app registration).
const _authPages = {'/login', '/register'};

/// Informational pages reachable signed in **and** signed out (About +
/// privacy policy, G12; "How MoneyLedger works", G39) — never redirected away
/// from once onboarding is done.
const _publicPages = {'/about', '/about/privacy', kHowItWorksLocation};

/// Neutral loading route shown while the device preferences or the
/// per-account onboarding flag are still unknown (G25).
const kSplashLocation = '/splash';

/// G39: the first-open welcome (with the three choices).
const kWelcomeLocation = '/welcome';

/// G39: the same pages to read again (About, login page) — no choices.
const kHowItWorksLocation = '/how-it-works';

/// G40: "Use without account" — asks for the local profile's name.
const kLocalSetupLocation = '/local-setup';

/// Entry pages of a signed-out device (besides login / register).
const _signedOutEntryPages = {kWelcomeLocation, kLocalSetupLocation};

/// Pure redirect rule (unit-tested).
///
/// * [AppSessionKind.loading] (device preferences not read yet) → splash.
/// * Signed out: welcome not seen → the welcome (public pages allowed);
///   seen → login / register / welcome / local setup / public pages, else
///   [landing] (login; the welcome after *Delete local data*, G46).
/// * Local mode with "Connect a Matrix account" in progress ([connecting]) →
///   only login / register / public pages.
/// * In (local or Matrix): onboarding flag [OnboardingStatus.unknown] → the
///   splash (never guess either page); not seen → forced onboarding; seen →
///   bounce off the auth / entry pages, bare root, splash and a stale
///   onboarding screen to the groups list. Local mode has no devices page.
String? routerRedirect({
  required AppSessionKind session,
  required WelcomeStatus welcome,
  required OnboardingStatus onboarding,
  bool connecting = false,
  SignedOutLanding landing = SignedOutLanding.login,
  required String location,
}) {
  final public = _publicPages.contains(location);
  switch (session) {
    case AppSessionKind.loading:
      return location == kSplashLocation ? null : kSplashLocation;
    case AppSessionKind.signedOut:
      switch (welcome) {
        case WelcomeStatus.unknown:
          return location == kSplashLocation ? null : kSplashLocation;
        case WelcomeStatus.notSeen:
          return location == kWelcomeLocation || public
              ? null
              : kWelcomeLocation;
        case WelcomeStatus.seen:
          return _authPages.contains(location) ||
                  _signedOutEntryPages.contains(location) ||
                  public
              ? null
              : switch (landing) {
                  SignedOutLanding.login => '/login',
                  SignedOutLanding.welcome => kWelcomeLocation,
                };
      }
    case AppSessionKind.local:
      if (connecting) {
        return _authPages.contains(location) || public ? null : '/login';
      }
      if (location == '/devices') return '/groups';
    case AppSessionKind.matrix:
      break;
  }
  switch (onboarding) {
    case OnboardingStatus.unknown:
      return location == kSplashLocation ? null : kSplashLocation;
    case OnboardingStatus.notSeen:
      return location == '/onboarding' || public ? null : '/onboarding';
    case OnboardingStatus.seen:
      break;
  }
  if (_authPages.contains(location) ||
      _signedOutEntryPages.contains(location) ||
      location == '/' ||
      location == kSplashLocation ||
      location == '/onboarding') {
    return '/groups';
  }
  return null;
}

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  // Toggled on any auth/onboarding change so GoRouter re-runs the redirect
  // (toggling guarantees a notification regardless of the new value).
  final listenable = ValueNotifier<bool>(false);
  void bump() => listenable.value = !listenable.value;
  ref.listen<AppSessionKind>(appSessionProvider, (_, next) {
    // G46: someone is in again → a later sign-out lands on the login page.
    if (next == AppSessionKind.local || next == AppSessionKind.matrix) {
      ref.read(signedOutLandingProvider.notifier).set(SignedOutLanding.login);
    }
    bump();
  });
  ref.listen<SignedOutLanding>(signedOutLandingProvider, (_, _) => bump());
  ref.listen<WelcomeStatus>(welcomeStatusProvider, (_, _) => bump());
  ref.listen<bool>(connectingAccountProvider, (_, _) => bump());
  ref.listen<OnboardingStatus>(onboardingGateProvider, (_, _) => bump());
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: kSplashLocation,
    refreshListenable: listenable,
    redirect: (_, state) => routerRedirect(
      session: ref.read(appSessionProvider),
      welcome: ref.read(welcomeStatusProvider),
      onboarding: ref.read(onboardingGateProvider),
      connecting: ref.read(connectingAccountProvider),
      landing: ref.read(signedOutLandingProvider),
      location: state.matchedLocation,
    ),
    errorBuilder: (_, state) => ErrorPage(error: state.error),
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(path: kSplashLocation, builder: (_, _) => const SplashPage()),
      GoRoute(
        path: kWelcomeLocation,
        // G46: seen before (e.g. after *Delete local data*) → the choices.
        builder: (_, _) => WelcomePage(
          startAtChoices: ref.read(welcomeStatusProvider) == WelcomeStatus.seen,
        ),
      ),
      GoRoute(
        path: kHowItWorksLocation,
        builder: (_, s) => WelcomePage(
          revisit: true,
          initialTopic: WelcomeTopic.fromName(s.uri.queryParameters['topic']),
        ),
      ),
      GoRoute(
        path: kLocalSetupLocation,
        builder: (_, _) => const LocalSetupPage(),
      ),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
      GoRoute(path: '/groups', builder: (_, _) => const GroupsPage()),
      GoRoute(path: '/devices', builder: (_, _) => const DevicesPage()),
      GoRoute(path: '/about', builder: (_, _) => const AboutPage()),
      GoRoute(
        path: '/about/privacy',
        builder: (_, _) => const PrivacyPolicyPage(),
      ),
      GoRoute(
        path: '/groups/create',
        builder: (_, _) => const CreateGroupPage(),
      ),
      GoRoute(
        path: '/groups/:roomId/expenses',
        builder: (_, s) => ExpensesPage(roomId: s.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/groups/:roomId/expenses/add',
        builder: (_, s) => AddExpensePage(roomId: s.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/groups/:roomId/expenses/edit',
        builder: (_, s) => AddExpensePage(
          roomId: s.pathParameters['roomId']!,
          initial: s.extra as ExpenseModel?,
        ),
      ),
      GoRoute(
        path: '/groups/:roomId/balance',
        builder: (_, s) => BalancePage(roomId: s.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/groups/:roomId/members',
        builder: (_, s) =>
            GroupMembersPage(roomId: s.pathParameters['roomId']!),
      ),
    ],
  );
}
