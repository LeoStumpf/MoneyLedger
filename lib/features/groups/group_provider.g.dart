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

@ProviderFor(groupMembers)
final groupMembersProvider = GroupMembersFamily._();

final class GroupMembersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<MemberModel>>,
          List<MemberModel>,
          Stream<List<MemberModel>>
        >
    with
        $FutureModifier<List<MemberModel>>,
        $StreamProvider<List<MemberModel>> {
  GroupMembersProvider._({
    required GroupMembersFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'groupMembersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$groupMembersHash();

  @override
  String toString() {
    return r'groupMembersProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<MemberModel>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<MemberModel>> create(Ref ref) {
    final argument = this.argument as String;
    return groupMembers(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GroupMembersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$groupMembersHash() => r'3cb151491b4278fb65d2e7d8bab18ac46d619f57';

final class GroupMembersFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<MemberModel>>, String> {
  GroupMembersFamily._()
    : super(
        retry: null,
        name: r'groupMembersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  GroupMembersProvider call(String groupId) =>
      GroupMembersProvider._(argument: groupId, from: this);

  @override
  String toString() => r'groupMembersProvider';
}

/// This device's own Matrix ID (empty until the transport/client is ready).

@ProviderFor(currentUserId)
final currentUserIdProvider = CurrentUserIdProvider._();

/// This device's own Matrix ID (empty until the transport/client is ready).

final class CurrentUserIdProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// This device's own Matrix ID (empty until the transport/client is ready).
  CurrentUserIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentUserIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentUserIdHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return currentUserId(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$currentUserIdHash() => r'76f65c8883f46092cc228dc1ff6c8a26b9366446';

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

String _$groupCreatorHash() => r'd9c6cfdeef4551bc01fe25dedd59d9a0b310d09f';

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

@ProviderFor(MemberAdder)
final memberAdderProvider = MemberAdderProvider._();

final class MemberAdderProvider
    extends $NotifierProvider<MemberAdder, AsyncValue<void>> {
  MemberAdderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'memberAdderProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$memberAdderHash();

  @$internal
  @override
  MemberAdder create() => MemberAdder();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<void> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<void>>(value),
    );
  }
}

String _$memberAdderHash() => r'c67d9c5e0a0d202526078bad783555f69b323e28';

abstract class _$MemberAdder extends $Notifier<AsyncValue<void>> {
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

@ProviderFor(MemberRemover)
final memberRemoverProvider = MemberRemoverProvider._();

final class MemberRemoverProvider
    extends $NotifierProvider<MemberRemover, AsyncValue<void>> {
  MemberRemoverProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'memberRemoverProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$memberRemoverHash();

  @$internal
  @override
  MemberRemover create() => MemberRemover();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<void> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<void>>(value),
    );
  }
}

String _$memberRemoverHash() => r'9bbad059fe1f26be221d581a250cf05b7ffc5027';

abstract class _$MemberRemover extends $Notifier<AsyncValue<void>> {
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
