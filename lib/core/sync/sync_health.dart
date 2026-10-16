import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/expenses/expenses_provider.dart';
import '../matrix/ledger_transport.dart';

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

  /// Peers (MXIDs) that had **no device** at our last send to them — not a
  /// transport error (they're simply not logged in anywhere right now), so it
  /// never counts towards [failing]; the UI says "X has no active device".
  /// Cleared per peer as soon as a later send finds one of their devices.
  final Set<String> unreachablePeers;

  /// G11: the subset of [unreachablePeers] that have devices, none of them
  /// verified, while "only sync with verified devices" is on — the UI says
  /// "X has no verified device" instead of "waiting".
  final Set<String> unverifiedPeers;

  const SyncHealthState({
    this.consecutiveFailures = 0,
    this.lastError,
    this.lastErrorAt,
    this.lastSuccessAt,
    this.unreachablePeers = const {},
    this.unverifiedPeers = const {},
  });

  /// Whether the UI should surface a sync problem.
  bool get failing => consecutiveFailures >= kSyncFailureThreshold;

  SyncHealthState afterFailure(Object error, int now) => SyncHealthState(
    consecutiveFailures: consecutiveFailures + 1,
    lastError: error.toString(),
    lastErrorAt: now,
    lastSuccessAt: lastSuccessAt,
    unreachablePeers: unreachablePeers,
    unverifiedPeers: unverifiedPeers,
  );

  /// A send went through. Resets failures and clears the error; [reached]
  /// targets leave [unreachablePeers], [unreachable] ones join it — and
  /// [unverified] ones (a subset of [unreachable]) [unverifiedPeers].
  SyncHealthState afterSuccess(
    int now, {
    Set<String> reached = const {},
    Set<String> unreachable = const {},
    Set<String> unverified = const {},
  }) => SyncHealthState(
    lastSuccessAt: now,
    unreachablePeers: {...unreachablePeers.difference(reached), ...unreachable},
    unverifiedPeers: {
      ...unverifiedPeers.difference(reached).difference(unreachable),
      ...unverified,
    },
  );
}

/// Holds [SyncHealthState] for the whole session. `keepAlive` so it survives
/// page navigation (the indicator lives in per-group app bars but the health is
/// global). The sync paths call [reportSuccess] / [reportFailure].
@Riverpod(keepAlive: true)
class SyncHealth extends _$SyncHealth {
  @override
  SyncHealthState build() {
    // Per account (G4): the ledger DB is swapped exactly on an account switch,
    // so the new account starts from a clean slate instead of showing the
    // previous account's failures / last error. (Watching the DB rather than
    // the account id keeps this off the auth/Matrix-client chain.)
    ref.watch(appDatabaseProvider);
    return const SyncHealthState();
  }

  // Reports may arrive from async work that outlived its container; drop them
  // instead of throwing (callers additionally skip reports once their account
  // DB is closed, so a stale report never lands in the next account's state).
  void reportSuccess() {
    if (!ref.mounted) return;
    state = state.afterSuccess(DateTime.now().millisecondsSinceEpoch);
  }

  /// A send to [targets] completed with [result]: success for the transport,
  /// plus per-peer "has a device / has none" bookkeeping.
  void reportDelivery(Set<String> targets, SendResult result) {
    if (!ref.mounted) return;
    state = state.afterSuccess(
      DateTime.now().millisecondsSinceEpoch,
      reached: targets.difference(result.unreachableUsers),
      unreachable: result.unreachableUsers,
      unverified: result.unverifiedUsers,
    );
  }

  void reportFailure(Object error) {
    if (!ref.mounted) return;
    state = state.afterFailure(error, DateTime.now().millisecondsSinceEpoch);
  }
}

/// Why the sync icon is still waiting for a peer (G24 / G11).
enum PendingReason {
  /// Nothing known — the peer hasn't acknowledged our latest state yet.
  waiting,

  /// The peer has no logged-in device.
  noDevice,

  /// The peer has devices, but none is verified and "only sync with verified
  /// devices" is on.
  unverified,
}

/// The peer the pending sync icon names, and why: a peer whose devices are
/// all unverified first, then one with no device, else the first waiting
/// peer. Pure; [pendingPeers] must not be empty.
({String peer, PendingReason reason}) pendingPeerHint(
  Iterable<String> pendingPeers,
  SyncHealthState health,
) {
  for (final p in pendingPeers) {
    if (health.unverifiedPeers.contains(p)) {
      return (peer: p, reason: PendingReason.unverified);
    }
  }
  for (final p in pendingPeers) {
    if (health.unreachablePeers.contains(p)) {
      return (peer: p, reason: PendingReason.noDevice);
    }
  }
  return (peer: pendingPeers.first, reason: PendingReason.waiting);
}
