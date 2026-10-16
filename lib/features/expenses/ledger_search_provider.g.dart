// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ledger_search_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// G16: the expense list's search / filter state for one group — null while
/// the search bar is closed (everything shown). Auto-disposed with the
/// group page, so leaving the group resets it.

@ProviderFor(LedgerSearch)
final ledgerSearchProvider = LedgerSearchFamily._();

/// G16: the expense list's search / filter state for one group — null while
/// the search bar is closed (everything shown). Auto-disposed with the
/// group page, so leaving the group resets it.
final class LedgerSearchProvider
    extends $NotifierProvider<LedgerSearch, LedgerFilter?> {
  /// G16: the expense list's search / filter state for one group — null while
  /// the search bar is closed (everything shown). Auto-disposed with the
  /// group page, so leaving the group resets it.
  LedgerSearchProvider._({
    required LedgerSearchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'ledgerSearchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$ledgerSearchHash();

  @override
  String toString() {
    return r'ledgerSearchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  LedgerSearch create() => LedgerSearch();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LedgerFilter? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LedgerFilter?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LedgerSearchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ledgerSearchHash() => r'b0febec91e08e67fb19a2a1fa1658d09f710c3cf';

/// G16: the expense list's search / filter state for one group — null while
/// the search bar is closed (everything shown). Auto-disposed with the
/// group page, so leaving the group resets it.

final class LedgerSearchFamily extends $Family
    with
        $ClassFamilyOverride<
          LedgerSearch,
          LedgerFilter?,
          LedgerFilter?,
          LedgerFilter?,
          String
        > {
  LedgerSearchFamily._()
    : super(
        retry: null,
        name: r'ledgerSearchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// G16: the expense list's search / filter state for one group — null while
  /// the search bar is closed (everything shown). Auto-disposed with the
  /// group page, so leaving the group resets it.

  LedgerSearchProvider call(String roomId) =>
      LedgerSearchProvider._(argument: roomId, from: this);

  @override
  String toString() => r'ledgerSearchProvider';
}

/// G16: the expense list's search / filter state for one group — null while
/// the search bar is closed (everything shown). Auto-disposed with the
/// group page, so leaving the group resets it.

abstract class _$LedgerSearch extends $Notifier<LedgerFilter?> {
  late final _$args = ref.$arg as String;
  String get roomId => _$args;

  LedgerFilter? build(String roomId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LedgerFilter?, LedgerFilter?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LedgerFilter?, LedgerFilter?>,
              LedgerFilter?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
