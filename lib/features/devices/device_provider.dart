import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/matrix/device_gateway.dart';
import '../../core/matrix/matrix_device_gateway.dart';
import '../auth/auth_provider.dart';

part 'device_provider.g.dart';

/// Device-verification seam. Overridden with an in-memory fake in tests.
@Riverpod(keepAlive: true)
Future<DeviceGateway> deviceGateway(Ref ref) async {
  final client = await ref.watch(matrixClientProvider.future);
  return MatrixDeviceGateway(client);
}

/// The signed-in user's own devices (this device + other sessions).
@riverpod
Future<List<DeviceInfo>> myDevices(Ref ref) async {
  final gateway = await ref.watch(deviceGatewayProvider.future);
  return sortDevices(await gateway.myDevices());
}
