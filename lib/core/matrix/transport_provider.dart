import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/auth_provider.dart';
import '../session/app_session.dart';
import '../session/local_transport.dart';
import 'ledger_transport.dart';
import 'matrix_ledger_transport.dart';

part 'transport_provider.g.dart';

/// The single seam the rest of the app depends on for sync/transport. In tests
/// this is overridden with an in-memory fake (see test/helpers/fake_ledger_network.dart),
/// so multi-user / federated flows can be exercised without a real homeserver.
///
/// G40: in local mode it is a [LocalOnlyTransport] — no Matrix client is
/// built, nothing is sent or received, nothing can be signed.
@Riverpod(keepAlive: true)
Future<LedgerTransport> ledgerTransport(Ref ref) async {
  if (ref.watch(localModeActiveProvider)) {
    return LocalOnlyTransport(ref.watch(localProfileProvider)?.name ?? '');
  }
  // Device preferences still loading: don't build a Matrix client yet (it
  // may turn out to be local mode); this provider rebuilds once they load.
  if (!ref.watch(matrixSessionWantedProvider)) {
    return Completer<LedgerTransport>().future;
  }
  final client = await ref.watch(matrixClientProvider.future);
  // Same instance whose inbound listener matrixClient attached before init.
  return MatrixLedgerTransport.forClient(client);
}
