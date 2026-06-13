/// An in-memory "virtual relay": multiple users, each with one or more
/// [FakeTransport]s (devices), all sharing one [FakeMatrixNetwork]. Models the
/// roomless to-device relay — `sendToUsers` delivers an encrypted-equivalent
/// payload to every device of each target user, except the exact sending
/// device (real homeserver semantics: your *other* devices do receive).
/// No rooms, no real Matrix client, no sqlite3, no network.
///
/// Wire it into the app by overriding `ledgerTransportProvider` with
/// `net.clientFor(userId)` (or `clientFor(userId, device: 'D2')` for a
/// second device of the same account).
///
/// No `package:matrix` import — it only depends on the plain-Dart transport port.
library;

import 'dart:async';

import 'package:money_ledger/core/matrix/ledger_transport.dart';

class FakeMatrixNetwork {
  // userId → (deviceId → transport)
  final Map<String, Map<String, FakeTransport>> _clients = {};

  /// Loss injection: when set, any delivery for which this returns true is
  /// silently dropped — simulates a to-device message lost in transit, the
  /// exact failure anti-entropy must repair. Set back to null to "reconnect".
  bool Function(String sender, String target, String type)? dropWhere;

  /// Returns (creating on first use) the transport view for one device of
  /// [userId], e.g. `@alice:x.org`. Create a user's transport before they
  /// need to receive payloads so delivery has somewhere to go.
  FakeTransport clientFor(String userId, {String device = 'D1'}) =>
      _clients.putIfAbsent(userId, () => {}).putIfAbsent(
          device, () => FakeTransport(this, userId));

  void _send(
    FakeTransport senderDevice,
    Set<String> targets,
    String type,
    Map<String, dynamic> content,
  ) {
    final sender = senderDevice.userId;
    for (final target in targets) {
      if (dropWhere?.call(sender, target, type) ?? false) continue;
      for (final device in (_clients[target] ?? const {}).values) {
        // A real homeserver excludes only the sender's *current* device —
        // the sender's other devices do receive the payload.
        if (identical(device, senderDevice)) continue;
        device._emit(
            TransportMessage(senderId: sender, type: type, content: content));
      }
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
      _net._send(this, userIds, type, content);
}
