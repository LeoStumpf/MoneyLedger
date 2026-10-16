/// G36: when the Matrix sync loop needs a nudge. Pure Dart (no Flutter, no
/// `package:matrix`) — the glue is `MatrixSyncWatchdog`
/// (`core/matrix/matrix_sync_watchdog.dart`).
///
/// Background: the SDK's loop (`Client._sync`) re-arms itself after every
/// round, retries errors every 3 s and caps the `/sync` long-poll at 40 s —
/// it recovered from every network switch we could provoke on the emulator.
/// What it can't recover from on its own: (a) the loop **not running** at all
/// (it only re-arms while logged in), and (b) an `await` inside a round that
/// never completes — e.g. an HTTP request on a socket that died in a network
/// switch, which the SDK's own timeout (applied to the response *body* only)
/// doesn't cover. (b) is bounded by `RequestTimeoutHttpClient`; this policy
/// restarts a dead loop and reports a stalled one.
library;

/// How often the app checks the loop (also on every app resume).
const kSyncWatchdogInterval = Duration(seconds: 30);

/// No finished / failed sync round for this long while a round is pending =
/// stalled (a healthy loop reports at least every ~40 s: 30 s long-poll +
/// processing, or an error every 3 s while offline).
const kSyncStallAfter = Duration(minutes: 2);

enum SyncWatchdogAction {
  /// Healthy (or nothing to do: signed out / not started yet).
  none,

  /// Signed in but no sync round is running or queued → start the loop again
  /// (`client.backgroundSync = true`; a no-op if one is pending).
  restartLoop,

  /// A round has been pending without progress for [kSyncStallAfter] — log
  /// it (the request timeout ends it; restarting the SDK loop while an old
  /// round can still complete would run two loops).
  reportStall,
}

/// [lastProgressAt]: when the loop last finished or failed a round (ms epoch;
/// null = none yet since start). [syncPending]: a round is running / queued.
SyncWatchdogAction syncWatchdogDecision({
  required int now,
  required int? lastProgressAt,
  required bool loggedIn,
  required bool backgroundSyncWanted,
  required bool syncPending,
  Duration stallAfter = kSyncStallAfter,
}) {
  if (!loggedIn || !backgroundSyncWanted) return SyncWatchdogAction.none;
  if (!syncPending) return SyncWatchdogAction.restartLoop;
  if (lastProgressAt != null &&
      now - lastProgressAt >= stallAfter.inMilliseconds) {
    return SyncWatchdogAction.reportStall;
  }
  return SyncWatchdogAction.none;
}
