/// Registers / cancels the periodic background sync with the OS (G31).
/// Plain Dart port; the Android implementation wraps WorkManager
/// (`background_sync_native.dart`), every other platform gets [NoopBackgroundScheduler].
abstract interface class BackgroundScheduler {
  /// Ensures the periodic task is registered (idempotent).
  Future<void> schedule();

  /// Removes the periodic task (idempotent).
  Future<void> cancel();
}

/// Web / iOS / desktop / tests: there is no background sync.
class NoopBackgroundScheduler implements BackgroundScheduler {
  const NoopBackgroundScheduler();

  @override
  Future<void> schedule() async {}

  @override
  Future<void> cancel() async {}
}
