// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ledgerGroups)
final ledgerGroupsProvider = LedgerGroupsProvider._();

final class LedgerGroupsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<GroupModel>>,
          List<GroupModel>,
          Stream<List<GroupModel>>
        >
    with $FutureModifier<List<GroupModel>>, $StreamProvider<List<GroupModel>> {
  LedgerGroupsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ledgerGroupsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ledgerGroupsHash();

  @$internal
  @override
  $StreamProviderElement<List<GroupModel>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<GroupModel>> create(Ref ref) {
    return ledgerGroups(ref);
  }
}

String _$ledgerGroupsHash() => r'c3aed9224eebc302f4f51720d4bb662853a9e3f4';

@ProviderFor(GroupCreator)
final groupCreatorProvider = GroupCreatorProvider._();

final class GroupCreatorProvider
    extends $NotifierProvider<GroupCreator, AsyncValue<void>> {
  GroupCreatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'groupCreatorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$groupCreatorHash();

  @$internal
  @override
  GroupCreator create() => GroupCreator();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<void> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<void>>(value),
    );
  }
}

String _$groupCreatorHash() => r'2e633643f0cbd5df318e5cc0ca64caae25157863';

abstract class _$GroupCreator extends $Notifier<AsyncValue<void>> {
  AsyncValue<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, AsyncValue<void>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, AsyncValue<void>>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
