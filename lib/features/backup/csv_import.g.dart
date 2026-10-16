// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'csv_import.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Imports a per-group CSV produced by [buildGroupCsv] back into the local DB.
///
/// Merge semantics (Phase D, G13): the group is resolved by `Group ID`
/// (created if absent), participants are resolved **by display name**
/// ([resolveCsvNames] — an unknown name becomes a new local participant), and
/// each expense / payment is **LWW-upserted by id** using the row's
/// `Updated At` clock — so re-importing a backup is idempotent and merging
/// into an existing group lets the newer copy win.
///
/// G6: the CSV carries no signatures. A row that **wins** against the local
/// copy (or is new) becomes a version signed by **this device as its
/// editor** (new records also get this device as their creator, "added
/// by"); rows that don't win are skipped, never re-signed.

@ProviderFor(CsvImporter)
final csvImporterProvider = CsvImporterProvider._();

/// Imports a per-group CSV produced by [buildGroupCsv] back into the local DB.
///
/// Merge semantics (Phase D, G13): the group is resolved by `Group ID`
/// (created if absent), participants are resolved **by display name**
/// ([resolveCsvNames] — an unknown name becomes a new local participant), and
/// each expense / payment is **LWW-upserted by id** using the row's
/// `Updated At` clock — so re-importing a backup is idempotent and merging
/// into an existing group lets the newer copy win.
///
/// G6: the CSV carries no signatures. A row that **wins** against the local
/// copy (or is new) becomes a version signed by **this device as its
/// editor** (new records also get this device as their creator, "added
/// by"); rows that don't win are skipped, never re-signed.
final class CsvImporterProvider
    extends $AsyncNotifierProvider<CsvImporter, void> {
  /// Imports a per-group CSV produced by [buildGroupCsv] back into the local DB.
  ///
  /// Merge semantics (Phase D, G13): the group is resolved by `Group ID`
  /// (created if absent), participants are resolved **by display name**
  /// ([resolveCsvNames] — an unknown name becomes a new local participant), and
  /// each expense / payment is **LWW-upserted by id** using the row's
  /// `Updated At` clock — so re-importing a backup is idempotent and merging
  /// into an existing group lets the newer copy win.
  ///
  /// G6: the CSV carries no signatures. A row that **wins** against the local
  /// copy (or is new) becomes a version signed by **this device as its
  /// editor** (new records also get this device as their creator, "added
  /// by"); rows that don't win are skipped, never re-signed.
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

String _$csvImporterHash() => r'42f4b9d0905196413fc8bf4b2b436312e011f0a6';

/// Imports a per-group CSV produced by [buildGroupCsv] back into the local DB.
///
/// Merge semantics (Phase D, G13): the group is resolved by `Group ID`
/// (created if absent), participants are resolved **by display name**
/// ([resolveCsvNames] — an unknown name becomes a new local participant), and
/// each expense / payment is **LWW-upserted by id** using the row's
/// `Updated At` clock — so re-importing a backup is idempotent and merging
/// into an existing group lets the newer copy win.
///
/// G6: the CSV carries no signatures. A row that **wins** against the local
/// copy (or is new) becomes a version signed by **this device as its
/// editor** (new records also get this device as their creator, "added
/// by"); rows that don't win are skipped, never re-signed.

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
