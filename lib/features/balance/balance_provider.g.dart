// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'balance_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// G73: [roomId]'s fixed exchange rates (null = none / group unknown).

@ProviderFor(groupExchangeRates)
final groupExchangeRatesProvider = GroupExchangeRatesFamily._();

/// G73: [roomId]'s fixed exchange rates (null = none / group unknown).

final class GroupExchangeRatesProvider
    extends $FunctionalProvider<ExchangeRates?, ExchangeRates?, ExchangeRates?>
    with $Provider<ExchangeRates?> {
  /// G73: [roomId]'s fixed exchange rates (null = none / group unknown).
  GroupExchangeRatesProvider._({
    required GroupExchangeRatesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'groupExchangeRatesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$groupExchangeRatesHash();

  @override
  String toString() {
    return r'groupExchangeRatesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ExchangeRates?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ExchangeRates? create(Ref ref) {
    final argument = this.argument as String;
    return groupExchangeRates(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExchangeRates? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExchangeRates?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GroupExchangeRatesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$groupExchangeRatesHash() =>
    r'0e4ce60e1020f726ae68ffb49ec377c9df3bb25d';

/// G73: [roomId]'s fixed exchange rates (null = none / group unknown).

final class GroupExchangeRatesFamily extends $Family
    with $FunctionalFamilyOverride<ExchangeRates?, String> {
  GroupExchangeRatesFamily._()
    : super(
        retry: null,
        name: r'groupExchangeRatesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// G73: [roomId]'s fixed exchange rates (null = none / group unknown).

  GroupExchangeRatesProvider call(String roomId) =>
      GroupExchangeRatesProvider._(argument: roomId, from: this);

  @override
  String toString() => r'groupExchangeRatesProvider';
}

/// G73: [roomId]'s expenses + payments as the balances see them — converted
/// into the base currency while "settle up in {base}" is on
/// ([ledgerForSettling]), else as stored.

@ProviderFor(settlingLedger)
final settlingLedgerProvider = SettlingLedgerFamily._();

/// G73: [roomId]'s expenses + payments as the balances see them — converted
/// into the base currency while "settle up in {base}" is on
/// ([ledgerForSettling]), else as stored.

final class SettlingLedgerProvider
    extends
        $FunctionalProvider<
          ({List<ExpenseModel> expenses, List<SettlementModel> settlements}),
          ({List<ExpenseModel> expenses, List<SettlementModel> settlements}),
          ({List<ExpenseModel> expenses, List<SettlementModel> settlements})
        >
    with
        $Provider<
          ({List<ExpenseModel> expenses, List<SettlementModel> settlements})
        > {
  /// G73: [roomId]'s expenses + payments as the balances see them — converted
  /// into the base currency while "settle up in {base}" is on
  /// ([ledgerForSettling]), else as stored.
  SettlingLedgerProvider._({
    required SettlingLedgerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'settlingLedgerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$settlingLedgerHash();

  @override
  String toString() {
    return r'settlingLedgerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<
    ({List<ExpenseModel> expenses, List<SettlementModel> settlements})
  >
  $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  ({List<ExpenseModel> expenses, List<SettlementModel> settlements}) create(
    Ref ref,
  ) {
    final argument = this.argument as String;
    return settlingLedger(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    ({List<ExpenseModel> expenses, List<SettlementModel> settlements}) value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<
            ({List<ExpenseModel> expenses, List<SettlementModel> settlements})
          >(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SettlingLedgerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$settlingLedgerHash() => r'd7c6c795198c3197f31fc9f70d5dfba05e9a53cd';

/// G73: [roomId]'s expenses + payments as the balances see them — converted
/// into the base currency while "settle up in {base}" is on
/// ([ledgerForSettling]), else as stored.

final class SettlingLedgerFamily extends $Family
    with
        $FunctionalFamilyOverride<
          ({List<ExpenseModel> expenses, List<SettlementModel> settlements}),
          String
        > {
  SettlingLedgerFamily._()
    : super(
        retry: null,
        name: r'settlingLedgerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// G73: [roomId]'s expenses + payments as the balances see them — converted
  /// into the base currency while "settle up in {base}" is on
  /// ([ledgerForSettling]), else as stored.

  SettlingLedgerProvider call(String roomId) =>
      SettlingLedgerProvider._(argument: roomId, from: this);

  @override
  String toString() => r'settlingLedgerProvider';
}

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

String _$balanceForRoomHash() => r'9f7f4b37b56685f6fc63488e63a5aedda50d3915';

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
