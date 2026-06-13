import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sync_health.g.dart';

/// How many consecutive replication/digest failures before the UI flips to the
/// error state. A single offline blip is normal (the homeserver queues
/// to-device messages and anti-entropy repairs), so we don't alarm on the first
/// failure — only a sustained inability to reach peers.
const kSyncFailureThreshold = 2;

/// App-wide health of the background sync (replication + anti-entropy digests).
/// Derived from successes/failures reported by the sync paths that used to only
/// `debugPrint` their errors — so silent divergence becomes visible.
@immutable
class SyncHealthState {
  /// Consecutive failures since the last success.
  final int consecutiveFailures;

  /// The most recent error text + when it happened (ms epoch); null once cleared
  /// by a success.
  final String? lastError;
  final int? lastErrorAt;

  /// When sync last provably succeeded (ms epoch); null until the first success.
  final int? lastSuccessAt;

  const SyncHealthState({
    this.consecutiveFailures = 0,
    this.lastError,
    this.lastErrorAt,
    this.lastSuccessAt,
  });

  /// Whether the UI should surface a sync problem.
  bool get failing => consecutiveFailures >= kSyncFailureThreshold;

  SyncHealthState afterFailure(Object error, int now) => SyncHealthState(
        consecutiveFailures: consecutiveFailures + 1,
        lastError: error.toString(),
        lastErrorAt: now,
        lastSuccessAt: lastSuccessAt,
      );

  SyncHealthState afterSuccess(int now) =>
      SyncHealthState(lastSuccessAt: now); // resets failures + clears the error
}

/// Holds [SyncHealthState] for the whole session. `keepAlive` so it survives
/// page navigation (the indicator lives in per-group app bars but the health is
/// global). The sync paths call [reportSuccess] / [reportFailure].
@Riverpod(keepAlive: true)
class SyncHealth extends _$SyncHealth {
  @override
  SyncHealthState build() => const SyncHealthState();

  void reportSuccess() =>
      state = state.afterSuccess(DateTime.now().millisecondsSinceEpoch);

  void reportFailure(Object error) =>
      state = state.afterFailure(error, DateTime.now().millisecondsSinceEpoch);
}
