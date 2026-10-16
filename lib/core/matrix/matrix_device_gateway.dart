import 'dart:async';

// hide DeviceInfo: the SDK exports a same-named type; ours is the app port type.
import 'package:matrix/matrix.dart' hide DeviceInfo;
import 'package:matrix/encryption.dart';

import 'device_gateway.dart';

/// Real [DeviceGateway] backed by the Matrix SDK [Client] — the only place that
/// translates the SDK's device-key + key-verification types into the app's
/// plain-Dart device port. Not unit-tested (needs a real homeserver + a second
/// device + olm); the verification round-trip is manual-smoke, like the SSO
/// deep link. The pure view-model around it (`device_gateway.dart`) is tested.
class MatrixDeviceGateway implements DeviceGateway {
  final Client _client;
  MatrixDeviceGateway(this._client);

  @override
  Future<List<DeviceInfo>> myDevices() async {
    final userId = _client.userID;
    if (userId == null) return [];
    final keys = _client.userDeviceKeys[userId]?.deviceKeys.values ?? const [];
    return [
      for (final dk in keys)
        DeviceInfo(
          deviceId: dk.deviceId ?? '',
          displayName: dk.deviceDisplayName,
          isThisDevice: dk.deviceId == _client.deviceID,
          verified: dk.verified,
        ),
    ];
  }

  @override
  VerificationSession verifyDevice(String deviceId) {
    final userId = _client.userID;
    final dk = _client.userDeviceKeys[userId]?.deviceKeys[deviceId];
    return _MatrixVerificationSession(dk);
  }
}

class _MatrixVerificationSession implements VerificationSession {
  final DeviceKeys? _device;
  final _controller = StreamController<VerificationState>.broadcast();
  KeyVerification? _kv;

  _MatrixVerificationSession(this._device) {
    _start();
  }

  @override
  Stream<VerificationState> get updates => _controller.stream;

  Future<void> _start() async {
    final device = _device;
    if (device == null) {
      _emit(
        const VerificationState(
          VerificationPhase.failed,
          error: 'Unknown device',
        ),
      );
      return;
    }
    _controller.add(const VerificationState(VerificationPhase.starting));
    try {
      final kv = await device.startVerification();
      _kv = kv;
      kv.onUpdate = () => _onUpdate(kv);
      _onUpdate(kv);
    } catch (e) {
      _emit(VerificationState(VerificationPhase.failed, error: e.toString()));
    }
  }

  void _onUpdate(KeyVerification kv) {
    switch (kv.state) {
      case KeyVerificationState.askSas:
        _emit(
          VerificationState(
            VerificationPhase.compareEmojis,
            emojis: [for (final e in kv.sasEmojis) SasEmoji(e.emoji, e.name)],
          ),
        );
      case KeyVerificationState.done:
        _emit(const VerificationState(VerificationPhase.success));
      case KeyVerificationState.error:
        _emit(
          VerificationState(VerificationPhase.failed, error: kv.canceledReason),
        );
      default:
        _emit(const VerificationState(VerificationPhase.starting));
    }
  }

  void _emit(VerificationState s) {
    if (!_controller.isClosed) _controller.add(s);
  }

  @override
  Future<void> confirmMatch() async => _kv?.acceptSas();

  @override
  Future<void> cancel() async => _kv?.cancel();

  @override
  void dispose() {
    _kv?.onUpdate = null;
    _controller.close();
  }
}
