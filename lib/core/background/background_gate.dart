/// Mutual exclusion between the **app** (main isolate) and a **background
/// sync round** (a WorkManager headless engine, G31) — native only.
///
/// Both run in the same Android process but in different isolates, each with
/// its own Matrix client and Drift connection to the *same* files: the Matrix
/// store (Olm sessions, sync token) and the ledger DB. Two writers — or one
/// client acting on Olm state another one has already advanced — could corrupt
/// the crypto state, so they must never overlap. The guard is the process-wide
/// [IsolateNameServer]: each side registers a port under a well-known name and
/// checks the other side's name (register first, check second — so of two
/// sides starting at once, at least one sees the other).
///
/// A mapping can outlive its isolate (the name server isn't cleaned up when an
/// isolate dies), so "is the other side there?" is a ping. G18 review — who
/// may treat an unanswered mapping as stale:
/// - The **background** side never removes a mapping. A registered app that
///   doesn't answer may just be busy (startup work on the main isolate), so
///   the round is **skipped** (the next periodic run retries; a new app
///   process starts with an empty name server anyway).
/// - The **app** side asks a running round to stop and waits until its
///   mapping is gone (the round releases it only after closing its stores),
///   it answers `stopped`, or it hasn't answered anything for [staleAfter]
///   (a dead isolate — then the mapping is removed). A live round always
///   ends within its own budget (`kBackgroundRoundTimeout` + the bounded
///   in-flight grace + closing), so [maxWait] is only a last resort against
///   a wedged round; meanwhile the app shows "Finishing background sync…"
///   instead of opening its stores in parallel.
///
/// Protocol (messages are `[command, replyPort]`):
/// - `ping` → `pong` (liveness).
/// - `sync` (background → app): the app is alive, so it does the round itself
///   (one `/sync` + answers) and replies `done`. Keeps WorkManager's process
///   awake while a backgrounded app catches up.
/// - `stop` (app → background): the app is starting; the round aborts, closes
///   its stores and replies `stopped`.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

const _mainPortName = 'io.github.leostumpf.moneyledger.main';
const _backgroundPortName = 'io.github.leostumpf.moneyledger.background';
const _pingTimeout = Duration(seconds: 2);

/// The process-wide port registry ([IsolateNameServer]); injectable so the
/// gate logic is unit-tested with in-isolate ports.
abstract interface class PortRegistry {
  SendPort? lookup(String name);
  bool register(SendPort port, String name);
  void remove(String name);
}

class _IsolateNameServerRegistry implements PortRegistry {
  const _IsolateNameServerRegistry();
  @override
  SendPort? lookup(String name) => IsolateNameServer.lookupPortByName(name);
  @override
  bool register(SendPort port, String name) =>
      IsolateNameServer.registerPortWithName(port, name);
  @override
  void remove(String name) => IsolateNameServer.removePortNameMapping(name);
}

/// Sends `[command, reply]` to the port registered as [name] and waits for the
/// first answer. Null when nothing is registered or no answer came in time.
Future<Object?> _ask(
  PortRegistry registry,
  String name,
  String command,
  Duration timeout,
) async {
  final port = registry.lookup(name);
  if (port == null) return null;
  final reply = ReceivePort();
  try {
    port.send([command, reply.sendPort]);
    return await reply.first.timeout(timeout);
  } on TimeoutException {
    return null;
  } finally {
    reply.close();
  }
}

/// Whether a side is registered as [name] at all — answering or not. The
/// background side treats an unanswered mapping as present (busy), never as
/// stale (G18 review).
Future<bool> _present(PortRegistry registry, String name) async =>
    registry.lookup(name) != null;

/// The app side. [claim] runs in `main()` **before** the Matrix client / DB
/// are opened.
class AppIsolateGate {
  AppIsolateGate._() : _registry = const _IsolateNameServerRegistry();
  static final instance = AppIsolateGate._();

  /// A gate on [registry] (tests).
  @visibleForTesting
  AppIsolateGate.withRegistry(PortRegistry registry) : _registry = registry;

  final PortRegistry _registry;
  ReceivePort? _port;

  /// Runs a quick foreground sync when a background round finds the app
  /// alive (set once the app's container exists). Null → answered at once.
  Future<void> Function()? onSyncRequest;

