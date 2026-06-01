import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/auth_provider.dart';
import '../features/auth/login_page.dart';
import '../features/balance/balance_page.dart';
import '../features/expenses/add_expense_page.dart';
import '../features/expenses/expenses_page.dart';
import '../features/groups/create_group_page.dart';
import '../features/groups/groups_page.dart';

part 'router.g.dart';

String? routerRedirect(bool isLoggedIn, String location) {
  if (!isLoggedIn && location != '/login') return '/login';
  if (isLoggedIn && location == '/login') return '/groups';
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
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/groups', builder: (_, _) => const GroupsPage()),
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
    ],
  );
}
