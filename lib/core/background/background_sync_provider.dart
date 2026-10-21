/// App-side wiring of the periodic background sync (G31): the per-account
/// on/off setting and keeping the OS registration in line with it.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/expenses/expenses_provider.dart' show linkDaoProvider;
import '../../features/onboarding/onboarding_provider.dart';
import '../session/app_session.dart';
import 'background_scheduler.dart';
import 'background_sync.dart';

/// The OS scheduler (WorkManager on Android, no-op elsewhere / in tests).
final backgroundSchedulerProvider = Provider<BackgroundScheduler>(
  (ref) => createPlatformBackgroundScheduler(),
);

/// Whether this platform has a background sync at all (the settings toggle is
/// only shown where it does something).
final backgroundSyncSupportedProvider = Provider<bool>(
  (ref) => backgroundSyncSupported,
);

/// The open ledger's background-sync setting (device-local, default on) —
/// the signed-in account's, or (G52 step 9) local mode's. Signed out →
/// false.
final backgroundSyncEnabledProvider = StreamProvider.autoDispose<bool>((ref) {
  final ledger = ref.watch(localModeActiveProvider)
      ? ref.watch(ledgerIdentityProvider)
      : ref.watch(accountUserIdProvider);
  if (ledger == null) return Stream.value(false);
  return ref.watch(settingsDaoProvider).watchBackgroundSyncEnabled();
});

/// G52 step 8: whether the open ledger has at least one link group (a
/// `link_channels` row) — local mode schedules the background round only
/// then (design doc §8.3).
final linkGroupsExistProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref
      .watch(linkDaoProvider)
      .watchAllChannels()
      .map((channels) => channels.isNotEmpty)
      .distinct(),
);

/// The last error of registering / cancelling the OS task (G33), null once a
/// later attempt succeeded — shown under the settings toggle instead of only
/// being logged.
final backgroundSyncSchedulingErrorProvider =
    NotifierProvider<BackgroundSyncSchedulingError, Object?>(
      BackgroundSyncSchedulingError.new,
    );

class BackgroundSyncSchedulingError extends Notifier<Object?> {
  @override
  Object? build() => null;

  void report(Object? error) {
    if (ref.mounted) state = error;
  }
}

/// Keeps the OS registration in line with the session: registered while an
/// account with background sync enabled is signed in (or, G52 step 8, local
/// mode holds a link group), cancelled when it is turned off or the user
/// signs out. Watched by `LedgerSyncHost`.
final backgroundSyncSchedulingProvider = Provider.autoDispose<void>((ref) {
  final scheduler = ref.watch(backgroundSchedulerProvider);
  // Captured before any await (G19); keepAlive, so it outlives this provider.
  final errors = ref.read(backgroundSyncSchedulingErrorProvider.notifier);

  Future<void> apply(bool on) async {
    try {
      await (on ? scheduler.schedule() : scheduler.cancel());
      errors.report(null);
    } catch (e) {
      debugPrint('[bg] scheduling failed: $e');
      errors.report(e);
    }
  }

  // G40: local mode has nothing to sync over Matrix — G52 step 8: but its
  // link groups sync via relays, so the round is registered while at least
  // one exists (design doc §8.3), else cancelled (also a task left from an
  // earlier Matrix session) — without consulting Matrix. G52 step 9: and
  // only while the local ledger's `background_sync_enabled` (settings →
  // Sync, default on) allows it.
  if (ref.watch(localModeActiveProvider)) {
    final links = ref.watch(linkGroupsExistProvider);
    final enabled = ref.watch(backgroundSyncEnabledProvider);
    if (links.hasValue && enabled.hasValue && !enabled.isLoading) {
      apply(links.requireValue && enabled.requireValue);
    }
    return;
  }
  if (!ref.watch(matrixSessionWantedProvider)) return; // prefs still loading
  final loggedIn = ref.watch(loginStateProvider);
  final account = ref.watch(accountUserIdProvider);
  final enabled = ref.watch(backgroundSyncEnabledProvider);

  if (loggedIn.hasValue && loggedIn.value == false) {
    apply(false);
  } else if (account != null && enabled.hasValue && !enabled.isLoading) {
    apply(enabled.requireValue);
  }
  // Otherwise still loading (or still showing the previous account's value)
  // — leave the registration as it is.
});
