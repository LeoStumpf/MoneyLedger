// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'csv_import.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Imports a per-group CSV produced by [buildGroupCsv] back into the local DB.
///
/// Merge semantics (Phase D): the group is resolved by `Group ID` (created if
/// absent), participants are resolved **by display name** (an unknown name
/// becomes a new local participant), and each expense is **LWW-upserted by id**
/// using the row's `Updated At` clock — so re-importing a backup is idempotent
/// and merging into an existing group lets the newer copy win.

@ProviderFor(CsvImporter)
final csvImporterProvider = CsvImporterProvider._();

/// Imports a per-group CSV produced by [buildGroupCsv] back into the local DB.
///
/// Merge semantics (Phase D): the group is resolved by `Group ID` (created if
/// absent), participants are resolved **by display name** (an unknown name
/// becomes a new local participant), and each expense is **LWW-upserted by id**
/// using the row's `Updated At` clock — so re-importing a backup is idempotent
/// and merging into an existing group lets the newer copy win.
final class CsvImporterProvider
    extends $AsyncNotifierProvider<CsvImporter, void> {
  /// Imports a per-group CSV produced by [buildGroupCsv] back into the local DB.
  ///
  /// Merge semantics (Phase D): the group is resolved by `Group ID` (created if
  /// absent), participants are resolved **by display name** (an unknown name
  /// becomes a new local participant), and each expense is **LWW-upserted by id**
  /// using the row's `Updated At` clock — so re-importing a backup is idempotent
  /// and merging into an existing group lets the newer copy win.
  CsvImporterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'csvImporterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$csvImporterHash();

  @$internal
  @override
  CsvImporter create() => CsvImporter();
}

String _$csvImporterHash() => r'3ddc6f3eae37ae956236a0ef69773c0cae9f1361';

/// Imports a per-group CSV produced by [buildGroupCsv] back into the local DB.
///
/// Merge semantics (Phase D): the group is resolved by `Group ID` (created if
/// absent), participants are resolved **by display name** (an unknown name
/// becomes a new local participant), and each expense is **LWW-upserted by id**
/// using the row's `Updated At` clock — so re-importing a backup is idempotent
/// and merging into an existing group lets the newer copy win.

abstract class _$CsvImporter extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
