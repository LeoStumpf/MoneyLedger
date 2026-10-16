/// The app's transport port: a narrow, plain-Dart interface over whatever
/// relays ledger data (the real Matrix client, or an in-memory fake in tests).
///
/// **No `package:matrix` import may ever be added to this file.** Everything
/// here is plain Dart so that test code (and the fake network) can depend on it
/// without pulling in the Matrix SDK / native sqlite3. The real implementation
/// lives in `matrix_ledger_transport.dart`.
///
/// Phase B: this is a **roomless relay**. There are no Matrix rooms — groups and
/// membership are owned by the local DB. The transport only resolves a set of
/// member MXIDs to their devices and ships an encrypted to-device payload to
/// them, and exposes an inbound stream of decrypted payloads. The homeserver
/// retains nothing once a to-device message is delivered.
library;

import 'record_crypto.dart';

export 'record_crypto.dart';

// Payload type tags carried as the to-device event `type`. All app payloads use
// the `com.moneyledger.` prefix so the transport can filter them on receive.
const expenseEventType = 'com.moneyledger.expense';
const settlementEventType = 'com.moneyledger.settlement';
const groupMetaEventType = 'com.moneyledger.group';
const memberEventType = 'com.moneyledger.member';
const bootstrapEventType = 'com.moneyledger.bootstrap';
// Phase C anti-entropy: per-group record digests + full-state resync requests.
const digestEventType = 'com.moneyledger.digest';
const resyncRequestEventType = 'com.moneyledger.resync_request';

/// Common prefix for every app to-device payload (used to filter inbound).
const moneyLedgerTypePrefix = 'com.moneyledger.';

/// One decrypted inbound to-device payload.
class TransportMessage {
  final String senderId;
  final String type;
  final Map<String, dynamic> content;

  const TransportMessage({
    required this.senderId,
    required this.type,
    required this.content,
  });
}

/// Thrown by [LedgerTransport.sendToUsers] when nothing can be sent at all:
/// the relay isn't signed in, or end-to-end encryption isn't set up (the
/// Matrix SDK silently drops to-device sends when encryption is disabled).
/// A real transport failure — it counts against `SyncHealth`.
class TransportUnavailableException implements Exception {
  final String reason;
  const TransportUnavailableException(this.reason);

  @override
  String toString() => 'Transport unavailable: $reason';
}

/// What one [LedgerTransport.sendToUsers] call reached.
///
/// "No device found" for **another** user is not a transport error — that
/// person may simply have no logged-in device right now (the message can't be
/// queued for a device that doesn't exist yet; anti-entropy catches them up
/// once they sign in). It is reported here, distinctly, so the UI can say
/// "B has no active device" instead of showing a scary error. The sender's
/// **own** account is never listed: having no *other* own device is normal.
class SendResult {
  /// Targets (other than the sender's own MXID) with no device to send to.
  final Set<String> unreachableUsers;

  /// G11: the subset of [unreachableUsers] that *do* have devices, all of
  /// which were withheld because none is verified ("only sync with verified
  /// devices" is on).
  final Set<String> unverifiedUsers;

  /// How many devices the payload was handed to for delivery.
  final int deviceCount;

  /// G11: devices (own and peers') skipped because they aren't verified.
  final int withheldDevices;

  const SendResult({
    this.unreachableUsers = const {},
    this.unverifiedUsers = const {},
    this.deviceCount = 0,
    this.withheldDevices = 0,
  });

  static const nothingToSend = SendResult();
}

/// One candidate device of a target user, as seen by the transport adapter.
class TransportDevice {
  final String deviceId;

  /// Blocked in the Matrix SDK — never sent to.
  final bool blocked;

  /// Verified according to the Matrix SDK's own store (SAS / cross-signing).
  final bool verified;

  /// The device's Ed25519 key (null when unknown) — matched against the
  /// app's own verified-device record (G11, [DeliveryPolicy.trusted]).
  final String? key;

  const TransportDevice(
    this.deviceId, {
    this.blocked = false,
    this.verified = false,
    this.key,
  });
}

/// Whether the device [deviceId] of [user] (current key [key]) counts as
/// verified: the SDK says so ([sdkVerified]) or this account verified exactly
/// this (user, device, key) by emoji comparison ([trusted], G11). A device
/// whose key changed since it was verified is **not** verified. Pure.
bool isDeviceTrusted({
  required String user,
  required String deviceId,
  required String? key,
  required bool sdkVerified,
  required Set<SignerId> trusted,
}) =>
    sdkVerified ||
    (key != null &&
        trusted.contains(SignerId(user: user, device: deviceId, key: key)));

/// G11: where a send may go. [everyone] (the default) = every device of
/// every target; with [verifiedOnly] only verified devices
/// ([isDeviceTrusted]) receive anything — own and peers' alike.
class DeliveryPolicy {
  final bool verifiedOnly;

  /// (user, device, Ed25519 key) this account verified by emoji comparison.
  final Set<SignerId> trusted;

  const DeliveryPolicy({this.verifiedOnly = false, this.trusted = const {}});

