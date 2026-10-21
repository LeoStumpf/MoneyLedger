/// Shared test helpers. No package:matrix imports — avoids the sqlite3/open.dart
/// compile issue that occurs when the matrix SDK is pulled in on native platforms.
library;

import 'package:money_ledger/features/link/link_join.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/device_prefs.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/features/devices/device_provider.dart';
import 'package:money_ledger/features/expenses/record_attribution.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/backup/backup_providers.dart';
import 'package:money_ledger/features/auth/sso_provider.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/group_archive.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/login_flows_result.dart';
import 'l10n.dart';

// ── Test app wrapper ─────────────────────────────────────────────────────────

/// Wraps [child] in a ProviderScope + MaterialApp with the given overrides.
/// Localized (G12) — English unless [locale] is given (e.g. `Locale('de')`).
Widget testApp(
  Widget child, {
  List overrides = const [],
  Locale? locale,
}) => ProviderScope(
  // Spread into a list literal — Dart infers List<Override> from the
  // ProviderScope parameter type, and each element IS an Override at runtime.
  overrides: [...overrides],
  child: MaterialApp(
    locale: locale ?? const Locale('en'),
    localizationsDelegates: testLocalizationsDelegates,
    supportedLocales: testSupportedLocales,
    home: child,
  ),
);

/// Like [testApp] but mounts [page] under a GoRouter (pushed onto a host route)
/// so pages that call `context.pop()` on success have somewhere to pop back to.
/// After a pop, the "host" text is visible — assert on it to confirm navigation.
Widget testRouterApp(Widget page, {List overrides = const [], Locale? locale}) {
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
    child: MaterialApp.router(
      locale: locale ?? const Locale('en'),
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
    ),
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
  List<MemberModel> members = const [],
  int? lastBackupAt,
  // G16: device-local archive entries the pages see.
  Map<String, GroupArchive> archives = const {},
  // G39/G40: the device-wide preferences (default: welcome seen, no local
  // profile). [localProfile] puts the app in local mode.
  String? localProfile,
  // G40: "Connect a Matrix account" in progress (needs [localProfile]).
  bool connecting = false,
  // G47: the group list the pages see (e.g. a group's custom categories).
  List<GroupModel> groups = const [],
  // G71: the sync status every group shows (default: synced).
  GroupSyncStatus syncStatus = const GroupSyncStatus(
    pendingPeers: {},
    minPeerInSyncAt: null,
  ),
}) => [
  isLoggedInProvider.overrideWith((ref) => isLoggedIn),
  // loginFlowsLoading: future never completes, simulating homeserver
  // discovery still in flight (the just-launched state).
  loginFlowsProvider.overrideWith(
    (ref, input) => loginFlowsLoading
        ? Completer<LoginFlowsResult>().future
        : Future.value(loginFlows ?? LoginFlowsResult.empty),
  ),
  expensesForRoomProvider.overrideWith((ref, roomId) => Stream.value(expenses)),
  settlementsForRoomProvider.overrideWith(
    (ref, roomId) => settlementsStream ?? Stream.value(settlements),
  ),
  balanceForRoomProvider.overrideWith((ref, roomId) => debts),
  ledgerGroupsProvider.overrideWith((_) => Stream.value(groups)),
  // The participant-name resolver and members page read the members stream
  // off the DB; default it to empty so unrelated widget tests stay offline.
  groupMembersProvider.overrideWith((ref, groupId) => Stream.value(members)),
  // Sync-status reads several DB-backed streams; widget tests that don't
  // exercise it default to "synced" so they never open a real database.
  groupSyncStatusProvider.overrideWith((ref, groupId) => syncStatus),
  // Backup (G5): never backed up, not snoozed, no members — the nudge stays
  // hidden and nothing opens a database.
  lastBackupAtProvider.overrideWith((_) => Stream.value(lastBackupAt)),
  backupNudgeSnoozedUntilProvider.overrideWith((_) => Stream.value(null)),
  allMembersProvider.overrideWith((_) => Stream.value(const [])),
  // G34: no second device of ours (the device list needs a Matrix client).
  ownDeviceProtectionProvider.overrideWith((_) => false),
  // Never touch the app_links plugin in widget tests.
  ssoCallbackProvider.overrideWith((_) => const Stream<Uri>.empty()),
  joinLinkStreamProvider.overrideWith((_) => const Stream<Uri>.empty()),
  ...signingUiOverrides(archives: archives),
  // G39/G40: device-wide preferences in memory — welcome seen, no local
  // profile (never the platform file / localStorage).
  devicePrefsStoreProvider.overrideWithValue(
    InMemoryDevicePrefsStore({
      'welcome_seen': '1',
      if (localProfile != null)
        'local_profile': jsonEncode({'name': localProfile, 'created_at': 1}),
      if (connecting) 'local_connecting': '1',
    }),
  ),
  // G79: no Matrix store probe (path_provider) in widget tests.
  matrixStoreExistsProvider.overrideWith((ref) async => false),
  // Local mode would open the real local DB file — use the storage-less
  // placeholder like a signed-out widget test does.
  if (localProfile != null)
    appDatabaseProvider.overrideWithValue(
      AppDatabase.signedOut(SignedOutExecutor()),
    ),
];

/// G6: the signature-status streams of the record UI, without a database
/// stream (drift stream timers would outlive the widget-test tree).
/// [keys]: the device-key history the UI sees. Also the G16 archive entries
/// (none archived) — read by the group and groups pages — and [archives]
/// for tests that need archived groups without a DB.
List<dynamic> signingUiOverrides({
  List<KnownKey> keys = const [],
  Map<String, GroupArchive> archives = const {},
}) => [
  knownDeviceKeysProvider.overrideWith((_) => Stream.value(keys)),
  rejectedVersionProvider.overrideWith((_, _) => Stream.value(null)),
  trustedDevicesProvider.overrideWith((_) => Stream.value(const {})),
  groupArchivesProvider.overrideWith((_) => Stream.value(archives)),
];

/// For widget tests that run a page against a **real** in-memory Drift DB
/// (`appDatabaseProvider.overrideWithValue(db)`): a Drift *watch* stream
/// never settles under the widget-test fake clock (its timers outlive the
/// tree / `pumpAndSettle` hangs), so the DB-watching providers a page shell
/// reads without the test caring about them get static values — the group
/// list ([groups], for the app-bar title / group cards), the G16 archive
/// entries ([archives]) and the G6 signature streams ([keys]). Override
/// anything the test *does* care about (members, expenses, …) yourself.
List<dynamic> realDbWidgetOverrides({
  List<GroupModel> groups = const [],
  Map<String, GroupArchive> archives = const {},
  List<KnownKey> keys = const [],
}) => [
  ledgerGroupsProvider.overrideWith((_) => Stream.value(groups)),
  ...signingUiOverrides(keys: keys, archives: archives),
];

/// Additional override for groups tests where you want to control the group list.
/// Pass a list of fake display names — the groups page uses room.name so we can't
/// pass real Room objects here; test just the empty/non-empty branching instead.
dynamic emptyGroupsOverride() =>
    ledgerGroupsProvider.overrideWith((_) => Stream.value([]));

/// Override that simulates the stream still loading (never emits, never closes).
dynamic loadingGroupsOverride() => ledgerGroupsProvider.overrideWith(
  (_) => StreamController<List<GroupModel>>().stream,
);
