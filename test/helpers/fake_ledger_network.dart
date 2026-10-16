/// An in-memory "virtual relay": multiple users, each with one or more
/// [FakeTransport]s (devices), all sharing one [FakeMatrixNetwork]. Models the
/// roomless to-device relay — `sendToUsers` delivers an encrypted-equivalent
/// payload to every device of each target user, except the exact sending
/// device (real homeserver semantics: your *other* devices do receive).
/// No rooms, no real Matrix client, no sqlite3, no network.
///
/// Wire it into the app by overriding `ledgerTransportProvider` with
/// `net.clientFor(userId)` (or `clientFor(userId, device: 'D2')` for a
/// second device of the same account).
///
/// Send semantics match the real adapter (G24): a target user with no device
/// is reported in [SendResult.unreachableUsers] (never the sender's own MXID),
/// and a transport with [FakeTransport.unavailable] set throws
/// [TransportUnavailableException] (signed out / encryption off).
///
/// With `bufferInbound: true` every device's inbound stream goes through a
/// [BufferedInbox] like the real transport: payloads delivered while nothing
/// listens are replayed to the next listeners. Off by default, so a device
/// without listeners keeps "missing" payloads as before (several tests rely
/// on that to simulate an offline device).
///
/// No `package:matrix` import — it only depends on the plain-Dart transport port.
library;

import 'dart:async';

import 'package:money_ledger/core/matrix/buffered_inbox.dart';
import 'package:money_ledger/core/matrix/hmac_record_crypto.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/sync/payload_budget.dart';

class FakeMatrixNetwork {
  FakeMatrixNetwork({this.bufferInbound = false});

  /// Whether devices buffer inbound payloads while nobody listens.
  final bool bufferInbound;

  /// G6: every fake device's signing key + the "homeserver device list".
  /// [removeDevice] also drops the device from it (sign-out).
  final HmacKeyRegistry keys = HmacKeyRegistry();

  /// Public profile display names by MXID (G17) — what
  /// [FakeTransport.profileName] returns; absent → null (no display name).
  final Map<String, String> profiles = {};

  // userId → (deviceId → transport)
  final Map<String, Map<String, FakeTransport>> _clients = {};

  /// Loss injection: when set, any delivery for which this returns true is
  /// silently dropped — simulates a to-device message lost in transit, the
  /// exact failure anti-entropy must repair. Set back to null to "reconnect".
  bool Function(String sender, String target, String type)? dropWhere;

  /// G14: max JSON bytes per payload, like the homeserver's 64 KiB
  /// to-device limit — a larger send throws [PayloadTooLargeException]
  /// (default: the real ceiling; tests with a small `payloadBudgetProvider`
  /// lower it to prove the senders chunk).
  int maxPayloadBytes = kHardMaxPayloadBytes;

  /// Bumped on every send and every delivery — [settle] waits until this stops
  /// moving.
  int _activity = 0;

  /// Returns (creating on first use) the transport view for one device of
  /// [userId], e.g. `@alice:x.org`. Create a user's transport before they
  /// need to receive payloads so delivery has somewhere to go.
  FakeTransport clientFor(String userId, {String device = 'D1'}) => _clients
      .putIfAbsent(userId, () => {})
      .putIfAbsent(device, () => FakeTransport(this, userId, device));

  /// G11: devices (`'<user>|<device>'`) the simulated Matrix SDK reports as
  /// verified (as if verified in another client / via cross-signing).
  final Set<String> sdkVerified = {};

  /// Simulates a device signing out: it no longer receives anything, and a
  /// user left with no devices becomes unreachable for senders.
  void removeDevice(String userId, {String device = 'D1'}) {
    _clients[userId]?.remove(device)?.dispose();
    keys.removeDevice(userId, device);
  }