  /// Registers the app and waits for a running background round to stop and
  /// close its stores (see the library doc). [onWaiting] is called once if
  /// there is a round to wait for (the app shows "Finishing background
  /// sync…"). Returns false only when [maxWait] ran out with the round still
  /// answering but not stopping (logged — a wedged round; the app proceeds).
  Future<bool> claim({
    Duration maxWait = const Duration(minutes: 2),
    Duration staleAfter = const Duration(seconds: 10),
    Duration askTimeout = const Duration(seconds: 1),
    void Function()? onWaiting,
  }) async {
    if (_port != null) return true;
    final port = _port = ReceivePort();
    port.listen(_onMessage);
    // A previous app isolate in this process is gone (we are the new one).
    _registry.remove(_mainPortName);
    _registry.register(port.sendPort, _mainPortName);

    if (!await _present(_registry, _backgroundPortName)) return true;
    debugPrint('[bg-gate] background round registered — asking it to stop');
    onWaiting?.call();
    final sw = Stopwatch()..start();
    var lastAnswer = Duration.zero;
    while (true) {
      if (_registry.lookup(_backgroundPortName) == null) break;
      // Re-ask in short slices: the round may release (and close its port)
      // at any moment, which drops a pending request — the mapping
      // disappearing is the answer then.
      final answer = await _ask(
        _registry,
        _backgroundPortName,
        'stop',
        askTimeout,
      );
      if (answer == 'stopped') break;
      if (answer != null) lastAnswer = sw.elapsed;
      if (answer == null &&
          await _ask(_registry, _backgroundPortName, 'ping', askTimeout) ==
              'pong') {
        lastAnswer = sw.elapsed;
      }
      if (sw.elapsed - lastAnswer >= staleAfter) {
        // Nothing answered for a long time: the round's isolate is gone.
        debugPrint('[bg-gate] removing stale background port');
        _registry.remove(_backgroundPortName);
        break;
      }
      if (sw.elapsed >= maxWait) {
        debugPrint(
          '[bg-gate] background round still running after '
          '${sw.elapsed.inSeconds} s — proceeding (wedged round)',
        );
        return false;
      }
    }
    debugPrint(
      '[bg-gate] background round finished after ${sw.elapsedMilliseconds} ms',
    );
    return true;
  }

  /// Gives the app's slot back — when the app's engine detaches (its isolate
  /// is about to end), and in tests.
  void release() {
    final port = _port;
    if (port == null) return;
    _port = null;
    _registry.remove(_mainPortName);
    port.close();
  }

  Future<void> _onMessage(dynamic msg) async {
    if (msg is! List || msg.length != 2 || msg[1] is! SendPort) return;
    final reply = msg[1] as SendPort;
    switch (msg[0]) {
      case 'ping':
        reply.send('pong');
      case 'sync':
        try {
          await onSyncRequest?.call();
        } catch (e) {
          debugPrint('[bg-gate] foreground sync on request failed: $e');
        }
        reply.send('done');
    }
  }
}

/// The background side (one per round).
class BackgroundIsolateGate {
  BackgroundIsolateGate([this._registry = const _IsolateNameServerRegistry()]);

  final PortRegistry _registry;
  ReceivePort? _port;
  final _abort = Completer<void>();
  final List<SendPort> _stopWaiters = [];

  /// Completes when the app asks this round to stop.
  Future<void> get abort => _abort.future;

  /// Whether the app is registered in this process right now — answering or
  /// not (an unanswered app may be busy starting up: never treated as stale
  /// from this side, G18 review).
  Future<bool> appAlive() => _present(_registry, _mainPortName);

  /// Takes the background slot unless the app (or another round) is
  /// registered.
  Future<bool> tryAcquire() async {
    if (await appAlive()) return false;
    if (await _present(_registry, _backgroundPortName)) return false;
    final port = ReceivePort();
    port.listen(_onMessage);
    if (!_registry.register(port.sendPort, _backgroundPortName)) {
      port.close();
      return false;
    }
    _port = port;
    // Re-check after registering: an app that registered in between saw
    // nothing yet (it checks us after registering itself).
    if (await appAlive()) {
      release();
      return false;
    }
    return true;
  }

  /// Asks the app to sync now; true once it reports done. False (no answer)
  /// when the app is registered but busy — the round is skipped then.
  Future<bool> delegateToApp(Duration timeout) async =>
      await _ask(_registry, _mainPortName, 'sync', timeout) == 'done';

  /// Whether the registered app answers a ping (diagnostics only).
  Future<bool> appAnswers() async =>
      await _ask(_registry, _mainPortName, 'ping', _pingTimeout) == 'pong';

  void _onMessage(dynamic msg) {
    if (msg is! List || msg.length != 2 || msg[1] is! SendPort) return;
    final reply = msg[1] as SendPort;
    switch (msg[0]) {
      case 'ping':
        reply.send('pong');
      case 'stop':
        _stopWaiters.add(reply);
        if (!_abort.isCompleted) _abort.complete();
    }
  }

  /// Gives the slot back (after the stores are closed) and tells a waiting
  /// app it may proceed.
  void release() {
    final port = _port;
    if (port == null) return;
    _port = null;
    _registry.remove(_backgroundPortName);
    port.close();
    for (final w in _stopWaiters) {
      w.send('stopped');
    }
    _stopWaiters.clear();
  }
}
