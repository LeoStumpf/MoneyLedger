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

/// The participant in [groupId] that this device's account has claimed, if any
/// — i.e. "who am I in this group". Its `userId` is the participant id to use
/// as `paid_by` / split key for the current user (equals the MXID for a
/// from-scratch user, a UUID once they've claimed a pre-existing local slot).
///
/// Re-evaluated whenever the group's members change (G26), so e.g. being
/// removed by another member is reflected live (read-only group, banner).
///
/// G52 (§6.1): with no participant claimed by this account (MXID or
/// `local:self`), a **link group**'s "me" is this device's
/// `link_channels.my_participant_id` — when that participant is active.
/// (Read once per members change; the join flow sets it together with the
/// participant.)

@ProviderFor(currentParticipant)
final currentParticipantProvider = CurrentParticipantFamily._();

/// The participant in [groupId] that this device's account has claimed, if any
/// — i.e. "who am I in this group". Its `userId` is the participant id to use
/// as `paid_by` / split key for the current user (equals the MXID for a
/// from-scratch user, a UUID once they've claimed a pre-existing local slot).
///
/// Re-evaluated whenever the group's members change (G26), so e.g. being
/// removed by another member is reflected live (read-only group, banner).
///
/// G52 (§6.1): with no participant claimed by this account (MXID or
/// `local:self`), a **link group**'s "me" is this device's
/// `link_channels.my_participant_id` — when that participant is active.
/// (Read once per members change; the join flow sets it together with the
/// participant.)

