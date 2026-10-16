import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:matrix/matrix.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'buffered_inbox.dart';
import 'ledger_transport.dart';

/// Real [LedgerTransport] backed by the Matrix SDK [Client]. The only place that
/// translates between `package:matrix` types and the app's plain-Dart relay
/// port. Roomless: sends are encrypted to-device messages to members' devices.
class MatrixLedgerTransport implements LedgerTransport {
  final Client _client;
  late final BufferedInbox _inbox;
  StreamSubscription<ToDeviceEvent>? _sub;

  static final _byClient = Expando<MatrixLedgerTransport>('ledgerTransport');

  /// The single transport for [client], created on first call. Call it right
  /// after constructing the client and **before** `client.init()`: the
  /// transport subscribes to the SDK's (unbuffered) to-device stream at once,
  /// so events from the first background `/sync` are buffered until the sync
  /// components attach instead of being lost (G24).
  static MatrixLedgerTransport forClient(Client client) =>
      _byClient[client] ??= MatrixLedgerTransport._(client);

  MatrixLedgerTransport._(this._client) {
    _inbox = BufferedInbox(currentRecipient: () => _client.userID ?? '');
    _sub = _client.onToDeviceEvent.stream
        .where((e) => e.type.startsWith(moneyLedgerTypePrefix))
        .listen(
          (e) => _inbox.add(
            TransportMessage(
              senderId: e.sender,
              type: e.type,
              content: e.content,
            ),
          ),
        );
  }

  @override
  String get userId => _client.userID ?? '';

  @override
  Stream<TransportMessage> get onMessage => _inbox.stream;

  @override
  Future<SendResult> sendToUsers(
    Set<String> userIds,
    String type,
    Map<String, dynamic> content,
  ) async {
    final targets = userIds.where((u) => u.isNotEmpty).toSet();
    if (targets.isEmpty) return SendResult.nothingToSend;

    // The SDK's sendToDeviceEncryptedChunked returns silently when encryption
    // is off — surface it instead of reporting a send that never happened.
    if (!_client.isLogged()) {
      throw const TransportUnavailableException('not signed in');
    }
    if (!_client.encryptionEnabled) {
      throw const TransportUnavailableException('encryption is not enabled');
    }

    // Roomless device tracking isn't persistent: the SDK evicts device lists for
    // users we share no encrypted room with. Re-resolve before each send (cheap,
    // idempotent) so we always have the current device set.
    await _client.updateUserDeviceKeys(additionalUsers: targets);

    final plan = planDeviceSend(
      targets: targets,
      selfUserId: _client.userID ?? '',
      selfDeviceId: _client.deviceID,
      devicesByUser: {
        for (final u in targets)
          u: [
            for (final dk
                in _client.userDeviceKeys[u]?.deviceKeys.values ??
                    const <DeviceKeys>[])
              if (dk.deviceId != null)
                (deviceId: dk.deviceId!, blocked: dk.blocked),
          ],
      },
    );
    final devices = <DeviceKeys>[
      for (final MapEntry(key: user, value: ids) in plan.devices.entries)
        for (final id in ids) ?_client.userDeviceKeys[user]?.deviceKeys[id],
    ];
    if (kDebugMode) {
      debugPrint(
        '[transport] send ${type.substring(moneyLedgerTypePrefix.length)}'
        '${content['group'] is String ? ' group=${content['group']}' : ''}'
        ' → ${devices.length} device(s)'
        '${plan.unreachableUsers.isEmpty ? '' : ', no device: ${plan.unreachableUsers.join(', ')}'}',
      );
    }
    if (devices.isNotEmpty) {
      // Encrypts and sends. Chunked to stay within per-request to-device
      // limits when there are many devices.
      await _client.sendToDeviceEncryptedChunked(devices, type, content);
    }
    return SendResult(
      unreachableUsers: plan.unreachableUsers,
      deviceCount: devices.length,
    );
  }

  @override
  Future<String?> profileName(String matrixId) async {
    try {
      final profile = await _client.getUserProfile(
        matrixId,
        timeout: const Duration(seconds: 5),
      );
      return normalizeProfileName(profile.displayname);
    } catch (e) {
      if (kDebugMode) debugPrint('[transport] profile of $matrixId: $e');
      return null;
    }
  }

  @override
  late final RecordCrypto crypto = MatrixRecordCrypto(_client);

  @override
  late final DeviceKeyDirectory deviceKeys = MatrixDeviceKeyDirectory(_client);

  /// Stops listening (the client is app-lifetime, so this is rarely needed).
  Future<void> dispose() async {
    await _sub?.cancel();
    await _inbox.close();
  }
}

/// G6: signs records with this device's Matrix Ed25519 fingerprint key (the
/// vodozemac olm account) and verifies Ed25519 signatures via vodozemac —
/// native and web (wasm) alike.
class MatrixRecordCrypto implements RecordCrypto {
  MatrixRecordCrypto(this._client);
  final Client _client;

  @override
  SignerId? get identity {
    final user = _client.userID;
    final device = _client.deviceID;
    final key = _client.encryption?.fingerprintKey;
    if (!_client.isLogged() || !_client.encryptionEnabled) return null;
    if (user == null || device == null || key == null) return null;
    return SignerId(user: user, device: device, key: key);
  }

  @override
  Future<String> sign(String message) async {
    final encryption = _client.encryption;
    if (encryption == null || !encryption.enabled) {
      throw const TransportUnavailableException('encryption is not enabled');
    }
    return encryption.olmManager.signString(message);
  }

  @override
  bool verify(String key, String message, String signature) {
    try {
      vod.Ed25519PublicKey.fromBase64(key).verify(
        message: message,
        signature: vod.Ed25519Signature.fromBase64(signature),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// G6: the homeserver's current (self-signed, unblocked) device keys.
class MatrixDeviceKeyDirectory implements DeviceKeyDirectory {
  MatrixDeviceKeyDirectory(this._client);
  final Client _client;

  @override
  Future<Map<String, Map<String, String>>> currentDevices(
    Set<String> users,
  ) async {
    final targets = users.where((u) => u.isNotEmpty).toSet();
    if (targets.isEmpty || !_client.isLogged()) return const {};
    await _client.updateUserDeviceKeys(additionalUsers: targets);
    final result = <String, Map<String, String>>{};
    for (final u in targets) {
      final devices = <String, String>{};
      for (final dk
          in _client.userDeviceKeys[u]?.deviceKeys.values ??
              const <DeviceKeys>[]) {
        final id = dk.deviceId;
        final key = dk.ed25519Key;
        if (id == null || key == null || !dk.isValid || dk.blocked) continue;
        devices[id] = key;
      }
      if (devices.isNotEmpty) result[u] = devices;
    }
    return result;
  }
}
