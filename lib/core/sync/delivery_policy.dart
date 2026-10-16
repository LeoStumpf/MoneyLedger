/// G11 — opt-in "only sync with verified devices".
///
/// Every app sender (replication, digests, bootstraps, resync answers, group
/// mutations, restore) reaches the relay through a [PolicyTransport] built
/// from the **same** account DB it writes to (captured before the first
/// await, G19). Each send reads the account's current [DeliveryPolicy] and
/// hands it to the transport, which withholds unverified devices
/// (`planDeviceSend`). Plain Dart — no `package:matrix`.
library;

import '../database/daos/settings_dao.dart';
import '../matrix/ledger_transport.dart';

/// Delegates everything to [inner]; every [sendToUsers] carries the policy
/// [policy] currently returns (the caller's `policy` argument is ignored —
/// the account setting is authoritative). Fails **closed**: if the policy
/// can't be read, nothing is sent ([TransportUnavailableException]).
class PolicyTransport implements LedgerTransport {
  PolicyTransport(this.inner, this.policy);

  final LedgerTransport inner;
  final Future<DeliveryPolicy> Function() policy;

  @override
  String get userId => inner.userId;

  @override
  Stream<TransportMessage> get onMessage => inner.onMessage;

  @override
  RecordCrypto get crypto => inner.crypto;

  @override
  DeviceKeyDirectory get deviceKeys => inner.deviceKeys;

  @override
  Future<String?> profileName(String matrixId) => inner.profileName(matrixId);

  @override
  Future<SendResult> sendToUsers(
    Set<String> userIds,
    String type,
    Map<String, dynamic> content, {
    DeliveryPolicy policy = DeliveryPolicy.everyone,
  }) async {
    final DeliveryPolicy current;
    try {
      current = await this.policy();
    } catch (e) {
      throw TransportUnavailableException('delivery policy unavailable: $e');
    }
    return inner.sendToUsers(userIds, type, content, policy: current);
  }
}

/// [inner] wrapped so its sends follow [settings]' delivery policy.
Future<LedgerTransport> withDeliveryPolicy(
  Future<LedgerTransport> inner,
  SettingsDao settings,
) async => PolicyTransport(await inner, settings.deliveryPolicy);
