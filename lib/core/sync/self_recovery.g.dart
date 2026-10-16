// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'self_recovery.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether this device's first-login recovery is outstanding: the account DB
/// was empty at start-up, a self `resync_request` is out, and nothing has been
/// restored yet. Drives the groups page's "Restoring your groups…" state.
///
/// Per account (reset when the ledger DB is swapped, G4). The notifier owns
/// the UI timeout, so the spinner always ends — even if the engine that
/// started it is gone.

@ProviderFor(SelfRecovery)
final selfRecoveryProvider = SelfRecoveryProvider._();

/// Whether this device's first-login recovery is outstanding: the account DB
/// was empty at start-up, a self `resync_request` is out, and nothing has been
/// restored yet. Drives the groups page's "Restoring your groups…" state.
///
/// Per account (reset when the ledger DB is swapped, G4). The notifier owns
/// the UI timeout, so the spinner always ends — even if the engine that
/// started it is gone.
final class SelfRecoveryProvider extends $NotifierProvider<SelfRecovery, bool> {
  /// Whether this device's first-login recovery is outstanding: the account DB
  /// was empty at start-up, a self `resync_request` is out, and nothing has been
  /// restored yet. Drives the groups page's "Restoring your groups…" state.
  ///
  /// Per account (reset when the ledger DB is swapped, G4). The notifier owns
  /// the UI timeout, so the spinner always ends — even if the engine that
  /// started it is gone.
  SelfRecoveryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selfRecoveryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selfRecoveryHash();

  @$internal
  @override
  SelfRecovery create() => SelfRecovery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$selfRecoveryHash() => r'aa311c8eb73ab3e6b3fa44212f1e36011cf7533c';

/// Whether this device's first-login recovery is outstanding: the account DB
/// was empty at start-up, a self `resync_request` is out, and nothing has been
/// restored yet. Drives the groups page's "Restoring your groups…" state.
///
/// Per account (reset when the ledger DB is swapped, G4). The notifier owns
/// the UI timeout, so the spinner always ends — even if the engine that
/// started it is gone.

abstract class _$SelfRecovery extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
