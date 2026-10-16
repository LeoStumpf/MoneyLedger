import 'dart:async';

import '../matrix/ledger_transport.dart';

/// Offline [LedgerTransport] for the demo: every send "succeeds" (each target
/// counts as one reachable device; our own account has no other device, so a
/// new-device recovery ends at once) and nothing ever arrives.
class DemoTransport implements LedgerTransport {
  @override
  final String userId;

  final _inbound = StreamController<TransportMessage>.broadcast();

  DemoTransport(this.userId);

  @override
  Stream<TransportMessage> get onMessage => _inbound.stream;

  @override
  Future<SendResult> sendToUsers(
    Set<String> userIds,
    String type,
    Map<String, dynamic> content,
  ) async => SendResult(deviceCount: userIds.where((u) => u != userId).length);

  @override
  Future<String?> profileName(String matrixId) async => null;
}