  SendResult _send(
    FakeTransport senderDevice,
    Set<String> targets,
    String type,
    Map<String, dynamic> content,
    DeliveryPolicy policy,
  ) {
    final bytes = encodedPayloadBytes(content);
    if (bytes > maxPayloadBytes) throw PayloadTooLargeException(type, bytes);
    final sender = senderDevice.userId;
    _activity++;
    sent.add((sender: sender, targets: targets, type: type, content: content));
    // Same decision as the real adapter (sender's current device excluded —
    // the sender's *other* devices do receive the payload).
    final plan = planDeviceSend(
      targets: targets,
      selfUserId: sender,
      selfDeviceId: senderDevice.deviceId,
      devicesByUser: {
        for (final t in targets)
          t: [
            for (final id in (_clients[t] ?? const {}).keys)
              TransportDevice(
                id,
                verified: sdkVerified.contains('$t|$id'),
                key: keys.listedKey(t, id),
              ),
          ],
      },
      policy: policy,
    );
    for (final MapEntry(key: target, value: ids) in plan.devices.entries) {
      if (dropWhere?.call(sender, target, type) ?? false) continue;
      for (final id in ids) {
        _clients[target]?[id]?._emit(
          TransportMessage(senderId: sender, type: type, content: content),
        );
      }
    }
    return SendResult(
      unreachableUsers: plan.unreachableUsers,
      unverifiedUsers: plan.unverifiedUsers,
      deviceCount: plan.deviceCount,
      withheldDevices: plan.withheldDevices,
    );
  }

  /// Every send attempted on this network (a log for count assertions).
  final List<
    ({
      String sender,
      Set<String> targets,
      String type,
      Map<String, dynamic> content,
    })
  >
  sent = [];

  /// Waits until the relay is **quiescent**: [quietTicks] consecutive short
  /// timer ticks during which nothing was sent or delivered. Call after each
  /// action before asserting on derived state.
  ///
  /// Deterministic under CPU load (unlike a fixed sleep): each tick is a 2 ms
  /// timer, and Dart runs every pending microtask (in-memory Drift work, stream
  /// deliveries) and every earlier-due timer (the 1 ms poke debounce used by
  /// the SyncEngine tests) before it — so a chain that is still producing
  /// messages always resets the count, however slow the machine is. Throws if
  /// the network never goes quiet within [timeout] (a ping-pong bug).
  Future<void> settle({
    int quietTicks = 5,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final sw = Stopwatch()..start();
    var seen = _activity;
    var quiet = 0;
    while (quiet < quietTicks) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (_activity != seen) {
        seen = _activity;
        quiet = 0;
      } else {
        quiet++;
      }
      if (sw.elapsed > timeout) {
        throw TimeoutException('fake network never went quiet', timeout);
      }
    }
  }
}

class FakeTransport implements LedgerTransport {
  final FakeMatrixNetwork _net;
  @override
  final String userId;
  final String deviceId;
  final StreamController<TransportMessage> _controller =
      StreamController.broadcast();
  late final BufferedInbox? _inbox = _net.bufferInbound
      ? BufferedInbox(
          replayDelay: Duration.zero,
          onReplay: () => _net._activity++,
        )
      : null;

  /// When set, every send throws [TransportUnavailableException] — simulates
  /// a signed-out client / encryption not enabled.
  bool unavailable = false;

  FakeTransport(this._net, this.userId, this.deviceId)
    : crypto = _net.keys.deviceCrypto(userId, deviceId);

  /// G6: this fake device's signer (see [HmacKeyRegistry]). Set
  /// `crypto.ready = false` to simulate encryption not being ready.
  @override
  final HmacRecordCrypto crypto;

  @override
  DeviceKeyDirectory get deviceKeys => _net.keys;

  void _emit(TransportMessage m) {
    _net._activity++;
    final inbox = _inbox;
    if (inbox != null) {
      inbox.add(m);
    } else if (!_controller.isClosed) {
      _controller.add(m);
    }
  }

  void dispose() {
    _controller.close();
    _inbox?.close();
  }

  @override
  Stream<TransportMessage> get onMessage =>
      _inbox?.stream ?? _controller.stream;

  @override
  Future<SendResult> sendToUsers(
    Set<String> userIds,
    String type,
    Map<String, dynamic> content, {
    DeliveryPolicy policy = DeliveryPolicy.everyone,
  }) async {
    if (unavailable) {
      throw const TransportUnavailableException('encryption is not enabled');
    }
    return _net._send(this, userIds, type, content, policy);
  }

  @override
  Future<String?> profileName(String matrixId) async =>
      normalizeProfileName(_net.profiles[matrixId]);
}
