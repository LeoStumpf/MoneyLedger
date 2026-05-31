// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'balance_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(balanceForRoom)
final balanceForRoomProvider = BalanceForRoomFamily._();

final class BalanceForRoomProvider
    extends
        $FunctionalProvider<List<DebtEntry>, List<DebtEntry>, List<DebtEntry>>
    with $Provider<List<DebtEntry>> {
  BalanceForRoomProvider._({
    required BalanceForRoomFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'balanceForRoomProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$balanceForRoomHash();

  @override
  String toString() {
    return r'balanceForRoomProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<DebtEntry>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<DebtEntry> create(Ref ref) {
    final argument = this.argument as String;
    return balanceForRoom(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<DebtEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<DebtEntry>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BalanceForRoomProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$balanceForRoomHash() => r'e3ac3ec0d6017654b79304ce2ba6568461f339c5';

final class BalanceForRoomFamily extends $Family
    with $FunctionalFamilyOverride<List<DebtEntry>, String> {
  BalanceForRoomFamily._()
    : super(
        retry: null,
        name: r'balanceForRoomProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  BalanceForRoomProvider call(String roomId) =>
      BalanceForRoomProvider._(argument: roomId, from: this);

  @override
  String toString() => r'balanceForRoomProvider';
}
