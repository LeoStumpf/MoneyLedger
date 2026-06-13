// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expenses_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(appDatabase)
final appDatabaseProvider = AppDatabaseProvider._();

final class AppDatabaseProvider
    extends $FunctionalProvider<AppDatabase, AppDatabase, AppDatabase>
    with $Provider<AppDatabase> {
  AppDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDatabaseHash();

  @$internal
  @override
  $ProviderElement<AppDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppDatabase create(Ref ref) {
    return appDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppDatabase>(value),
    );
  }
}

String _$appDatabaseHash() => r'98a09c6cfd43966155dfbdb0787fa18c85438e13';

@ProviderFor(expensesDao)
final expensesDaoProvider = ExpensesDaoProvider._();

final class ExpensesDaoProvider
    extends $FunctionalProvider<ExpensesDao, ExpensesDao, ExpensesDao>
    with $Provider<ExpensesDao> {
  ExpensesDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'expensesDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$expensesDaoHash();

  @$internal
  @override
  $ProviderElement<ExpensesDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ExpensesDao create(Ref ref) {
    return expensesDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExpensesDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExpensesDao>(value),
    );
  }
}

String _$expensesDaoHash() => r'e904d40571ecec6dceb1db4278727ca3d5010428';

@ProviderFor(groupsDao)
final groupsDaoProvider = GroupsDaoProvider._();

final class GroupsDaoProvider
    extends $FunctionalProvider<GroupsDao, GroupsDao, GroupsDao>
    with $Provider<GroupsDao> {
  GroupsDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'groupsDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$groupsDaoHash();

  @$internal
  @override
  $ProviderElement<GroupsDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GroupsDao create(Ref ref) {
    return groupsDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GroupsDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GroupsDao>(value),
    );
  }
}

String _$groupsDaoHash() => r'6cb0afbf2815a1a69a2a8720065d500d0b720576';

@ProviderFor(membersDao)
final membersDaoProvider = MembersDaoProvider._();

final class MembersDaoProvider
    extends $FunctionalProvider<MembersDao, MembersDao, MembersDao>
    with $Provider<MembersDao> {
  MembersDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'membersDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$membersDaoHash();

  @$internal
  @override
  $ProviderElement<MembersDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MembersDao create(Ref ref) {
    return membersDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MembersDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MembersDao>(value),
    );
  }
}

String _$membersDaoHash() => r'd9a0cb328ed0e80f8566beffc6b14eb0602dcb9b';

@ProviderFor(syncStatesDao)
final syncStatesDaoProvider = SyncStatesDaoProvider._();

final class SyncStatesDaoProvider
    extends $FunctionalProvider<SyncStatesDao, SyncStatesDao, SyncStatesDao>
    with $Provider<SyncStatesDao> {
  SyncStatesDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncStatesDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncStatesDaoHash();

  @$internal
  @override
  $ProviderElement<SyncStatesDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SyncStatesDao create(Ref ref) {
    return syncStatesDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncStatesDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncStatesDao>(value),
    );
  }
}

String _$syncStatesDaoHash() => r'28c17ae2a2fdd6539777368352415b31e31c6d7e';

@ProviderFor(expensesForRoom)
final expensesForRoomProvider = ExpensesForRoomFamily._();

final class ExpensesForRoomProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ExpenseModel>>,
          List<ExpenseModel>,
          Stream<List<ExpenseModel>>
        >
    with
        $FutureModifier<List<ExpenseModel>>,
        $StreamProvider<List<ExpenseModel>> {
  ExpensesForRoomProvider._({
    required ExpensesForRoomFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'expensesForRoomProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$expensesForRoomHash();

  @override
  String toString() {
    return r'expensesForRoomProvider'
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
    return expensesForRoom(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ExpensesForRoomProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$expensesForRoomHash() => r'b7be9889172af98952f0cff60bc07f7dd3500285';

final class ExpensesForRoomFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<ExpenseModel>>, String> {
  ExpensesForRoomFamily._()
    : super(
        retry: null,
        name: r'expensesForRoomProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ExpensesForRoomProvider call(String roomId) =>
      ExpensesForRoomProvider._(argument: roomId, from: this);

  @override
  String toString() => r'expensesForRoomProvider';
}

@ProviderFor(settlementsForRoom)
final settlementsForRoomProvider = SettlementsForRoomFamily._();

final class SettlementsForRoomProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SettlementModel>>,
          List<SettlementModel>,
          Stream<List<SettlementModel>>
        >
    with
        $FutureModifier<List<SettlementModel>>,
        $StreamProvider<List<SettlementModel>> {
  SettlementsForRoomProvider._({
    required SettlementsForRoomFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'settlementsForRoomProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$settlementsForRoomHash();

  @override
  String toString() {
    return r'settlementsForRoomProvider'
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
    return settlementsForRoom(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SettlementsForRoomProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$settlementsForRoomHash() =>
    r'7442b5902aff6663367aeb6f21714be0af61c14b';

final class SettlementsForRoomFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<SettlementModel>>, String> {
  SettlementsForRoomFamily._()
    : super(
        retry: null,
        name: r'settlementsForRoomProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SettlementsForRoomProvider call(String roomId) =>
      SettlementsForRoomProvider._(argument: roomId, from: this);

  @override
  String toString() => r'settlementsForRoomProvider';
}

@ProviderFor(ExpenseAdder)
final expenseAdderProvider = ExpenseAdderProvider._();

final class ExpenseAdderProvider
    extends $AsyncNotifierProvider<ExpenseAdder, void> {
  ExpenseAdderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'expenseAdderProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$expenseAdderHash();

  @$internal
  @override
  ExpenseAdder create() => ExpenseAdder();
}

String _$expenseAdderHash() => r'35ba87c038dac7bbe6ecd5251798d209c02d7e1c';

abstract class _$ExpenseAdder extends $AsyncNotifier<void> {
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
