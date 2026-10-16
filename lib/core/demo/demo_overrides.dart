import 'package:flutter_riverpod/misc.dart' show Override;

import '../../features/auth/auth_provider.dart';
import '../../features/auth/sso_provider.dart';
import '../../features/devices/device_provider.dart';
import '../../features/expenses/expenses_provider.dart';
import '../background/background_scheduler.dart';
import '../background/background_sync_provider.dart';
import '../database/app_database.dart';
import '../matrix/transport_provider.dart';
import 'demo_auth_gateway.dart';
import 'demo_device_gateway.dart';
import 'demo_mode.dart';
import 'demo_seed.dart';
import 'demo_transport.dart';

/// Opens the demo ledger ([kDemoDatabaseName]) and reseeds it on every open,
/// so each start shows the same fresh dataset.
AppDatabase openDemoDatabase() =>
    AppDatabase.named(kDemoDatabaseName, onOpen: (db) => seedDemoLedger(db));

/// Provider overrides that turn the app into the offline demo (G15): fake
/// auth (signed in as [kDemoUserId]), a fake relay, fake devices, the demo
/// ledger DB instead of any account DB, and no background sync. None of them
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
    backgroundSyncSupportedProvider.overrideWithValue(false),
    ssoCallbackProvider.overrideWith((ref) => const Stream<Uri>.empty()),
  ];
}
