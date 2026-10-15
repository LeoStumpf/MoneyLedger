// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(settingsDao)
final settingsDaoProvider = SettingsDaoProvider._();

final class SettingsDaoProvider
    extends $FunctionalProvider<SettingsDao, SettingsDao, SettingsDao>
    with $Provider<SettingsDao> {
  SettingsDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsDaoHash();

  @$internal
  @override
  $ProviderElement<SettingsDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SettingsDao create(Ref ref) {
    return settingsDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsDao>(value),
    );
  }
}

String _$settingsDaoHash() => r'3fb5dd0a2aeb1dba479a4ba86b8afa7e36b58827';

/// The flag lives in the **per-account** ledger DB (G4), so onboarding is
/// shown once per account on a device. Signed out there is no DB to read and
/// the router never forces onboarding anyway → report "seen".

@ProviderFor(onboardingSeenStream)
final onboardingSeenStreamProvider = OnboardingSeenStreamProvider._();

/// The flag lives in the **per-account** ledger DB (G4), so onboarding is
/// shown once per account on a device. Signed out there is no DB to read and
/// the router never forces onboarding anyway → report "seen".

final class OnboardingSeenStreamProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, Stream<bool>>
    with $FutureModifier<bool>, $StreamProvider<bool> {
  /// The flag lives in the **per-account** ledger DB (G4), so onboarding is
  /// shown once per account on a device. Signed out there is no DB to read and
  /// the router never forces onboarding anyway → report "seen".
  OnboardingSeenStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onboardingSeenStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onboardingSeenStreamHash();

  @$internal
  @override
  $StreamProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<bool> create(Ref ref) {
    return onboardingSeenStream(ref);
  }
}

String _$onboardingSeenStreamHash() =>
    r'8321bd1094cec9dc52da00c31de0dc557e7ccab5';

/// Router-facing onboarding state. Signed out → [OnboardingStatus.seen] (the
/// router never forces onboarding then). Signed in → [OnboardingStatus.unknown]
/// until the account's flag loads; a flag still *reloading* after an account
/// switch counts as unknown too, so the previous account's (or the signed-out
/// placeholder's) value is never reused. After [kOnboardingFlagTimeout] (or a
/// stream error) the answer latches to seen for that account — a late "not
/// seen" then no longer yanks the user to onboarding mid-use; it shows on the
/// next start instead.

@ProviderFor(OnboardingGate)
final onboardingGateProvider = OnboardingGateProvider._();

/// Router-facing onboarding state. Signed out → [OnboardingStatus.seen] (the
/// router never forces onboarding then). Signed in → [OnboardingStatus.unknown]
/// until the account's flag loads; a flag still *reloading* after an account
/// switch counts as unknown too, so the previous account's (or the signed-out
/// placeholder's) value is never reused. After [kOnboardingFlagTimeout] (or a
/// stream error) the answer latches to seen for that account — a late "not
/// seen" then no longer yanks the user to onboarding mid-use; it shows on the
/// next start instead.
final class OnboardingGateProvider
    extends $NotifierProvider<OnboardingGate, OnboardingStatus> {
  /// Router-facing onboarding state. Signed out → [OnboardingStatus.seen] (the
  /// router never forces onboarding then). Signed in → [OnboardingStatus.unknown]
  /// until the account's flag loads; a flag still *reloading* after an account
  /// switch counts as unknown too, so the previous account's (or the signed-out
  /// placeholder's) value is never reused. After [kOnboardingFlagTimeout] (or a
  /// stream error) the answer latches to seen for that account — a late "not
  /// seen" then no longer yanks the user to onboarding mid-use; it shows on the
  /// next start instead.
  OnboardingGateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onboardingGateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onboardingGateHash();

  @$internal
  @override
  OnboardingGate create() => OnboardingGate();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OnboardingStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OnboardingStatus>(value),
    );
  }
}

String _$onboardingGateHash() => r'e132f1e9d4ceae8cf7d01843ef1ea7001cbda027';

/// Router-facing onboarding state. Signed out → [OnboardingStatus.seen] (the
/// router never forces onboarding then). Signed in → [OnboardingStatus.unknown]
/// until the account's flag loads; a flag still *reloading* after an account
/// switch counts as unknown too, so the previous account's (or the signed-out
/// placeholder's) value is never reused. After [kOnboardingFlagTimeout] (or a
/// stream error) the answer latches to seen for that account — a late "not
/// seen" then no longer yanks the user to onboarding mid-use; it shows on the
/// next start instead.

abstract class _$OnboardingGate extends $Notifier<OnboardingStatus> {
  OnboardingStatus build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<OnboardingStatus, OnboardingStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<OnboardingStatus, OnboardingStatus>,
              OnboardingStatus,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(OnboardingController)
final onboardingControllerProvider = OnboardingControllerProvider._();

final class OnboardingControllerProvider
    extends $NotifierProvider<OnboardingController, void> {
  OnboardingControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onboardingControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onboardingControllerHash();

  @$internal
  @override
  OnboardingController create() => OnboardingController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$onboardingControllerHash() =>
    r'0220c81376480ed6b70cd002e1d7bf259e169867';

abstract class _$OnboardingController extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