  static const everyone = DeliveryPolicy();

  bool allows(String user, TransportDevice d) =>
      !verifiedOnly ||
      isDeviceTrusted(
        user: user,
        deviceId: d.deviceId,
        key: d.key,
        sdkVerified: d.verified,
        trusted: trusted,
      );
}

/// The pure delivery decision behind every real send (plain Dart so it is
/// unit-testable without the Matrix SDK).
class DevicePlan {
  /// userId → device ids to send to (blocked devices and the sender's current
  /// device removed — exactly what the SDK itself would skip — and, under a
  /// verified-only [DeliveryPolicy], unverified devices).
  final Map<String, List<String>> devices;

  /// Targets other than [planDeviceSend]'s `selfUserId` with no sendable device.
  final Set<String> unreachableUsers;

  /// The subset of [unreachableUsers] whose devices were all withheld as
  /// unverified (G11).
  final Set<String> unverifiedUsers;

  /// Devices withheld as unverified (own other devices included).
  final int withheldDevices;

  const DevicePlan({
    required this.devices,
    required this.unreachableUsers,
    this.unverifiedUsers = const {},
    this.withheldDevices = 0,
  });

  int get deviceCount => devices.values.fold(0, (sum, ids) => sum + ids.length);
}

/// Decides which devices of [targets] to send to, given every target's known
/// [devicesByUser]. The sender's current device ([selfUserId]/[selfDeviceId])
/// and blocked devices are excluded, and so are devices [policy] doesn't
/// allow (G11 verified-only). A target other than [selfUserId] left with no
/// device is *unreachable* — *unverified* when it had devices that were only
/// withheld by the policy; self with no other device is normal (a
/// single-device user's digest/resync to self) and never reported.
DevicePlan planDeviceSend({
  required Set<String> targets,
  required String selfUserId,
  required String? selfDeviceId,
  required Map<String, Iterable<TransportDevice>> devicesByUser,
  DeliveryPolicy policy = DeliveryPolicy.everyone,
}) {
  final devices = <String, List<String>>{};
  final unreachable = <String>{};
  final unverified = <String>{};
  var withheld = 0;
  for (final user in targets) {
    if (user.isEmpty) continue;
    final ids = <String>[];
    var withheldHere = 0;
    for (final d in devicesByUser[user] ?? const <TransportDevice>[]) {
      if (d.blocked || (user == selfUserId && d.deviceId == selfDeviceId)) {
        continue;
      }
      if (!policy.allows(user, d)) {
        withheldHere++;
        continue;
      }
      ids.add(d.deviceId);
    }
    withheld += withheldHere;
    if (ids.isNotEmpty) {
      devices[user] = ids;
    } else if (user != selfUserId) {
      unreachable.add(user);
      if (withheldHere > 0) unverified.add(user);
    }
  }
  return DevicePlan(
    devices: devices,
    unreachableUsers: unreachable,
    unverifiedUsers: unverified,
    withheldDevices: withheld,
  );
}

/// The operations the app needs from its relay layer.
abstract interface class LedgerTransport {
  /// This device's own Matrix ID.
  String get userId;

  /// Inbound decrypted app payloads. Broadcast — multiple listeners supported.
  /// Messages that arrive while **nobody** listens (app start before the sync
  /// components attach, an account-DB switch) are buffered and replayed to the
  /// next listeners — see `BufferedInbox`.
  Stream<TransportMessage> get onMessage;

  /// Encrypts and relays [content] (tagged [type]) to every device of every
  /// MXID in [userIds]. Best-effort once handed over: the homeserver queues
  /// undelivered to-device messages, and the SDK retries failed sends.
  ///
  /// Throws [TransportUnavailableException] when nothing can be sent at all
  /// (signed out / encryption not ready). Targets without any device are
  /// reported in [SendResult.unreachableUsers] rather than thrown.
  ///
  /// [policy] (G11) restricts delivery to verified devices; the app's
  /// senders pass the account's setting via `PolicyTransport`.
  Future<SendResult> sendToUsers(
    Set<String> userIds,
    String type,
    Map<String, dynamic> content, {
    DeliveryPolicy policy = DeliveryPolicy.everyone,
  });

  /// The public Matrix profile display name of [matrixId] (G17) — used as a
  /// participant's name when they are added by MXID. Null when the account
  /// has no display name or the lookup fails (offline, unknown user); never
  /// throws.
  Future<String?> profileName(String matrixId);

  /// G6: this device's record signer + Ed25519 verifier (the relay identity's
  /// Matrix device key).
  RecordCrypto get crypto;

  /// G6: the homeserver's current device keys — first-hand (user, device) →
  /// key bindings for verifying record signatures.
  DeviceKeyDirectory get deviceKeys;
}

/// [name] trimmed, or null when it is empty / null — the profile-name
/// normalisation shared by every [LedgerTransport.profileName].
String? normalizeProfileName(String? name) {
  final t = name?.trim();
  return (t == null || t.isEmpty) ? null : t;
}
