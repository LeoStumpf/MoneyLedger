import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/expenses/expenses_provider.dart';

part 'self_recovery.g.dart';

/// Backoff between the new-device `resync_request{scope: all}` attempts (G30):
/// the first request goes out when the engine starts, then one retry after each
/// of these delays — while the local DB is still empty and no bootstrap has
/// arrived. Injectable so tests can shorten it.
///
/// Why retry at all: the request is relayed to the user's *other* devices, and
/// those only answer while MoneyLedger is actually running there (no push /
/// background sync on mobile). The homeserver queues the request, so it is
/// normally answered as soon as the other device opens the app — the retries
/// cover a request that was lost or couldn't be sent yet (encryption not ready
/// right after login, a transient send failure).
final selfResyncRetryDelaysProvider = Provider<List<Duration>>((ref) => const [
      Duration(seconds: 5),
      Duration(seconds: 30),
      Duration(minutes: 2),
    ]);

/// How long the groups page shows "Restoring your groups…" before falling back
/// to the normal empty state.
final selfRecoveryTimeoutProvider =
    Provider<Duration>((ref) => const Duration(minutes: 3));

/// Whether this device's first-login recovery is outstanding: the account DB
/// was empty at start-up, a self `resync_request` is out, and nothing has been
/// restored yet. Drives the groups page's "Restoring your groups…" state.
///
/// Per account (reset when the ledger DB is swapped, G4). The notifier owns
/// the UI timeout, so the spinner always ends — even if the engine that
/// started it is gone.
@Riverpod(keepAlive: true)
class SelfRecovery extends _$SelfRecovery {
  Timer? _timeout;

  @override
  bool build() {
    ref.watch(appDatabaseProvider);
    ref.onDispose(() => _timeout?.cancel());
    _timeout?.cancel();
    return false;
  }

  /// A self-resync went out from an empty DB: show "restoring" for at most
  /// [timeout].
  void begin(Duration timeout) {
    if (!ref.mounted) return;
    _timeout?.cancel();
    _timeout = Timer(timeout, finish);
    state = true;
  }

  /// Recovery is over (data arrived, nothing to restore, or timed out).
  void finish() {
    _timeout?.cancel();
    _timeout = null;
    if (!ref.mounted) return;
    state = false;
  }
}
