import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/auth_provider.dart';
import 'ledger_transport.dart';
import 'matrix_ledger_transport.dart';

part 'transport_provider.g.dart';

/// The single seam the rest of the app depends on for sync/transport. In tests
/// this is overridden with an in-memory fake (see test/helpers/fake_ledger_network.dart),
/// so multi-user / federated flows can be exercised without a real homeserver.
@Riverpod(keepAlive: true)
Future<LedgerTransport> ledgerTransport(Ref ref) async {
  final client = await ref.watch(matrixClientProvider.future);
  // Same instance whose inbound listener matrixClient attached before init.
  return MatrixLedgerTransport.forClient(client);
}
