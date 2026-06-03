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

@ProviderFor(pendingInvites)
final pendingInvitesProvider = PendingInvitesProvider._();

final class PendingInvitesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TransportRoom>>,
          List<TransportRoom>,
          Stream<List<TransportRoom>>
        >
    with
        $FutureModifier<List<TransportRoom>>,
        $StreamProvider<List<TransportRoom>> {
  PendingInvitesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingInvitesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingInvitesHash();

  @$internal
  @override
  $StreamProviderElement<List<TransportRoom>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<TransportRoom>> create(Ref ref) {
    return pendingInvites(ref);
  }
}

String _$pendingInvitesHash() => r'ddf1dc6717b1f20f8a2e201bab4ba29d68d475ff';

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

String _$groupCreatorHash() => r'7eae316675e7874c19d9cc050085de49cc1d9452';

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

@ProviderFor(UserInviter)
final userInviterProvider = UserInviterProvider._();

final class UserInviterProvider
    extends $NotifierProvider<UserInviter, AsyncValue<void>> {
  UserInviterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userInviterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userInviterHash();

  @$internal
  @override
  UserInviter create() => UserInviter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<void> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<void>>(value),
    );
  }
}

String _$userInviterHash() => r'528fc5f5fdab6ef76df8b618803c7cbba5394ab2';

abstract class _$UserInviter extends $Notifier<AsyncValue<void>> {
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

String _$memberRemoverHash() => r'351792e409c8d3d21a29cecb1ded7eb6def2c09f';

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

@ProviderFor(InviteAcceptor)
final inviteAcceptorProvider = InviteAcceptorProvider._();

final class InviteAcceptorProvider
    extends $NotifierProvider<InviteAcceptor, AsyncValue<void>> {
  InviteAcceptorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inviteAcceptorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inviteAcceptorHash();

  @$internal
  @override
  InviteAcceptor create() => InviteAcceptor();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<void> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<void>>(value),
    );
  }
}

String _$inviteAcceptorHash() => r'6aee5133565081700db5e0f13f6fba6a1ff54b12';

abstract class _$InviteAcceptor extends $Notifier<AsyncValue<void>> {
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
