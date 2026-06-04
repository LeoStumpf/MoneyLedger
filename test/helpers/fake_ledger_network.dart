/// An in-memory "virtual relay": multiple users, each with one [FakeTransport]
/// (one device), all sharing one [FakeMatrixNetwork]. Models the Phase B
/// roomless to-device relay — `sendToUsers` delivers an encrypted-equivalent
/// payload to each target user's inbound stream. No rooms, no real Matrix
/// client, no sqlite3, no network.
///
/// Wire it into the app by overriding `ledgerTransportProvider` with
/// `net.clientFor(userId)`.
///
/// No `package:matrix` import — it only depends on the plain-Dart transport port.
library;

import 'dart:async';

import 'package:money_ledger/core/matrix/ledger_transport.dart';

class FakeMatrixNetwork {
  final Map<String, FakeTransport> _clients = {};

  /// Returns (creating on first use) the transport view for [userId], e.g.
  /// `@alice:x.org`. Create a user's transport before they need to receive
  /// payloads so delivery has somewhere to go.
  FakeTransport clientFor(String userId) =>
      _clients.putIfAbsent(userId, () => FakeTransport(this, userId));

  void _send(
    String sender,
    Set<String> targets,
    String type,
    Map<String, dynamic> content,
  ) {
    for (final target in targets) {
      // A real homeserver excludes the sender's *current* device but still
      // reaches their other devices. The fake models one device per user, so
      // there's no "other device" to deliver to — skip self.
      if (target == sender) continue;
      _clients[target]
          ?._emit(TransportMessage(senderId: sender, type: type, content: content));
    }
  }

  /// Lets queued stream events propagate to listeners. Call after each action
  /// before asserting on derived provider state.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class FakeTransport implements LedgerTransport {
  final FakeMatrixNetwork _net;
  @override
  final String userId;
  final StreamController<TransportMessage> _controller =
      StreamController.broadcast();

  FakeTransport(this._net, this.userId);

  void _emit(TransportMessage m) {
    if (!_controller.isClosed) _controller.add(m);
  }

  void dispose() => _controller.close();

  @override
  Stream<TransportMessage> get onMessage => _controller.stream;

  @override
  Future<void> sendToUsers(
    Set<String> userIds,
    String type,
    Map<String, dynamic> content,
  ) async =>
      _net._send(userId, userIds, type, content);
}
