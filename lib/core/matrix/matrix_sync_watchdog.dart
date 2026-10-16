import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:matrix/matrix.dart';

import '../sync/sync_watchdog_policy.dart';

/// G36: watches the app's Matrix sync loop (every [kSyncWatchdogInterval] and
/// on app resume) and acts on [syncWatchdogDecision]: restarts a loop that
/// stopped running, logs one that stalls. App isolate only — the background
/// round (G31) runs single `/sync`s on its own client.
class MatrixSyncWatchdog {
  MatrixSyncWatchdog(this._client);

  final Client _client;
  StreamSubscription<SyncStatusUpdate>? _sub;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  int? _lastProgressAt;
  SyncStatus? _lastStatus;
  bool _stallReported = false;

  void start() {
    _sub = _client.onSyncStatus.stream.listen((u) {
      _lastStatus = u.status;
      if (u.status == SyncStatus.finished || u.status == SyncStatus.error) {
        _lastProgressAt = DateTime.now().millisecondsSinceEpoch;
        if (_stallReported) {
          debugPrint('[watchdog] sync loop progressing again');
          _stallReported = false;
        }
      }
    });
    _timer = Timer.periodic(kSyncWatchdogInterval, (_) => check('timer'));
    _lifecycle = AppLifecycleListener(onResume: () => check('resume'));
  }

  void check(String trigger) {
    final action = syncWatchdogDecision(
      now: DateTime.now().millisecondsSinceEpoch,
      lastProgressAt: _lastProgressAt,
      loggedIn: _client.isLogged(),
      // The app never turns the SDK loop off itself (logout does, and then
      // `loggedIn` is false).
      backgroundSyncWanted: true,
      syncPending: _client.syncPending,
    );
    switch (action) {
      case SyncWatchdogAction.none:
        break;
      case SyncWatchdogAction.restartLoop:
        debugPrint('[watchdog] sync loop not running ($trigger) — restarting');
        _client.backgroundSync = true;
      case SyncWatchdogAction.reportStall:
        if (!_stallReported) {
          _stallReported = true;
          debugPrint(
            '[watchdog] no sync progress for '
            '${kSyncStallAfter.inSeconds} s (last status: $_lastStatus, '
            '$trigger) — waiting for the request timeout',
          );
        }
    }
  }

  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _lifecycle?.dispose();
  }
}
