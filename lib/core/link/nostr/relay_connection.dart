/// G52 step 2: the relay connection port and its WebSocket adapter (design
/// doc `docs/design/no-login-sharing.md` §4.3).
///
/// [NostrRelayPool] only talks to relays through [RelayConnector] /
/// [RelayConnection], so tests run it against the in-memory
/// `test/helpers/fake_relay_network.dart` — never a real relay.
library;

import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens connections to relays.
abstract interface class RelayConnector {
  /// Connects to the relay at [url] (`wss://…`). Completes once the
  /// connection is open; throws when it can't be opened (the pool bounds
  /// the wait with its own connect timeout).
  Future<RelayConnection> connect(String url);
}

/// One open connection to a relay, carrying NIP-01 text frames.
abstract interface class RelayConnection {
  /// Incoming text frames. Done (or an error) = the connection is gone;
  /// single-subscription.
  Stream<String> get frames;

  /// Sends one text frame. Ignored once the connection is closed.
  void send(String frame);

  /// Closes the connection ([frames] completes).
  Future<void> close();
}

/// The real adapter: one WebSocket per relay via `web_socket_channel`
/// (`WebSocketChannel.connect` picks `dart:io` natively and the browser
/// WebSocket on the web).
class WebSocketRelayConnector implements RelayConnector {
  const WebSocketRelayConnector();

  @override
  Future<RelayConnection> connect(String url) async {
    final channel = WebSocketChannel.connect(Uri.parse(url));
    try {
      await channel.ready;
    } catch (_) {
      unawaited(channel.sink.close().catchError((_) {}));
      rethrow;
    }
    return _WebSocketRelayConnection(channel);
  }
}

class _WebSocketRelayConnection implements RelayConnection {
  final WebSocketChannel _channel;
  bool _closed = false;

  _WebSocketRelayConnection(this._channel);

  @override
  late final Stream<String> frames = _channel.stream
      .where((m) => m is String)
      .cast<String>();

  @override
  void send(String frame) {
    if (_closed) return;
    try {
      _channel.sink.add(frame);
    } catch (_) {
      // The sink is already closed: the frames stream ends on its own.
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _channel.sink.close();
    } catch (_) {}
  }
}
