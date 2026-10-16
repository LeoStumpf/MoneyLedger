import 'dart:async';

import '../matrix/ed25519_verify.dart';
import '../matrix/ledger_transport.dart';
import 'app_session.dart';

/// The transport of local mode (G40): there is no relay. Nothing is ever
/// sent (every send reaches no device and is no error), nothing arrives, and
/// there is no device key — local writes are therefore stored `pendingSign`
/// and get signed by the account's device once the local ledger is adopted
/// into a Matrix account (`local_adoption.dart`).
///
/// [userId] is [kLocalAccountId], the claimant of the user's own participant
/// ("me"); [profileName] answers the local profile's name for it, so a new
/// group's creator is named like the user chose.
///
/// G41: signatures can still be **verified** ([verify], Ed25519 via
/// vodozemac — no Matrix client needed), so a backup made with a Matrix
/// account restores in local mode instead of being refused as forged.
class LocalOnlyTransport implements LedgerTransport {
  LocalOnlyTransport(
    this.profile, {
    bool Function(String key, String message, String signature) verify =
        verifyEd25519,
  }) : crypto = _NoCrypto(verify);

  /// The local profile's display name.
  final String profile;

  @override
  String get userId => kLocalAccountId;

  @override
  Stream<TransportMessage> get onMessage => const Stream.empty();

  @override
  Future<SendResult> sendToUsers(
    Set<String> userIds,
    String type,
    Map<String, dynamic> content, {
    DeliveryPolicy policy = DeliveryPolicy.everyone,
  }) async => SendResult.nothingToSend;

  @override
  Future<String?> profileName(String matrixId) async =>
      isLocalAccountId(matrixId) ? normalizeProfileName(profile) : null;

  @override
  final RecordCrypto crypto;

  @override
  DeviceKeyDirectory get deviceKeys => const _NoDirectory();
}

/// No device key: [identity] is null, so `LocalRecordSigner` stores every
/// write `pendingSign` at once (no wait). Verifying works (G41).
class _NoCrypto implements RecordCrypto {
  const _NoCrypto(this._verify);

  final bool Function(String key, String message, String signature) _verify;

  @override
  SignerId? get identity => null;

  @override
  Future<String> sign(String message) =>
      throw StateError('Local mode has no device key');

  @override
  bool verify(String key, String message, String signature) =>
      _verify(key, message, signature);
}

class _NoDirectory implements DeviceKeyDirectory {
  const _NoDirectory();

  @override
  Future<Map<String, Map<String, String>>> currentDevices(
    Set<String> users,
  ) async => const {};
}