final class CurrentParticipantProvider
    extends
        $FunctionalProvider<
          AsyncValue<MemberModel?>,
          MemberModel?,
          FutureOr<MemberModel?>
        >
    with $FutureModifier<MemberModel?>, $FutureProvider<MemberModel?> {
  /// The participant in [groupId] that this device's account has claimed, if any
  /// — i.e. "who am I in this group". Its `userId` is the participant id to use
  /// as `paid_by` / split key for the current user (equals the MXID for a
  /// from-scratch user, a UUID once they've claimed a pre-existing local slot).
  ///
  /// Re-evaluated whenever the group's members change (G26), so e.g. being
  /// removed by another member is reflected live (read-only group, banner).
  ///
  /// G52 (§6.1): with no participant claimed by this account (MXID or
  /// `local:self`), a **link group**'s "me" is this device's
  /// `link_channels.my_participant_id` — when that participant is active.
  /// (Read once per members change; the join flow sets it together with the
  /// participant.)
  CurrentParticipantProvider._({
    required CurrentParticipantFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'currentParticipantProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$currentParticipantHash();

  @override
  String toString() {
    return r'currentParticipantProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MemberModel?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MemberModel?> create(Ref ref) {
    final argument = this.argument as String;
    return currentParticipant(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CurrentParticipantProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$currentParticipantHash() =>
    r'f0a5d1ed2a184eafad3857b6753e5b8936ea6237';

/// The participant in [groupId] that this device's account has claimed, if any
/// — i.e. "who am I in this group". Its `userId` is the participant id to use
/// as `paid_by` / split key for the current user (equals the MXID for a
/// from-scratch user, a UUID once they've claimed a pre-existing local slot).
///
/// Re-evaluated whenever the group's members change (G26), so e.g. being
/// removed by another member is reflected live (read-only group, banner).
///
/// G52 (§6.1): with no participant claimed by this account (MXID or
/// `local:self`), a **link group**'s "me" is this device's
/// `link_channels.my_participant_id` — when that participant is active.
/// (Read once per members change; the join flow sets it together with the
/// participant.)

final class CurrentParticipantFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<MemberModel?>, String> {
  CurrentParticipantFamily._()
    : super(
        retry: null,
        name: r'currentParticipantProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The participant in [groupId] that this device's account has claimed, if any
  /// — i.e. "who am I in this group". Its `userId` is the participant id to use
  /// as `paid_by` / split key for the current user (equals the MXID for a
  /// from-scratch user, a UUID once they've claimed a pre-existing local slot).
  ///
  /// Re-evaluated whenever the group's members change (G26), so e.g. being
  /// removed by another member is reflected live (read-only group, banner).
  ///
  /// G52 (§6.1): with no participant claimed by this account (MXID or
  /// `local:self`), a **link group**'s "me" is this device's
  /// `link_channels.my_participant_id` — when that participant is active.
  /// (Read once per members change; the join flow sets it together with the
  /// participant.)

  CurrentParticipantProvider call(String groupId) =>
      CurrentParticipantProvider._(argument: groupId, from: this);

  @override
  String toString() => r'currentParticipantProvider';
}

/// participant id → display label for [groupId]. Falls back to the Matrix
/// id's localpart (or the raw participant id, [MemberModel.label]) when a participant has no name yet, so the UI
/// never shows a blank. Watches the members stream, so renames/claims reflect
/// live.

@ProviderFor(participantNames)
final participantNamesProvider = ParticipantNamesFamily._();

/// participant id → display label for [groupId]. Falls back to the Matrix
/// id's localpart (or the raw participant id, [MemberModel.label]) when a participant has no name yet, so the UI
/// never shows a blank. Watches the members stream, so renames/claims reflect
/// live.

final class ParticipantNamesProvider
    extends
        $FunctionalProvider<
          Map<String, String>,
          Map<String, String>,
          Map<String, String>
        >
    with $Provider<Map<String, String>> {
  /// participant id → display label for [groupId]. Falls back to the Matrix
  /// id's localpart (or the raw participant id, [MemberModel.label]) when a participant has no name yet, so the UI
  /// never shows a blank. Watches the members stream, so renames/claims reflect
  /// live.
  ParticipantNamesProvider._({
    required ParticipantNamesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'participantNamesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$participantNamesHash();

  @override
  String toString() {
    return r'participantNamesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<Map<String, String>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, String> create(Ref ref) {
    final argument = this.argument as String;
    return participantNames(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, String>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ParticipantNamesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$participantNamesHash() => r'228ff448c3330ca6b6e43a508c2e8cc987523d55';

/// participant id → display label for [groupId]. Falls back to the Matrix
/// id's localpart (or the raw participant id, [MemberModel.label]) when a participant has no name yet, so the UI
/// never shows a blank. Watches the members stream, so renames/claims reflect
/// live.

final class ParticipantNamesFamily extends $Family
    with $FunctionalFamilyOverride<Map<String, String>, String> {
  ParticipantNamesFamily._()
    : super(
        retry: null,
        name: r'participantNamesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// participant id → display label for [groupId]. Falls back to the Matrix
  /// id's localpart (or the raw participant id, [MemberModel.label]) when a participant has no name yet, so the UI
  /// never shows a blank. Watches the members stream, so renames/claims reflect
  /// live.

  ParticipantNamesProvider call(String groupId) =>
      ParticipantNamesProvider._(argument: groupId, from: this);

  @override
  String toString() => r'participantNamesProvider';
}

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

String _$groupCreatorHash() => r'9c7e1a3c38b87a48eebeb6049cb3a6fbadc12e42';

abstract class _$GroupCreator extends $Notifier<AsyncValue<void>> {
  AsyncValue<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, AsyncValue<void>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, AsyncValue<void>>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
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

String _$memberAdderHash() => r'94e83b92f66e5e230d373876c6a8a0825f106bc6';

abstract class _$MemberAdder extends $Notifier<AsyncValue<void>> {
  AsyncValue<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, AsyncValue<void>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, AsyncValue<void>>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
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

String _$memberRemoverHash() => r'9463ec01bd00fe71c889c2bf610534da5d688478';

abstract class _$MemberRemover extends $Notifier<AsyncValue<void>> {
  AsyncValue<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, AsyncValue<void>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, AsyncValue<void>>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// One-off name upgrade (G17): participants whose stored name is just their
/// account's MXID localpart — the default before profile names were fetched —
/// are renamed to that account's Matrix profile display name, if it has a
/// different one. Runs once per signed-in account (keepAlive; rebuilt on an
/// account switch with the DB), only in groups where this account is an
/// active participant (others would reject our edits), and only for active
/// claimed participants. Each rename is an ordinary LWW edit relayed to the
/// group like a manual rename. Returns the number of renamed participants.
///
/// G19: everything is captured before the first await; it bails silently
/// once the DB closed (account switch / sign-out).

@ProviderFor(profileNameRefresh)
final profileNameRefreshProvider = ProfileNameRefreshProvider._();

/// One-off name upgrade (G17): participants whose stored name is just their
/// account's MXID localpart — the default before profile names were fetched —
/// are renamed to that account's Matrix profile display name, if it has a
/// different one. Runs once per signed-in account (keepAlive; rebuilt on an
/// account switch with the DB), only in groups where this account is an
/// active participant (others would reject our edits), and only for active
/// claimed participants. Each rename is an ordinary LWW edit relayed to the
/// group like a manual rename. Returns the number of renamed participants.
///
/// G19: everything is captured before the first await; it bails silently
/// once the DB closed (account switch / sign-out).

final class ProfileNameRefreshProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// One-off name upgrade (G17): participants whose stored name is just their
  /// account's MXID localpart — the default before profile names were fetched —
  /// are renamed to that account's Matrix profile display name, if it has a
  /// different one. Runs once per signed-in account (keepAlive; rebuilt on an
  /// account switch with the DB), only in groups where this account is an
  /// active participant (others would reject our edits), and only for active
  /// claimed participants. Each rename is an ordinary LWW edit relayed to the
  /// group like a manual rename. Returns the number of renamed participants.
  ///
  /// G19: everything is captured before the first await; it bails silently
  /// once the DB closed (account switch / sign-out).
  ProfileNameRefreshProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profileNameRefreshProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profileNameRefreshHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return profileNameRefresh(ref);
  }
}

String _$profileNameRefreshHash() =>
    r'9a75a3ca6420067adb65459aeeea2ef54e6dd872';

/// Leave / delete a group (G9). Both end with the group **purged** from the
/// local DB and a device-local [LeftGroupTombstone], so a late digest or
/// bootstrap from a peer (or our own other devices) can't resurrect it — only
/// being re-added (a newer `active` member record for our MXID) brings it back.

@ProviderFor(GroupExiter)
final groupExiterProvider = GroupExiterProvider._();

/// Leave / delete a group (G9). Both end with the group **purged** from the
/// local DB and a device-local [LeftGroupTombstone], so a late digest or
/// bootstrap from a peer (or our own other devices) can't resurrect it — only
/// being re-added (a newer `active` member record for our MXID) brings it back.
final class GroupExiterProvider
    extends $NotifierProvider<GroupExiter, AsyncValue<void>> {
  /// Leave / delete a group (G9). Both end with the group **purged** from the
  /// local DB and a device-local [LeftGroupTombstone], so a late digest or
  /// bootstrap from a peer (or our own other devices) can't resurrect it — only
  /// being re-added (a newer `active` member record for our MXID) brings it back.
  GroupExiterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'groupExiterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$groupExiterHash();

  @$internal
  @override
  GroupExiter create() => GroupExiter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<void> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<void>>(value),
    );
  }
}

String _$groupExiterHash() => r'f455229463bb9da736959b442c69aa4fb7a4152e';

/// Leave / delete a group (G9). Both end with the group **purged** from the
/// local DB and a device-local [LeftGroupTombstone], so a late digest or
/// bootstrap from a peer (or our own other devices) can't resurrect it — only
/// being re-added (a newer `active` member record for our MXID) brings it back.

abstract class _$GroupExiter extends $Notifier<AsyncValue<void>> {
  AsyncValue<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, AsyncValue<void>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, AsyncValue<void>>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Edits a group's meta — name and default currency (G10). Any active member
/// may edit. Persisted as an LWW meta upsert with a fresh clock and relayed
/// as a `group` meta payload to the active claimed members (anti-entropy's
/// `meta_updated_at` repairs a lost relay). The default currency only applies
/// to **new** expenses — existing ones keep theirs (balances are per currency).

@ProviderFor(GroupEditor)
final groupEditorProvider = GroupEditorProvider._();

/// Edits a group's meta — name and default currency (G10). Any active member
/// may edit. Persisted as an LWW meta upsert with a fresh clock and relayed
/// as a `group` meta payload to the active claimed members (anti-entropy's
/// `meta_updated_at` repairs a lost relay). The default currency only applies
/// to **new** expenses — existing ones keep theirs (balances are per currency).
final class GroupEditorProvider
    extends $NotifierProvider<GroupEditor, AsyncValue<void>> {
  /// Edits a group's meta — name and default currency (G10). Any active member
  /// may edit. Persisted as an LWW meta upsert with a fresh clock and relayed
  /// as a `group` meta payload to the active claimed members (anti-entropy's
  /// `meta_updated_at` repairs a lost relay). The default currency only applies
  /// to **new** expenses — existing ones keep theirs (balances are per currency).
  GroupEditorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'groupEditorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$groupEditorHash();

  @$internal
  @override
  GroupEditor create() => GroupEditor();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<void> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<void>>(value),
    );
  }
}

String _$groupEditorHash() => r'448503f65b4ce567a04c048e036ca1760464e209';

/// Edits a group's meta — name and default currency (G10). Any active member
/// may edit. Persisted as an LWW meta upsert with a fresh clock and relayed
/// as a `group` meta payload to the active claimed members (anti-entropy's
/// `meta_updated_at` repairs a lost relay). The default currency only applies
/// to **new** expenses — existing ones keep theirs (balances are per currency).

abstract class _$GroupEditor extends $Notifier<AsyncValue<void>> {
  AsyncValue<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, AsyncValue<void>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, AsyncValue<void>>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
