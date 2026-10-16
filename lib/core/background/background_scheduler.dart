/// Registers / cancels the periodic background sync with the OS (G31).
/// Plain Dart port; the Android implementation wraps WorkManager
/// (`background_sync_native.dart`), every other platform gets [NoopBackgroundScheduler].
abstract interface class BackgroundScheduler {
  /// Ensures the periodic task is registered (idempotent).
  Future<void> schedule();

  /// Removes the periodic task (idempotent).
  Future<void> cancel();

  /// Debug builds only (G36, settings sheet): queues **one** background round
  /// after [delay] — time to swipe the app away, so the round runs headless
  /// instead of delegating to the running app.
  Future<void> runOnce({Duration delay});
}

/// G36: the delay of the debug-only "Run background sync now".
const kDebugBackgroundRunDelay = Duration(seconds: 15);

/// Web / iOS / desktop / tests: there is no background sync.
class NoopBackgroundScheduler implements BackgroundScheduler {
  const NoopBackgroundScheduler();

  @override
  Future<void> schedule() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> runOnce({Duration delay = Duration.zero}) async {}
}
