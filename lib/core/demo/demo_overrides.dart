import 'package:flutter/foundation.dart' show kIsWeb;
import '../../features/link/link_join.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../features/auth/auth_provider.dart';
import '../../features/auth/sso_provider.dart';
import '../../features/devices/device_provider.dart';
import '../../features/expenses/expenses_provider.dart';
import '../../features/history/snapshot_store.dart';
import '../background/background_scheduler.dart';
import '../link/link_sync_engine.dart';
import '../background/background_sync.dart' show backgroundSyncSupported;
import '../background/background_sync_provider.dart';
import '../database/app_database.dart';
import '../matrix/transport_provider.dart';
import '../session/device_prefs.dart';
import 'demo_auth_gateway.dart';
import 'demo_device_gateway.dart';
import 'demo_mode.dart';
import 'demo_seed.dart';
import 'demo_transport.dart';

/// Opens the demo ledger ([kDemoDatabaseName]) and reseeds it on every open,
/// so each start shows the same fresh dataset.
AppDatabase openDemoDatabase() =>
    AppDatabase.named(kDemoDatabaseName, onOpen: (db) => seedDemoLedger(db));

/// G79: the demo's snapshot stores — in memory, one per ledger DB name, on
/// native; none on the web (as in a real web build). [web] is for tests.
SnapshotStore? Function(String dbName) demoSnapshotStores({bool? web}) {
  if (web ?? kIsWeb) return (_) => null;
  final stores = <String, InMemorySnapshotStore>{};
  return (name) => stores.putIfAbsent(name, InMemorySnapshotStore.new);
}

/// Provider overrides that turn the app into the offline demo (G15): fake
/// auth (signed in as [kDemoUserId]), a fake relay, fake devices, the demo
/// ledger DB instead of any account DB, no background sync (a no-op
/// scheduler), restore points in memory (G79) and no link sync — the seeded
/// link group (G52) shows as synced. None of them
/// touches the Matrix client, so no homeserver / Matrix store is ever opened.
///
/// [openDatabase] lets tests back the demo with an in-memory database.
List<Override> demoOverrides({AppDatabase Function()? openDatabase}) {
  final open = openDatabase ?? openDemoDatabase;
  return [
    authGatewayProvider.overrideWith((ref) async => DemoAuthGateway()),
    ledgerTransportProvider.overrideWith((ref) async {
      final gateway = await ref.watch(authGatewayProvider.future);
      return DemoTransport(gateway.userId ?? kDemoUserId);
    }),
    deviceGatewayProvider.overrideWith((ref) async => DemoDeviceGateway()),
    accountDatabaseOpenerProvider.overrideWithValue((_) => open()),
    backgroundSchedulerProvider.overrideWithValue(
      const NoopBackgroundScheduler(),
    ),
    // G79: the settings show the real platform's texts (store screenshots):
    // on Android the background-sync toggle (the scheduler is a no-op), on
    // the web none.
    backgroundSyncSupportedProvider.overrideWithValue(backgroundSyncSupported),
    // G79: restore points in memory on native (gone with the process, like
    // the reseeded demo ledger) — not the web's "only in an installed app".
    snapshotStoreFactoryProvider.overrideWithValue(demoSnapshotStores()),
    ssoCallbackProvider.overrideWith((ref) => const Stream<Uri>.empty()),
    joinLinkStreamProvider.overrideWith(
      (_) => const Stream<JoinLinkEvent>.empty(),
    ),
    // G52 step 11: no relay is ever contacted — engine off (also where
    // kOfflineDemo isn't set, e.g. tests), no NIP-11 look-ups.
    linkSyncEnabledProvider.overrideWithValue(false),
    linkRelayInfoFetcherProvider.overrideWithValue(null),
    // The link sync engine stays off in the demo (nothing
    // contacts a relay), so a link group's status comes from its seeded
    // channel: "synced" at the last (seeded) publish.
    linkGroupSyncStatusProvider.overrideWith(
      (ref, groupId) => ref
          .watch(linkDaoProvider)
          .watchChannel(groupId)
          .map(
            (ch) => LinkGroupSyncStatus(
              phase: LinkSyncPhase.synced,
              lastPublishedAt: ch?.lastPublishedAt,
            ),
          ),
    ),
    // G39: the demo starts signed in — no welcome, no stored preferences.
    devicePrefsStoreProvider.overrideWithValue(
      InMemoryDevicePrefsStore({'welcome_seen': '1'}),
    ),
  ];
}
