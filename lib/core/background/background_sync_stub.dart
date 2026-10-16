/// Web build of the background-sync glue (G31): browsers have no periodic
/// background execution for MoneyLedger — a web tab syncs only while open.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background_scheduler.dart';

/// Whether this platform runs a periodic background sync.
bool get backgroundSyncSupported => false;

/// App start, before the Matrix client / ledger DB are opened. No-op.
Future<void> prepareBackgroundSync({void Function()? onWaiting}) async {}

/// Lets a background round delegate to the running app. No-op.
void attachForegroundSync(ProviderContainer container) {}

BackgroundScheduler createPlatformBackgroundScheduler() =>
    const NoopBackgroundScheduler();
