// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Device-verification seam. Overridden with an in-memory fake in tests.

@ProviderFor(deviceGateway)
final deviceGatewayProvider = DeviceGatewayProvider._();

/// Device-verification seam. Overridden with an in-memory fake in tests.

final class DeviceGatewayProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceGateway>,
          DeviceGateway,
          FutureOr<DeviceGateway>
        >
    with $FutureModifier<DeviceGateway>, $FutureProvider<DeviceGateway> {
  /// Device-verification seam. Overridden with an in-memory fake in tests.
  DeviceGatewayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceGatewayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceGatewayHash();

  @$internal
  @override
  $FutureProviderElement<DeviceGateway> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DeviceGateway> create(Ref ref) {
    return deviceGateway(ref);
  }
}

String _$deviceGatewayHash() => r'f15708afc8283ad2bafd4335a225847ac13a1bba';

/// The signed-in user's own devices (this device + other sessions).

@ProviderFor(myDevices)
final myDevicesProvider = MyDevicesProvider._();

/// The signed-in user's own devices (this device + other sessions).

final class MyDevicesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DeviceInfo>>,
          List<DeviceInfo>,
          FutureOr<List<DeviceInfo>>
        >
    with $FutureModifier<List<DeviceInfo>>, $FutureProvider<List<DeviceInfo>> {
  /// The signed-in user's own devices (this device + other sessions).
  MyDevicesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myDevicesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myDevicesHash();

  @$internal
  @override
  $FutureProviderElement<List<DeviceInfo>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<DeviceInfo>> create(Ref ref) {
    return myDevices(ref);
  }
}

String _$myDevicesHash() => r'9f83551ea8abc9b43454793decc872616a725912';
