/// Native (Android) glue for the periodic background sync (G31): the
/// WorkManager registration, the headless entry point, and the real Matrix
/// session behind [runBackgroundRound]. iOS/desktop: no periodic task is
/// registered (see [backgroundSyncSupported]).
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:workmanager/workmanager.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/history/snapshot_store_platform.dart';
import '../session/app_session.dart';
import '../database/account_database.dart';
import '../matrix/ledger_transport.dart';
import '../matrix/matrix_ledger_transport.dart';
import '../matrix/matrix_service.dart';
import '../matrix/request_timeout_http_client.dart';
import '../logging.dart';
import 'background_gate.dart';
import 'background_round.dart';
import 'background_scheduler.dart';

/// WorkManager unique work name + task name of the periodic sync.
const kBackgroundSyncUniqueName = 'moneyledger-background-sync';
const kBackgroundSyncTaskName =
    'io.github.leostumpf.moneyledger.backgroundSync';

/// G36: unique name of the debug-only one-off round (same task / dispatcher).
const kBackgroundSyncOnceUniqueName = 'moneyledger-background-sync-once';

/// How long a round that finds the app alive waits for the app's own sync.
const _delegateTimeout = Duration(seconds: 45);

/// Whether this platform runs a periodic background sync.
bool get backgroundSyncSupported => Platform.isAndroid;

/// App start (`main()`), **before** the Matrix client / ledger DB are opened:
/// registers the app with the [AppIsolateGate] (waiting for a running
/// background round to close its stores — meanwhile [onWaiting] shows
/// "Finishing background sync…", G18 review) and initializes WorkManager.
Future<void> prepareBackgroundSync({void Function()? onWaiting}) async {
  if (!backgroundSyncSupported) return;
  try {
    await AppIsolateGate.instance.claim(onWaiting: onWaiting);
  } catch (e) {
    debugPrint('[bg-gate] claim failed: $e');
  }
  try {
    await Workmanager().initialize(backgroundSyncDispatcher);
  } catch (e) {
    debugPrint('[bg] WorkManager init failed: $e');
  }
}

/// A round that finds the app alive asks it to sync instead (the app owns the
/// stores): one `/sync` through the app's client, then a pause so the ack
/// digests (5 s debounce) go out while WorkManager keeps the process awake.
void attachForegroundSync(ProviderContainer container) {
  if (!backgroundSyncSupported) return;
  // G18 review: the background side never treats a registered app as stale,
  // so the app gives its slot back when its engine detaches (the activity is
  // finishing — e.g. backed out of; the isolate ends right after). Otherwise
  // the dead app's mapping would keep every round skipped until the process
  // dies.
  _lifecycle ??= AppLifecycleListener(
    onDetach: () {
      debugPrint('[bg-gate] app detached — releasing the app slot');
      AppIsolateGate.instance.release();
    },
  );
  AppIsolateGate.instance.onSyncRequest = () async {
    // G40: local mode never builds a Matrix client (nothing to sync).
    if (!container.read(matrixSessionWantedProvider)) return;
    final client = await container
        .read(matrixClientProvider.future)
        .timeout(const Duration(seconds: 10));
    if (!client.isLogged()) return;
    debugPrint('[bg] background task found the app alive — syncing in-app');
    await client.oneShotSync().timeout(const Duration(seconds: 30));
    await Future<void>.delayed(const Duration(seconds: 7));
  };
}

AppLifecycleListener? _lifecycle;

BackgroundScheduler createPlatformBackgroundScheduler() =>
    backgroundSyncSupported
    ? const _WorkManagerScheduler()
    : const NoopBackgroundScheduler();

class _WorkManagerScheduler implements BackgroundScheduler {
  const _WorkManagerScheduler();

  @override
  Future<void> schedule() async {
    await Workmanager().registerPeriodicTask(
      kBackgroundSyncUniqueName,
      kBackgroundSyncTaskName,
      frequency: kBackgroundSyncPeriod,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
    debugPrint('[bg] periodic background sync scheduled');
  }

  @override
  Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(kBackgroundSyncUniqueName);
    debugPrint('[bg] periodic background sync cancelled');
  }

