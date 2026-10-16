import 'dart:async';

/// Creates a one-shot [Timer]. Production code that owns a user-visible
/// timeout or a backoff schedule takes its timers from an injectable provider
/// of this type (default [Timer.new]) so tests can fire them explicitly
/// instead of waiting on the wall clock — which flakes under CPU load (G15).
typedef TimerFactory =
    Timer Function(Duration duration, void Function() callback);
