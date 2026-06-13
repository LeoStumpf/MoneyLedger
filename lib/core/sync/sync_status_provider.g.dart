// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_status_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(peerSyncStates)
final peerSyncStatesProvider = PeerSyncStatesFamily._();

final class PeerSyncStatesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<PeerSyncStateModel>>,
          List<PeerSyncStateModel>,
          Stream<List<PeerSyncStateModel>>
        >
    with
        $FutureModifier<List<PeerSyncStateModel>>,
        $StreamProvider<List<PeerSyncStateModel>> {
  PeerSyncStatesProvider._({
    required PeerSyncStatesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'peerSyncStatesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$peerSyncStatesHash();

  @override
  String toString() {
    return r'peerSyncStatesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<PeerSyncStateModel>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<PeerSyncStateModel>> create(Ref ref) {
    final argument = this.argument as String;
    return peerSyncStates(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PeerSyncStatesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$peerSyncStatesHash() => r'4477db41756df52087f3449bc58fc7ffe3ddce50';

final class PeerSyncStatesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<PeerSyncStateModel>>, String> {
  PeerSyncStatesFamily._()
    : super(
        retry: null,
        name: r'peerSyncStatesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PeerSyncStatesProvider call(String groupId) =>
      PeerSyncStatesProvider._(argument: groupId, from: this);

  @override
  String toString() => r'peerSyncStatesProvider';
}

@ProviderFor(allExpensesForGroup)
final allExpensesForGroupProvider = AllExpensesForGroupFamily._();

final class AllExpensesForGroupProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ExpenseModel>>,
          List<ExpenseModel>,
          Stream<List<ExpenseModel>>
        >
    with
        $FutureModifier<List<ExpenseModel>>,
        $StreamProvider<List<ExpenseModel>> {
  AllExpensesForGroupProvider._({
    required AllExpensesForGroupFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'allExpensesForGroupProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$allExpensesForGroupHash();

  @override
  String toString() {
    return r'allExpensesForGroupProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<ExpenseModel>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ExpenseModel>> create(Ref ref) {
    final argument = this.argument as String;
    return allExpensesForGroup(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AllExpensesForGroupProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$allExpensesForGroupHash() =>
    r'43a3e66605b0bdbce5fe4788dbbf50660e06f4f0';

final class AllExpensesForGroupFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<ExpenseModel>>, String> {
  AllExpensesForGroupFamily._()
    : super(
        retry: null,
        name: r'allExpensesForGroupProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AllExpensesForGroupProvider call(String groupId) =>
      AllExpensesForGroupProvider._(argument: groupId, from: this);

  @override
  String toString() => r'allExpensesForGroupProvider';
}

@ProviderFor(allSettlementsForGroup)
final allSettlementsForGroupProvider = AllSettlementsForGroupFamily._();

final class AllSettlementsForGroupProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SettlementModel>>,
          List<SettlementModel>,
          Stream<List<SettlementModel>>
        >
    with
        $FutureModifier<List<SettlementModel>>,
        $StreamProvider<List<SettlementModel>> {
  AllSettlementsForGroupProvider._({
    required AllSettlementsForGroupFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'allSettlementsForGroupProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$allSettlementsForGroupHash();

  @override
  String toString() {
    return r'allSettlementsForGroupProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<SettlementModel>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<SettlementModel>> create(Ref ref) {
    final argument = this.argument as String;
    return allSettlementsForGroup(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AllSettlementsForGroupProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$allSettlementsForGroupHash() =>
    r'7c1465e5c60716271804dc97db8a02dc023408b0';

final class AllSettlementsForGroupFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<SettlementModel>>, String> {
  AllSettlementsForGroupFamily._()
    : super(
        retry: null,
        name: r'allSettlementsForGroupProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AllSettlementsForGroupProvider call(String groupId) =>
      AllSettlementsForGroupProvider._(argument: groupId, from: this);

  @override
  String toString() => r'allSettlementsForGroupProvider';
}

/// Reactive sync status for one group: recomputes whenever members, peer sync
/// state, or any record (including tombstones) changes.

@ProviderFor(groupSyncStatus)
final groupSyncStatusProvider = GroupSyncStatusFamily._();

/// Reactive sync status for one group: recomputes whenever members, peer sync
/// state, or any record (including tombstones) changes.

final class GroupSyncStatusProvider
    extends
        $FunctionalProvider<GroupSyncStatus, GroupSyncStatus, GroupSyncStatus>
    with $Provider<GroupSyncStatus> {
  /// Reactive sync status for one group: recomputes whenever members, peer sync
  /// state, or any record (including tombstones) changes.
  GroupSyncStatusProvider._({
    required GroupSyncStatusFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'groupSyncStatusProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$groupSyncStatusHash();

  @override
  String toString() {
    return r'groupSyncStatusProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<GroupSyncStatus> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GroupSyncStatus create(Ref ref) {
    final argument = this.argument as String;
    return groupSyncStatus(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GroupSyncStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GroupSyncStatus>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GroupSyncStatusProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$groupSyncStatusHash() => r'6e93b90b288dd1a35dd63460d034ffb1e63fccae';

/// Reactive sync status for one group: recomputes whenever members, peer sync
/// state, or any record (including tombstones) changes.

final class GroupSyncStatusFamily extends $Family
    with $FunctionalFamilyOverride<GroupSyncStatus, String> {
  GroupSyncStatusFamily._()
    : super(
        retry: null,
        name: r'groupSyncStatusProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Reactive sync status for one group: recomputes whenever members, peer sync
  /// state, or any record (including tombstones) changes.

  GroupSyncStatusProvider call(String groupId) =>
      GroupSyncStatusProvider._(argument: groupId, from: this);

  @override
  String toString() => r'groupSyncStatusProvider';
}
