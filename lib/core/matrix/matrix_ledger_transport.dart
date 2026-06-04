import 'package:matrix/matrix.dart';

import 'ledger_transport.dart';

/// Real [LedgerTransport] backed by the Matrix SDK [Client]. The only place that
/// translates between `package:matrix` types and the app's plain-Dart relay
/// port. Roomless: sends are encrypted to-device messages to members' devices.
class MatrixLedgerTransport implements LedgerTransport {
  final Client _client;
  MatrixLedgerTransport(this._client);

  @override
  String get userId => _client.userID ?? '';

  @override
  Stream<TransportMessage> get onMessage => _client.onToDeviceEvent.stream
      .where((e) => e.type.startsWith(moneyLedgerTypePrefix))
      .map((e) => TransportMessage(
            senderId: e.sender,
            type: e.type,
            content: e.content,
          ));

  @override
  Future<void> sendToUsers(
    Set<String> userIds,
    String type,
    Map<String, dynamic> content,
  ) async {
    final targets = userIds.where((u) => u.isNotEmpty).toSet();
    if (targets.isEmpty) return;

    // Roomless device tracking isn't persistent: the SDK evicts device lists for
    // users we share no encrypted room with. Re-resolve before each send (cheap,
    // idempotent) so we always have the current device set.
    await _client.updateUserDeviceKeys(additionalUsers: targets);

    final devices = <DeviceKeys>[];
    for (final u in targets) {
      final dk = _client.userDeviceKeys[u]?.deviceKeys.values;
      if (dk != null) devices.addAll(dk);
    }
    if (devices.isEmpty) return;

    // Encrypts and sends; our own current device is auto-excluded. Chunked to
    // stay within per-request to-device limits when there are many devices.
    await _client.sendToDeviceEncryptedChunked(devices, type, content);
  }
}
