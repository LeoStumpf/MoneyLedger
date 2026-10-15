/// Plain-Dart inbound buffer between the relay's raw message source and the
/// app's sync components. **No `package:matrix` import** (unit-tested offline).
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show debugPrint;

import 'ledger_transport.dart';

/// Keeps inbound [TransportMessage]s that arrive while **nobody listens** and
/// replays them, in order, to the next listeners.
///
/// The Matrix SDK's to-device stream is a plain broadcast stream: an event
/// emitted while no one is subscribed is consumed (the sync token advances)
/// and gone until the next digest cycle (≤10 min). That happens at app start
/// (the first `/sync` runs in the background before `LedgerSyncer` /
/// `SyncEngine` have subscribed — they wait for the account DB) and during an
/// account-DB switch (old components disposed, new ones not yet attached).
/// The transport adapter feeds every inbound payload into [add] from the
/// moment the client exists, so nothing is dropped in those windows.
///
/// Replay is deferred by [replayDelay] after the first listener attaches, so
/// every sync component that attaches in the same start-up turn (LedgerSyncer
/// *and* SyncEngine) sees the backlog. Messages arriving while a replay is
/// pending queue behind it (order is preserved).
///
/// Bounded: at most [capacity] messages are kept (oldest dropped — anti-entropy
/// repairs anything lost). Each message records the account it was received
/// for ([currentRecipient]); on replay, messages received for a different
/// account than the current one are discarded, so a backlog can never leak
/// into another account's ledger after an account switch.
class BufferedInbox {
  BufferedInbox({
    this.capacity = 500,
    this.replayDelay = const Duration(milliseconds: 50),
    this.currentRecipient,
    this.onReplay,
  }) {
    _controller = StreamController<TransportMessage>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
  }

  final int capacity;
  final Duration replayDelay;

  /// The account messages are currently received for (`null` → no check).
  final String Function()? currentRecipient;

  /// Called once per replayed message (the fake network counts it as activity).
  final void Function()? onReplay;

  late final StreamController<TransportMessage> _controller;
  final Queue<({String? recipient, TransportMessage message})> _backlog =
      Queue();
  Timer? _replayTimer;
  int _dropped = 0;

  /// The listener-facing stream (broadcast).
  Stream<TransportMessage> get stream => _controller.stream;

  /// Messages currently held for replay.
  int get pending => _backlog.length;

  /// Feeds one inbound message.
  void add(TransportMessage message) {
    if (_controller.isClosed) return;
    if (_controller.hasListener && _replayTimer == null && _backlog.isEmpty) {
      _controller.add(message);
      return;
    }
    if (_backlog.isEmpty && !_controller.hasListener) {
      debugPrint('[transport] no listener yet — buffering inbound payloads');
    }
    _backlog.add((recipient: currentRecipient?.call(), message: message));
    if (_backlog.length > capacity) {
      _backlog.removeFirst();
      if (_dropped++ == 0) {
        debugPrint('[transport] inbound backlog full ($capacity) — dropping '
            'oldest; anti-entropy will repair');
      }
    }
    if (_controller.hasListener) _scheduleReplay();
  }

  void _onListen() {
    if (_backlog.isNotEmpty) _scheduleReplay();
  }

  void _onCancel() {
    // Last listener gone (dispose / account switch): keep the backlog — the
    // next listeners get it.
    _replayTimer?.cancel();
    _replayTimer = null;
  }

  void _scheduleReplay() {
    _replayTimer ??= Timer(replayDelay, _replay);
  }

  void _replay() {
    _replayTimer = null;
    if (!_controller.hasListener || _controller.isClosed) return;
    final now = currentRecipient?.call();
    var replayed = 0;
    while (_backlog.isNotEmpty) {
      final entry = _backlog.removeFirst();
      if (currentRecipient != null && entry.recipient != now) continue;
      _controller.add(entry.message);
      onReplay?.call();
      replayed++;
    }
    _dropped = 0;
    if (replayed > 0) {
      debugPrint('[transport] replayed $replayed buffered inbound message(s)');
    }
  }

  Future<void> close() {
    _replayTimer?.cancel();
    return _controller.close();
  }
}
