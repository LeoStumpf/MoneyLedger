/// Shared test helpers. No package:matrix imports — avoids the sqlite3/open.dart
/// compile issue that occurs when the matrix SDK is pulled in on native platforms.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/auth/sso_provider.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/login_flows_result.dart';

// ── Test app wrapper ─────────────────────────────────────────────────────────

/// Wraps [child] in a ProviderScope + MaterialApp with the given overrides.
Widget testApp(Widget child, {List overrides = const []}) =>
    ProviderScope(
      // Spread into a list literal — Dart infers List<Override> from the
      // ProviderScope parameter type, and each element IS an Override at runtime.
      overrides: [...overrides],
      child: MaterialApp(home: child),
    );

/// Like [testApp] but mounts [page] under a GoRouter (pushed onto a host route)
/// so pages that call `context.pop()` on success have somewhere to pop back to.
/// After a pop, the "host" text is visible — assert on it to confirm navigation.
Widget testRouterApp(Widget page, {List overrides = const []}) {
  final router = GoRouter(
    initialLocation: '/host',
    routes: [
      GoRoute(
        path: '/host',
        builder: (_, _) => const Scaffold(body: Center(child: Text('host'))),
      ),
      GoRoute(path: '/page', builder: (_, _) => page),
    ],
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => router.push('/page'));
  return ProviderScope(
    overrides: [...overrides],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ── Override helpers ──────────────────────────────────────────────────────────

/// Returns a minimal set of overrides that prevents any network / DB calls.
/// Parameters control the fake data each page sees.
List<dynamic> testOverrides({
  bool isLoggedIn = false,
  LoginFlowsResult? loginFlows,
  bool loginFlowsLoading = false,
  List<ExpenseModel> expenses = const [],
  List<SettlementModel> settlements = const [],
  // Overrides [settlements] — for tests that push updates over time.
  Stream<List<SettlementModel>>? settlementsStream,
  List<DebtEntry> debts = const [],
}) =>
    [
      isLoggedInProvider.overrideWith((ref) => isLoggedIn),
      // loginFlowsLoading: future never completes, simulating homeserver
      // discovery still in flight (the just-launched state).
      loginFlowsProvider.overrideWith((ref, input) => loginFlowsLoading
          ? Completer<LoginFlowsResult>().future
          : Future.value(loginFlows ?? LoginFlowsResult.empty)),
      expensesForRoomProvider
          .overrideWith((ref, roomId) => Stream.value(expenses)),
      settlementsForRoomProvider
          .overrideWith((ref, roomId) =>
              settlementsStream ?? Stream.value(settlements)),
      balanceForRoomProvider.overrideWith((ref, roomId) => debts),
      ledgerGroupsProvider.overrideWith((_) => Stream.value([])),
      // The participant-name resolver and members page read the members stream
      // off the DB; default it to empty so unrelated widget tests stay offline.
      groupMembersProvider.overrideWith((ref, groupId) => Stream.value(const [])),
      // Sync-status reads several DB-backed streams; widget tests that don't
      // exercise it default to "synced" so they never open a real database.
      groupSyncStatusProvider.overrideWith((ref, groupId) =>
          const GroupSyncStatus(pendingPeers: {}, minPeerInSyncAt: null)),
      // Never touch the app_links plugin in widget tests.
      ssoCallbackProvider.overrideWith((_) => const Stream<Uri>.empty()),
    ];

/// Additional override for groups tests where you want to control the group list.
/// Pass a list of fake display names — the groups page uses room.name so we can't
/// pass real Room objects here; test just the empty/non-empty branching instead.
dynamic emptyGroupsOverride() =>
    ledgerGroupsProvider.overrideWith((_) => Stream.value([]));

/// Override that simulates the stream still loading (never emits, never closes).
dynamic loadingGroupsOverride() =>
    ledgerGroupsProvider.overrideWith((_) => StreamController<List<GroupModel>>().stream);
