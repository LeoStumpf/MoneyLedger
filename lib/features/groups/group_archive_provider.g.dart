// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_archive_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// G16: this account's archive entries on this device, by group id.

@ProviderFor(groupArchives)
final groupArchivesProvider = GroupArchivesProvider._();

/// G16: this account's archive entries on this device, by group id.

final class GroupArchivesProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, GroupArchive>>,
          Map<String, GroupArchive>,
          Stream<Map<String, GroupArchive>>
        >
    with
        $FutureModifier<Map<String, GroupArchive>>,
        $StreamProvider<Map<String, GroupArchive>> {
  /// G16: this account's archive entries on this device, by group id.
  GroupArchivesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'groupArchivesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$groupArchivesHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, GroupArchive>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, GroupArchive>> create(Ref ref) {
    return groupArchives(ref);
  }
}

String _$groupArchivesHash() => r'5b08a5d4a414cbcb097295acd8c7a795df459b65';

/// The current [ledgerFingerprint] of [groupId] (null while loading).

@ProviderFor(groupLedgerFingerprint)
final groupLedgerFingerprintProvider = GroupLedgerFingerprintFamily._();

/// The current [ledgerFingerprint] of [groupId] (null while loading).

final class GroupLedgerFingerprintProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// The current [ledgerFingerprint] of [groupId] (null while loading).
  GroupLedgerFingerprintProvider._({
    required GroupLedgerFingerprintFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'groupLedgerFingerprintProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$groupLedgerFingerprintHash();

  @override
  String toString() {
    return r'groupLedgerFingerprintProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    final argument = this.argument as String;
    return groupLedgerFingerprint(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GroupLedgerFingerprintProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$groupLedgerFingerprintHash() =>
    r'16ed8aefee2c7bfd9fbe091f6946a68674bc93fa';

/// The current [ledgerFingerprint] of [groupId] (null while loading).

final class GroupLedgerFingerprintFamily extends $Family
    with $FunctionalFamilyOverride<String?, String> {
  GroupLedgerFingerprintFamily._()
    : super(
        retry: null,
        name: r'groupLedgerFingerprintProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The current [ledgerFingerprint] of [groupId] (null while loading).

  GroupLedgerFingerprintProvider call(String groupId) =>
      GroupLedgerFingerprintProvider._(argument: groupId, from: this);

  @override
  String toString() => r'groupLedgerFingerprintProvider';
}

/// Whether [groupId] is archived here and had no activity since (see
/// [GroupArchive]). While the ledger is still loading an archived group
/// stays archived (no flicker between the sections).

@ProviderFor(groupArchived)
final groupArchivedProvider = GroupArchivedFamily._();

/// Whether [groupId] is archived here and had no activity since (see
/// [GroupArchive]). While the ledger is still loading an archived group
/// stays archived (no flicker between the sections).

final class GroupArchivedProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether [groupId] is archived here and had no activity since (see
  /// [GroupArchive]). While the ledger is still loading an archived group
  /// stays archived (no flicker between the sections).
  GroupArchivedProvider._({
    required GroupArchivedFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'groupArchivedProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$groupArchivedHash();

  @override
  String toString() {
    return r'groupArchivedProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    final argument = this.argument as String;
    return groupArchived(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GroupArchivedProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$groupArchivedHash() => r'619b5652729f7095f734f2993a1388f8cc7ef1d5';

/// Whether [groupId] is archived here and had no activity since (see
/// [GroupArchive]). While the ledger is still loading an archived group
/// stays archived (no flicker between the sections).

final class GroupArchivedFamily extends $Family
    with $FunctionalFamilyOverride<bool, String> {
  GroupArchivedFamily._()
    : super(
        retry: null,
        name: r'groupArchivedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether [groupId] is archived here and had no activity since (see
  /// [GroupArchive]). While the ledger is still loading an archived group
  /// stays archived (no flicker between the sections).

  GroupArchivedProvider call(String groupId) =>
      GroupArchivedProvider._(argument: groupId, from: this);

  @override
  String toString() => r'groupArchivedProvider';
}

/// Archives / un-archives a group on this device (G16). Device-local: no
/// write is replicated.

@ProviderFor(GroupArchiver)
final groupArchiverProvider = GroupArchiverProvider._();

/// Archives / un-archives a group on this device (G16). Device-local: no
/// write is replicated.
final class GroupArchiverProvider
    extends $AsyncNotifierProvider<GroupArchiver, void> {
  /// Archives / un-archives a group on this device (G16). Device-local: no
  /// write is replicated.
  GroupArchiverProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'groupArchiverProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$groupArchiverHash();

  @$internal
  @override
  GroupArchiver create() => GroupArchiver();
}

String _$groupArchiverHash() => r'efeef978d44e8c6dcaf70111e001561251985971';

/// Archives / un-archives a group on this device (G16). Device-local: no
/// write is replicated.

abstract class _$GroupArchiver extends $AsyncNotifier<void> {
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
