/// Shared test helpers. No package:matrix imports — avoids the sqlite3/open.dart
/// compile issue that occurs when the matrix SDK is pulled in on native platforms.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
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

// ── Override helpers ──────────────────────────────────────────────────────────

/// Returns a minimal set of overrides that prevents any network / DB calls.
/// Parameters control the fake data each page sees.
List<dynamic> testOverrides({
  bool isLoggedIn = false,
  LoginFlowsResult? loginFlows,
  List<ExpenseModel> expenses = const [],
  List<SettlementModel> settlements = const [],
  List<DebtEntry> debts = const [],
}) =>
    [
      isLoggedInProvider.overrideWith((ref) => isLoggedIn),
      loginFlowsProvider
          .overrideWith((ref, input) async => loginFlows ?? LoginFlowsResult.empty),
      expensesForRoomProvider
          .overrideWith((ref, roomId) => Stream.value(expenses)),
      settlementsForRoomProvider
          .overrideWith((ref, roomId) => Stream.value(settlements)),
      balanceForRoomProvider.overrideWith((ref, roomId) => debts),
      ledgerGroupsProvider.overrideWith((_) => Stream.value([])),
      pendingInvitesProvider
          .overrideWith((_) => Stream.value(const <TransportRoom>[])),
    ];

/// Additional override for groups tests where you want to control the group list.
/// Pass a list of fake display names — the groups page uses room.name so we can't
/// pass real Room objects here; test just the empty/non-empty branching instead.
dynamic emptyGroupsOverride() =>
    ledgerGroupsProvider.overrideWith((_) => Stream.value([]));

/// Override that simulates the stream still loading (never emits, never closes).
dynamic loadingGroupsOverride() =>
    ledgerGroupsProvider.overrideWith((_) => StreamController<List<GroupModel>>().stream);
