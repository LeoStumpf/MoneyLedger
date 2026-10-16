import 'dart:async';

import '../matrix/device_gateway.dart';

/// Offline [DeviceGateway] for the demo: this device plus one already
/// verified second session (so no verification is ever started).
class DemoDeviceGateway implements DeviceGateway {
  @override
  Future<List<DeviceInfo>> myDevices() async => const [
    DeviceInfo(
      deviceId: 'DEMOPHONE',
      displayName: 'MoneyLedger (Android)',
      isThisDevice: true,
      verified: true,
    ),
    DeviceInfo(
      deviceId: 'DEMOWEB',
      displayName: 'MoneyLedger (Web)',
      isThisDevice: false,
      verified: true,
    ),
  ];

  @override
  VerificationSession verifyDevice(String deviceId) => _NoVerification();
}

/// Verification isn't simulated: the session reports failure immediately.
class _NoVerification implements VerificationSession {
  @override
  Stream<VerificationState> get updates =>
      Stream.value(const VerificationState(VerificationPhase.failed));

  @override
  Future<void> confirmMatch() async {}

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}