  @override
  Future<void> runOnce({Duration delay = Duration.zero}) async {
    // Debug-only (G36): the settings sheet shows the action under kDebugMode.
    if (!kDebugMode) return;
    await Workmanager().registerOneOffTask(
      kBackgroundSyncOnceUniqueName,
      kBackgroundSyncTaskName,
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    debugPrint(
      '[bg] one-off background round queued (in ${delay.inSeconds} s)',
    );
  }
}

/// Completes when the OS stops the running worker (constraints lost, quota).
Completer<void>? _osStop;

/// WorkManager's headless entry point (runs in a fresh engine + isolate).
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  // G44: a fresh isolate — its own debugPrint; silence it in release too.
  silenceDebugPrintInRelease();
  Workmanager().executeTask(
    (task, input) async {
      try {
        await runBackgroundTask();
      } catch (e, st) {
        debugPrint('[bg] task failed: $e\n$st');
      }
      // Always "success": the next periodic run retries anyway — no retry
      // storms on a flaky network.
      return true;
    },
    onTaskStopped: (task, reason) async {
      debugPrint('[bg] stopped by the OS: $reason');
      final stop = _osStop;
      if (stop != null && !stop.isCompleted) stop.complete();
    },
  );
}

/// One background task: delegate to the app if it is alive in this process,
/// otherwise run [runBackgroundRound] with the restored Matrix session.
Future<BackgroundRoundResult?> runBackgroundTask() async {
  final gate = BackgroundIsolateGate();
  if (await gate.appAlive()) {
    // A registered app that doesn't answer is busy (or detaching): never
    // touch the stores then — skip; the next periodic run retries.
    final ok = await gate.delegateToApp(_delegateTimeout);
    debugPrint(
      '[bg] app is registered — delegated to it '
      '(${ok ? 'done' : 'no answer: round skipped'})',
    );
    return null;
  }
  final osStop = _osStop = Completer<void>();
  try {
    // G18 review 2: the round's own HTTP client — closing it aborts the
    // requests in flight (IOClient.close is forced) before the stores close.
    final roundHttp = RequestTimeoutHttpClient(http.Client());
    return await runBackgroundRound(
      tryAcquire: gate.tryAcquire,
      openSession: () => _openMatrixSession(roundHttp),
      openDatabase: openAccountDatabase,
      abort: Future.any([gate.abort, osStop.future]),
      abortRequests: roundHttp.close,
      // G58: daily restore points from background rounds too. path_provider
      // works in this headless engine (WorkManager registers the plugins;
      // buildMatrixClient resolves its store the same way).
      snapshotStores: createPlatformSnapshotStore,
    );
  } finally {
    gate.release();
  }
}

/// Restores the Matrix session exactly like the app does (same store, same
/// E2EE setup) but without the endless sync loop. Null when signed out.
Future<BackgroundSession?> _openMatrixSession(http.Client httpClient) async {
  try {
    // Without vodozemac the SDK disables E2EE and to-device sends are no-ops.
    await vod.init();
  } catch (e) {
    debugPrint('[bg] vodozemac init failed; E2EE disabled: $e');
  }
  final client = await buildMatrixClient(httpClient: httpClient);
  // One-shot: no background sync loop after init's first /sync.
  client.backgroundSync = false;
  // Subscribe before init(): init's first /sync may already carry payloads.
  final transport = MatrixLedgerTransport.forClient(client);
  try {
    await client.init(waitForFirstSync: false);
  } catch (e) {
    debugPrint('[bg] client init failed: $e');
    await transport.dispose();
    await client.dispose(closeDatabase: true);
    rethrow;
  }
  if (!client.isLogged()) {
    await transport.dispose();
    await client.dispose(closeDatabase: true);
    return null;
  }
  return _MatrixBackgroundSession(client, transport);
}

class _MatrixBackgroundSession implements BackgroundSession {
  _MatrixBackgroundSession(this._client, this._transport);

  final Client _client;
  final MatrixLedgerTransport _transport;

  @override
  String get userId => _client.userID ?? '';

  @override
  LedgerTransport get transport => _transport;

  @override
  Future<void> fetchOnce({Duration wait = Duration.zero}) =>
      _client.oneShotSync(timeout: wait);

  @override
  Future<void> close() async {
    await _transport.dispose();
    // dispose() stops syncing and closes the store — it never logs out.
    await _client.dispose(closeDatabase: true);
  }
}
