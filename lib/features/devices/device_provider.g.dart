// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Device-verification seam. Overridden with an in-memory fake in tests.
/// G40: local mode has no devices — it fails (no Matrix client is built);
/// device lists read as unavailable and no verification is listened for.

@ProviderFor(deviceGateway)
final deviceGatewayProvider = DeviceGatewayProvider._();

/// Device-verification seam. Overridden with an in-memory fake in tests.
/// G40: local mode has no devices — it fails (no Matrix client is built);
/// device lists read as unavailable and no verification is listened for.

final class DeviceGatewayProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceGateway>,
          DeviceGateway,
          FutureOr<DeviceGateway>
        >
    with $FutureModifier<DeviceGateway>, $FutureProvider<DeviceGateway> {
  /// Device-verification seam. Overridden with an in-memory fake in tests.
  /// G40: local mode has no devices — it fails (no Matrix client is built);
  /// device lists read as unavailable and no verification is listened for.
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

String _$deviceGatewayHash() => r'f43ccca5df53235084e8c1c620f5e093fe159210';

/// G11: the devices this account verified by emoji comparison (device-local,
/// per account — the app's own record, see `SettingsDao.markDeviceVerified`).

@ProviderFor(trustedDevices)
final trustedDevicesProvider = TrustedDevicesProvider._();

/// G11: the devices this account verified by emoji comparison (device-local,
/// per account — the app's own record, see `SettingsDao.markDeviceVerified`).

final class TrustedDevicesProvider
    extends
        $FunctionalProvider<
          AsyncValue<Set<SignerId>>,
          Set<SignerId>,
          Stream<Set<SignerId>>
        >
    with $FutureModifier<Set<SignerId>>, $StreamProvider<Set<SignerId>> {
  /// G11: the devices this account verified by emoji comparison (device-local,
  /// per account — the app's own record, see `SettingsDao.markDeviceVerified`).
  TrustedDevicesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trustedDevicesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trustedDevicesHash();

  @$internal
  @override
  $StreamProviderElement<Set<SignerId>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Set<SignerId>> create(Ref ref) {
    return trustedDevices(ref);
  }
}

String _$trustedDevicesHash() => r'dab91c8b118c8d997c2a319d9fee17bbb4a4933a';

/// G11: "Only sync with verified devices" (device-local, per account,
/// default off). Signed out → false.

@ProviderFor(verifiedOnlySync)
final verifiedOnlySyncProvider = VerifiedOnlySyncProvider._();

/// G11: "Only sync with verified devices" (device-local, per account,
/// default off). Signed out → false.

final class VerifiedOnlySyncProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, Stream<bool>>
    with $FutureModifier<bool>, $StreamProvider<bool> {
  /// G11: "Only sync with verified devices" (device-local, per account,
  /// default off). Signed out → false.
  VerifiedOnlySyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'verifiedOnlySyncProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$verifiedOnlySyncHash();

  @$internal
  @override
  $StreamProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<bool> create(Ref ref) {
    return verifiedOnlySync(ref);
  }
}

String _$verifiedOnlySyncHash() => r'7808097c26a2c5429a9df5d62a20d1e5e728f503';

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

String _$myDevicesHash() => r'e480468d578baa80f6b7989aa0f99fed0018bef4';

/// G11: another member's ([matrixId]) current devices with their verified
/// state (SDK + this account's record), as the homeserver lists them.

@ProviderFor(memberDevices)
final memberDevicesProvider = MemberDevicesFamily._();

/// G11: another member's ([matrixId]) current devices with their verified
/// state (SDK + this account's record), as the homeserver lists them.

final class MemberDevicesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DeviceInfo>>,
          List<DeviceInfo>,
          FutureOr<List<DeviceInfo>>
        >
    with $FutureModifier<List<DeviceInfo>>, $FutureProvider<List<DeviceInfo>> {
  /// G11: another member's ([matrixId]) current devices with their verified
  /// state (SDK + this account's record), as the homeserver lists them.
  MemberDevicesProvider._({
    required MemberDevicesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'memberDevicesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$memberDevicesHash();

  @override
  String toString() {
    return r'memberDevicesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<DeviceInfo>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<DeviceInfo>> create(Ref ref) {
    final argument = this.argument as String;
    return memberDevices(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MemberDevicesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$memberDevicesHash() => r'879f6817e03dcf0185f042ab2c463c42f840d286';

/// G11: another member's ([matrixId]) current devices with their verified
/// state (SDK + this account's record), as the homeserver lists them.

final class MemberDevicesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<DeviceInfo>>, String> {
  MemberDevicesFamily._()
    : super(
        retry: null,
        name: r'memberDevicesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// G11: another member's ([matrixId]) current devices with their verified
  /// state (SDK + this account's record), as the homeserver lists them.

  MemberDevicesProvider call(String matrixId) =>
      MemberDevicesProvider._(argument: matrixId, from: this);

  @override
  String toString() => r'memberDevicesProvider';
}
