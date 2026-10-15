// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_health.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds [SyncHealthState] for the whole session. `keepAlive` so it survives
/// page navigation (the indicator lives in per-group app bars but the health is
/// global). The sync paths call [reportSuccess] / [reportFailure].

@ProviderFor(SyncHealth)
final syncHealthProvider = SyncHealthProvider._();

/// Holds [SyncHealthState] for the whole session. `keepAlive` so it survives
/// page navigation (the indicator lives in per-group app bars but the health is
/// global). The sync paths call [reportSuccess] / [reportFailure].
final class SyncHealthProvider
    extends $NotifierProvider<SyncHealth, SyncHealthState> {
  /// Holds [SyncHealthState] for the whole session. `keepAlive` so it survives
  /// page navigation (the indicator lives in per-group app bars but the health is
  /// global). The sync paths call [reportSuccess] / [reportFailure].
  SyncHealthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncHealthProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncHealthHash();

  @$internal
  @override
  SyncHealth create() => SyncHealth();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncHealthState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncHealthState>(value),
    );
  }
}

String _$syncHealthHash() => r'c34dbb20620ef02cb5aff9fd2c42c0c21efcacd0';

/// Holds [SyncHealthState] for the whole session. `keepAlive` so it survives
/// page navigation (the indicator lives in per-group app bars but the health is
/// global). The sync paths call [reportSuccess] / [reportFailure].

abstract class _$SyncHealth extends $Notifier<SyncHealthState> {
  SyncHealthState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SyncHealthState, SyncHealthState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SyncHealthState, SyncHealthState>,
              SyncHealthState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
