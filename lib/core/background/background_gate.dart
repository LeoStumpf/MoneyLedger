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
/// isolate dies), so "is the other side there?" is a ping that must be
/// answered; an unanswered name is stale and removed.
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

import 'package:flutter/foundation.dart' show debugPrint;

const _mainPortName = 'app.moneyledger.main';
const _backgroundPortName = 'app.moneyledger.background';
const _pingTimeout = Duration(seconds: 2);

/// Sends `[command, reply]` to the port registered as [name] and waits for the
/// first answer. Null when nothing is registered or no answer came in time.
Future<Object?> _ask(String name, String command, Duration timeout) async {
  final port = IsolateNameServer.lookupPortByName(name);
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

/// Whether the side registered as [name] is alive; a stale mapping (its
/// isolate is gone) is removed.
Future<bool> _isAlive(String name) async {
  if (IsolateNameServer.lookupPortByName(name) == null) return false;
  if (await _ask(name, 'ping', _pingTimeout) == 'pong') return true;
  debugPrint('[bg-gate] removing stale port $name');
  IsolateNameServer.removePortNameMapping(name);
  return false;
}

/// The app side. [claim] runs in `main()` **before** the Matrix client / DB
/// are opened.
class AppIsolateGate {
  AppIsolateGate._();
  static final instance = AppIsolateGate._();

  ReceivePort? _port;

  /// Runs a quick foreground sync when a background round finds the app
  /// alive (set once the app's container exists). Null → answered at once.
  Future<void> Function()? onSyncRequest;

  /// Registers the app and waits (bounded by [maxWait]) for a running
  /// background round to stop and close its stores.
  Future<void> claim({Duration maxWait = const Duration(seconds: 15)}) async {
    if (_port != null) return;
    final port = _port = ReceivePort();
    port.listen(_onMessage);
    // A previous app isolate in this process is gone (we are the new one).
    IsolateNameServer.removePortNameMapping(_mainPortName);
    IsolateNameServer.registerPortWithName(port.sendPort, _mainPortName);

    if (!await _isAlive(_backgroundPortName)) return;
    debugPrint('[bg-gate] background round running — asking it to stop');
    final sw = Stopwatch()..start();
    // Re-ask in short slices: the round may release (and close its port) at
    // any moment, which drops a pending request — the mapping disappearing is
    // the answer then.
    var stopped = false;
    while (sw.elapsed < maxWait) {
      if (IsolateNameServer.lookupPortByName(_backgroundPortName) == null ||
          await _ask(_backgroundPortName, 'stop', const Duration(seconds: 1)) ==
              'stopped') {
        stopped = true;
        break;
      }
    }
    debugPrint(
      '[bg-gate] background round '
      '${stopped ? 'stopped' : 'did not stop in time'} '
      'after ${sw.elapsedMilliseconds} ms',
    );
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
  ReceivePort? _port;
  final _abort = Completer<void>();
  final List<SendPort> _stopWaiters = [];

  /// Completes when the app asks this round to stop.
  Future<void> get abort => _abort.future;

  /// Whether the app is alive in this process right now.
  Future<bool> appAlive() => _isAlive(_mainPortName);

  /// Takes the background slot unless the app (or another round) is alive.
  Future<bool> tryAcquire() async {
    if (await appAlive()) return false;
    if (await _isAlive(_backgroundPortName)) return false;
    final port = ReceivePort();
    port.listen(_onMessage);
    if (!IsolateNameServer.registerPortWithName(
      port.sendPort,
      _backgroundPortName,
    )) {
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

  /// Asks the alive app to sync now; true once it reports done.
  Future<bool> delegateToApp(Duration timeout) async =>
      await _ask(_mainPortName, 'sync', timeout) == 'done';

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
    IsolateNameServer.removePortNameMapping(_backgroundPortName);
    port.close();
    for (final w in _stopWaiters) {
      w.send('stopped');
    }
    _stopWaiters.clear();
  }
}
