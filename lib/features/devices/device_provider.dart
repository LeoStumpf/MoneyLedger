import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/matrix/device_gateway.dart';
import '../../core/matrix/matrix_device_gateway.dart';
import '../../core/matrix/record_crypto.dart';
import '../../core/session/app_session.dart';
import '../auth/auth_provider.dart';
import '../onboarding/onboarding_provider.dart';

part 'device_provider.g.dart';

/// Device-verification seam. Overridden with an in-memory fake in tests.
/// G40: local mode has no devices — it fails (no Matrix client is built);
/// device lists read as unavailable and no verification is listened for.
@Riverpod(keepAlive: true)
Future<DeviceGateway> deviceGateway(Ref ref) async {
  // (Also while the device preferences load — never build a Matrix client
  // before we know it isn't local mode; this rebuilds once they load.)
  if (!ref.watch(matrixSessionWantedProvider)) {
    throw StateError('Local mode: no Matrix devices');
  }
  final client = await ref.watch(matrixClientProvider.future);
  return MatrixDeviceGateway(client);
}

/// G11: the devices this account verified by emoji comparison (device-local,
/// per account — the app's own record, see `SettingsDao.markDeviceVerified`).
@riverpod
Stream<Set<SignerId>> trustedDevices(Ref ref) =>
    ref.watch(settingsDaoProvider).watchVerifiedDevices();

/// G11: records a successful emoji verification in this account's
/// verified-device list. Injectable for widget tests.
final deviceTrustRecorderProvider =
    Provider<Future<void> Function(SignerId device)>(
      (ref) => ref.watch(settingsDaoProvider).markDeviceVerified,
    );

/// G11: "Only sync with verified devices" (device-local, per account,
/// default off). Signed out → false.
@riverpod
Stream<bool> verifiedOnlySync(Ref ref) {
  if (ref.watch(accountUserIdProvider) == null) return Stream.value(false);
  return ref.watch(settingsDaoProvider).watchVerifiedOnlySync();
}

/// The signed-in user's own devices (this device + other sessions).
@riverpod
Future<List<DeviceInfo>> myDevices(Ref ref) async {
  final gateway = await ref.watch(deviceGatewayProvider.future);
  final trusted = await ref.watch(trustedDevicesProvider.future);
  return sortDevices([
    for (final d in await gateway.myDevices()) d.withTrust(trusted),
  ]);
}

/// G11: another member's ([matrixId]) current devices with their verified
/// state (SDK + this account's record), as the homeserver lists them.
@riverpod
Future<List<DeviceInfo>> memberDevices(Ref ref, String matrixId) async {
  final gateway = await ref.watch(deviceGatewayProvider.future);
  final trusted = await ref.watch(trustedDevicesProvider.future);
  return sortDevices([
    for (final d in await gateway.userDevices(matrixId)) d.withTrust(trusted),
  ]);
}
