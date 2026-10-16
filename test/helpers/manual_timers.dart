import 'dart:async';

/// A [Timer] factory whose timers never fire on their own: a test fires them
/// explicitly ([fire] / [fireWhere]). Lets backoff / timeout logic be tested
/// without real wall-clock waits, so it can't flake under CPU load (G15).
class ManualTimers {
  final List<ManualTimer> _all = [];

  /// Pass as the factory (e.g. `selfRecoveryTimerFactoryProvider`).
  Timer call(Duration duration, void Function() callback) {
    final t = ManualTimer._(duration, callback);
    _all.add(t);
    return t;
  }

  /// Timers created and neither fired nor cancelled yet.
  List<ManualTimer> get pending => _all.where((t) => t.isActive).toList();

  /// Pending timers created with exactly [duration].
  List<ManualTimer> pendingWith(Duration duration) =>
      pending.where((t) => t.duration == duration).toList();

  /// Fires every pending timer with [duration]; returns how many fired.
  int fireWhere(Duration duration) {
    final due = pendingWith(duration);
    for (final t in due) {
      t.fire();
    }
    return due.length;
  }
}

class ManualTimer implements Timer {
  final Duration duration;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  ManualTimer._(this.duration, this._callback);

  /// Runs the callback now (no-op if cancelled or already fired).
  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}
