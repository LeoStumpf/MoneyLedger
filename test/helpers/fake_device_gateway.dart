/// In-memory [DeviceGateway] for testing the devices UI — no real homeserver,
/// no olm. The verification session emits a fixed emoji list and, on confirm,
/// marks the device verified.
library;

import 'dart:async';

import 'package:money_ledger/core/matrix/device_gateway.dart';

class FakeDeviceGateway implements DeviceGateway {
  List<DeviceInfo> devices;
  FakeDeviceGateway(this.devices);

  static const sampleEmojis = [
    SasEmoji('🐶', 'Dog'),
    SasEmoji('🐱', 'Cat'),
    SasEmoji('🦁', 'Lion'),
  ];

  @override
  Future<List<DeviceInfo>> myDevices() async => devices;

  @override
  VerificationSession verifyDevice(String deviceId) =>
      FakeVerificationSession(this, deviceId);
}

class FakeVerificationSession implements VerificationSession {
  final FakeDeviceGateway _gateway;
  final String _deviceId;
  // Single-subscription so the "compare these emojis" event buffers until the
  // dialog's StreamBuilder attaches (a broadcast controller would drop it).
  final _controller = StreamController<VerificationState>();

  FakeVerificationSession(this._gateway, this._deviceId) {
    _controller.add(
      const VerificationState(
        VerificationPhase.compareEmojis,
        emojis: FakeDeviceGateway.sampleEmojis,
      ),
    );
  }

  @override
  Stream<VerificationState> get updates => _controller.stream;

  @override
  Future<void> confirmMatch() async {
    _gateway.devices = [
      for (final d in _gateway.devices)
        if (d.deviceId == _deviceId)
          DeviceInfo(
            deviceId: d.deviceId,
            displayName: d.displayName,
            isThisDevice: d.isThisDevice,
            verified: true,
          )
        else
          d,
    ];
    if (!_controller.isClosed) {
      _controller.add(const VerificationState(VerificationPhase.success));
    }
  }

  @override
  Future<void> cancel() async {
    if (!_controller.isClosed) {
      _controller.add(const VerificationState(VerificationPhase.failed));
    }
  }

  @override
  void dispose() => _controller.close();
}
