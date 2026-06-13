import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/auth_provider.dart';
import '../models/expense_model.dart';
import 'error_page.dart';
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

String? routerRedirect(bool isLoggedIn, bool onboardingSeen, String location) {
  if (!isLoggedIn) {
    return _authPages.contains(location) ? null : '/login';
  }
  // Logged in but hasn't completed the one-time onboarding → force it.
  if (!onboardingSeen) {
    return location == '/onboarding' ? null : '/onboarding';
  }
  // Logged in and onboarded: bounce off the auth pages, bare root, and the
  // now-stale onboarding screen to the groups list.
  if (_authPages.contains(location) ||
      location == '/' ||
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
  ref.listen<bool>(isLoggedInProvider, (_, _) => bump());
  ref.listen<bool>(onboardingSeenProvider, (_, _) => bump());
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: listenable,
    redirect: (_, state) => routerRedirect(
      ref.read(isLoggedInProvider),
      ref.read(onboardingSeenProvider),
      state.matchedLocation,
    ),
    errorBuilder: (_, state) => ErrorPage(error: state.error),
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(
          path: '/onboarding', builder: (_, _) => const OnboardingPage()),
      GoRoute(path: '/groups', builder: (_, _) => const GroupsPage()),
      GoRoute(path: '/devices', builder: (_, _) => const DevicesPage()),
      GoRoute(
          path: '/groups/create',
          builder: (_, _) => const CreateGroupPage()),
      GoRoute(
        path: '/groups/:roomId/expenses',
        builder: (_, s) =>
            ExpensesPage(roomId: s.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/groups/:roomId/expenses/add',
        builder: (_, s) =>
            AddExpensePage(roomId: s.pathParameters['roomId']!),
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
        builder: (_, s) =>
            BalancePage(roomId: s.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/groups/:roomId/members',
        builder: (_, s) =>
            GroupMembersPage(roomId: s.pathParameters['roomId']!),
      ),
    ],
  );
}
