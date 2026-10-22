// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_overview_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// [GroupOverview] of [groupId], recomputed from the Drift streams.

@ProviderFor(groupOverview)
final groupOverviewProvider = GroupOverviewFamily._();

/// [GroupOverview] of [groupId], recomputed from the Drift streams.

final class GroupOverviewProvider
    extends $FunctionalProvider<GroupOverview, GroupOverview, GroupOverview>
    with $Provider<GroupOverview> {
  /// [GroupOverview] of [groupId], recomputed from the Drift streams.
  GroupOverviewProvider._({
    required GroupOverviewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'groupOverviewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$groupOverviewHash();

  @override
  String toString() {
    return r'groupOverviewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<GroupOverview> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GroupOverview create(Ref ref) {
    final argument = this.argument as String;
    return groupOverview(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GroupOverview value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GroupOverview>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GroupOverviewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$groupOverviewHash() => r'48836315088fed4230cae4df2d46e12f973afa20';

/// [GroupOverview] of [groupId], recomputed from the Drift streams.

final class GroupOverviewFamily extends $Family
    with $FunctionalFamilyOverride<GroupOverview, String> {
  GroupOverviewFamily._()
    : super(
        retry: null,
        name: r'groupOverviewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// [GroupOverview] of [groupId], recomputed from the Drift streams.

  GroupOverviewProvider call(String groupId) =>
      GroupOverviewProvider._(argument: groupId, from: this);

  @override
  String toString() => r'groupOverviewProvider';
}
