import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/auth_provider.dart';
import 'error_page.dart';
import '../features/auth/login_page.dart';
import '../features/balance/balance_page.dart';
import '../features/debug/to_device_smoke_page.dart'; // TEMP: Phase B0 spike
import '../features/expenses/add_expense_page.dart';
import '../features/expenses/expenses_page.dart';
import '../features/groups/create_group_page.dart';
import '../features/groups/group_members_page.dart';
import '../features/groups/groups_page.dart';

part 'router.g.dart';

String? routerRedirect(bool isLoggedIn, String location) {
  if (!isLoggedIn && location != '/login') return '/login';
  // Send logged-in users away from /login and the bare root / to the groups list.
  if (isLoggedIn && (location == '/login' || location == '/')) return '/groups';
  return null;
}

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final listenable = ValueNotifier<bool>(false);
  ref.listen<bool>(isLoggedInProvider, (_, next) => listenable.value = next);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: listenable,
    redirect: (_, state) =>
        routerRedirect(ref.read(isLoggedInProvider), state.matchedLocation),
    errorBuilder: (_, state) => ErrorPage(error: state.error),
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/groups', builder: (_, _) => const GroupsPage()),
      // TEMP: Phase B0 spike — remove with the debug button + smoke page.
      GoRoute(
          path: '/debug/todevice',
          builder: (_, _) => const ToDeviceSmokePage()),
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
