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
///
/// keepAlive (G22): the UI reads the notifier once, then awaits the file
/// picker and a preview dialog with nothing listening — an auto-disposed
/// provider was gone by then. The DAOs are read per call, so an account
/// switch in between is still honoured.

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
///
/// keepAlive (G22): the UI reads the notifier once, then awaits the file
/// picker and a preview dialog with nothing listening — an auto-disposed
/// provider was gone by then. The DAOs are read per call, so an account
/// switch in between is still honoured.
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
  ///
  /// keepAlive (G22): the UI reads the notifier once, then awaits the file
  /// picker and a preview dialog with nothing listening — an auto-disposed
  /// provider was gone by then. The DAOs are read per call, so an account
  /// switch in between is still honoured.
  CsvImporterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'csvImporterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$csvImporterHash();

  @$internal
  @override
  CsvImporter create() => CsvImporter();
}

String _$csvImporterHash() => r'7ec72c9170ed710e0e774f71a5c03b67ecf90599';

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
///
/// keepAlive (G22): the UI reads the notifier once, then awaits the file
/// picker and a preview dialog with nothing listening — an auto-disposed
/// provider was gone by then. The DAOs are read per call, so an account
/// switch in between is still honoured.

abstract class _$CsvImporter extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
