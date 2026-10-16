// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transport_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The single seam the rest of the app depends on for sync/transport. In tests
/// this is overridden with an in-memory fake (see test/helpers/fake_ledger_network.dart),
/// so multi-user / federated flows can be exercised without a real homeserver.
///
/// G40: in local mode it is a [LocalOnlyTransport] — no Matrix client is
/// built, nothing is sent or received, nothing can be signed.

@ProviderFor(ledgerTransport)
final ledgerTransportProvider = LedgerTransportProvider._();

/// The single seam the rest of the app depends on for sync/transport. In tests
/// this is overridden with an in-memory fake (see test/helpers/fake_ledger_network.dart),
/// so multi-user / federated flows can be exercised without a real homeserver.
///
/// G40: in local mode it is a [LocalOnlyTransport] — no Matrix client is
/// built, nothing is sent or received, nothing can be signed.

final class LedgerTransportProvider
    extends
        $FunctionalProvider<
          AsyncValue<LedgerTransport>,
          LedgerTransport,
          FutureOr<LedgerTransport>
        >
    with $FutureModifier<LedgerTransport>, $FutureProvider<LedgerTransport> {
  /// The single seam the rest of the app depends on for sync/transport. In tests
  /// this is overridden with an in-memory fake (see test/helpers/fake_ledger_network.dart),
  /// so multi-user / federated flows can be exercised without a real homeserver.
  ///
  /// G40: in local mode it is a [LocalOnlyTransport] — no Matrix client is
  /// built, nothing is sent or received, nothing can be signed.
  LedgerTransportProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ledgerTransportProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ledgerTransportHash();

  @$internal
  @override
  $FutureProviderElement<LedgerTransport> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<LedgerTransport> create(Ref ref) {
    return ledgerTransport(ref);
  }
}

String _$ledgerTransportHash() => r'61966de09fcb0c62fceee73d0413e7aebd0ae2b8';
