/// App-side wiring of the periodic background sync (G31): the per-account
/// on/off setting and keeping the OS registration in line with it.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/onboarding/onboarding_provider.dart';
import 'background_scheduler.dart';
import 'background_sync.dart';

/// The OS scheduler (WorkManager on Android, no-op elsewhere / in tests).
final backgroundSchedulerProvider = Provider<BackgroundScheduler>(
    (ref) => createPlatformBackgroundScheduler());

/// Whether this platform has a background sync at all (the settings toggle is
/// only shown where it does something).
final backgroundSyncSupportedProvider =
    Provider<bool>((ref) => backgroundSyncSupported);

/// The signed-in account's background-sync setting (device-local, default
/// on). Signed out → false.
final backgroundSyncEnabledProvider = StreamProvider<bool>((ref) {
  if (ref.watch(accountUserIdProvider) == null) return Stream.value(false);
  return ref.watch(settingsDaoProvider).watchBackgroundSyncEnabled();
});

/// Keeps the OS registration in line with the session: registered while an
/// account with background sync enabled is signed in, cancelled when it is
/// turned off or the user signs out. Watched by `LedgerSyncHost`.
final backgroundSyncSchedulingProvider = Provider.autoDispose<void>((ref) {
  final scheduler = ref.watch(backgroundSchedulerProvider);
  final loggedIn = ref.watch(loginStateProvider);
  final account = ref.watch(accountUserIdProvider);
  final enabled = ref.watch(backgroundSyncEnabledProvider);

  Future<void> apply(bool on) async {
    try {
      await (on ? scheduler.schedule() : scheduler.cancel());
    } catch (e) {
      debugPrint('[bg] scheduling failed: $e');
    }
  }

  if (loggedIn.hasValue && loggedIn.value == false) {
    apply(false);
  } else if (account != null && enabled.hasValue && !enabled.isLoading) {
    apply(enabled.requireValue);
  }
  // Otherwise still loading (or still showing the previous account's value)
  // — leave the registration as it is.
});
