import 'dart:async';

// hide DeviceInfo: the SDK exports a same-named type; ours is the app port type.
import 'package:matrix/matrix.dart' hide DeviceInfo;
import 'package:matrix/encryption.dart';

import 'device_gateway.dart';
import 'record_crypto.dart';

/// Real [DeviceGateway] backed by the Matrix SDK [Client] — the only place that
/// translates the SDK's device-key + key-verification types into the app's
/// plain-Dart device port. Not unit-tested (needs a real homeserver + a second
/// device + olm); the verification round-trip is manual-smoke, like the SSO
/// deep link. The pure view-model around it (`device_gateway.dart`) is tested.
///
/// Verification is **to-device SAS** (no rooms) — works for our own other
/// devices and (G11) for another member's device alike. Requires the client
/// to advertise the SAS methods (`verificationMethods` in
/// `buildMatrixClient`); without them the SDK ignores every request.
class MatrixDeviceGateway implements DeviceGateway {
  final Client _client;
  MatrixDeviceGateway(this._client);

  DeviceInfo _info(DeviceKeys dk) => DeviceInfo(
    deviceId: dk.deviceId ?? '',
    displayName: dk.deviceDisplayName,
    userId: dk.userId,
    ed25519Key: dk.ed25519Key,
    isThisDevice:
        dk.userId == _client.userID && dk.deviceId == _client.deviceID,
    verified: dk.verified,
  );

  @override
  Future<List<DeviceInfo>> myDevices() async {
    final userId = _client.userID;
    if (userId == null) return [];
    final keys = _client.userDeviceKeys[userId]?.deviceKeys.values ?? const [];
    return [for (final dk in keys) _info(dk)];
  }

  @override
  Future<List<DeviceInfo>> userDevices(String userId) async {
    if (!_client.isLogged() || userId.isEmpty) return [];
    // Roomless: the SDK only tracks users we name — refresh this one.
    await _client.updateUserDeviceKeys(additionalUsers: {userId});
    final keys = _client.userDeviceKeys[userId]?.deviceKeys.values ?? const [];
    return [
      for (final dk in keys)
        if (dk.isValid && !dk.blocked) _info(dk),
    ];
  }

  @override
  VerificationSession verifyDevice(String deviceId, {String? userId}) =>
      _MatrixVerificationSession.outgoing(
        _client,
        userId ?? _client.userID ?? '',
        deviceId,
      );

  @override
  Stream<IncomingVerification> get incomingVerifications => _client
      .onKeyVerificationRequest
      .stream
      .where((kv) => !kv.isDone && kv.state == KeyVerificationState.askAccept)
      .map((kv) => _MatrixIncoming(_client, kv));
}

class _MatrixIncoming implements IncomingVerification {
  _MatrixIncoming(this._client, this._kv);
  final Client _client;
  final KeyVerification _kv;

  @override
  String get userId => _kv.userId;

  @override
  String? get deviceId => _kv.deviceId;

  @override
  VerificationSession accept() =>
      _MatrixVerificationSession.incoming(_client, _kv);

  @override
  Future<void> reject() => _kv.rejectVerification();
}

class _MatrixVerificationSession implements VerificationSession {
  final Client _client;
  final _controller = StreamController<VerificationState>.broadcast();
  KeyVerification? _kv;

  /// The verified device's key, captured once the SAS is shown (the SDK may
  /// evict the peer's device list from memory before `done`).
  String? _key;

  _MatrixVerificationSession.outgoing(
    this._client,
    String userId,
    String deviceId,
  ) {
    _startOutgoing(userId, deviceId);
  }

  _MatrixVerificationSession.incoming(this._client, KeyVerification kv) {
    _kv = kv;
    kv.onUpdate = () => _onUpdate(kv);
    _acceptIncoming(kv);
  }

  VerificationState _last = const VerificationState(VerificationPhase.starting);

  /// Replays the latest state to each new listener (the dialog may subscribe
  /// a frame after the session started), then follows live.
  @override
  Stream<VerificationState> get updates => Stream.multi((c) {
    c.add(_last);
    final sub = _controller.stream.listen(c.add, onDone: c.close);
    c.onCancel = sub.cancel;
  });

  Future<void> _startOutgoing(String userId, String deviceId) async {
    _emit(const VerificationState(VerificationPhase.starting));
    try {
      var dk = _client.userDeviceKeys[userId]?.deviceKeys[deviceId];
      if (dk == null) {
        await _client.updateUserDeviceKeys(additionalUsers: {userId});
        dk = _client.userDeviceKeys[userId]?.deviceKeys[deviceId];
      }
      if (dk == null) {
        _emit(
          const VerificationState(
            VerificationPhase.failed,
            error: 'Unknown device',
          ),
        );
        return;
      }
      final kv = await dk.startVerification();
      _kv = kv;
      kv.onUpdate = () => _onUpdate(kv);
      _onUpdate(kv);
    } catch (e) {
      _emit(VerificationState(VerificationPhase.failed, error: e.toString()));
    }
  }

  Future<void> _acceptIncoming(KeyVerification kv) async {
    _emit(const VerificationState(VerificationPhase.starting));
    try {
      await kv.acceptVerification();
    } catch (e) {
      _emit(VerificationState(VerificationPhase.failed, error: e.toString()));
    }
  }

  void _onUpdate(KeyVerification kv) {
    switch (kv.state) {
      case KeyVerificationState.askSSSS:
        // The account has cross-signing but its keys aren't cached here: the
        // app doesn't do cross-signing — skip it (the device itself is
        // verified either way).
        unawaited(kv.openSSSS(skip: true));
        _emit(const VerificationState(VerificationPhase.starting));
      case KeyVerificationState.askSas:
        _key = _client
            .userDeviceKeys[kv.userId]
            ?.deviceKeys[kv.deviceId]
            ?.ed25519Key;
        _emit(
          VerificationState(
            VerificationPhase.compareEmojis,
            emojis: [
              for (final e in kv.sasEmojis)
                SasEmoji(e.emoji, e.name, number: e.number),
            ],
          ),
        );
      case KeyVerificationState.done:
        final device = kv.deviceId;
        final key =
            _key ??
            _client.userDeviceKeys[kv.userId]?.deviceKeys[device]?.ed25519Key;
        _emit(
          VerificationState(
            VerificationPhase.success,
            verifiedDevice: device == null || key == null
                ? null
                : SignerId(user: kv.userId, device: device, key: key),
          ),
        );
      case KeyVerificationState.error:
        _emit(
          VerificationState(VerificationPhase.failed, error: kv.canceledReason),
        );
      default:
        _emit(const VerificationState(VerificationPhase.starting));
    }
  }

  /// The SDK can leave a verification hanging forever when a send fails
  /// mid-way (seen on a flaky emulator network: the cancel itself failed, so
  /// the state never left "waiting"). Give up after this long without
  /// progress so the dialog can't spin forever.
  static const _stallTimeout = Duration(minutes: 3);
  Timer? _stall;

  void _emit(VerificationState s) {
    _last = s;
    _stall?.cancel();
    final open =
        s.phase == VerificationPhase.starting ||
        s.phase == VerificationPhase.compareEmojis;
    if (open && !_controller.isClosed) {
      _stall = Timer(_stallTimeout, () {
        _emit(
          const VerificationState(VerificationPhase.failed, error: 'timed out'),
        );
      });
    }
    if (!_controller.isClosed) _controller.add(s);
  }

  @override
  Future<void> confirmMatch() async => _kv?.acceptSas();

  @override
  Future<void> cancel() async {
    final kv = _kv;
    if (kv != null && !kv.isDone) await kv.cancel();
  }

  @override
  void dispose() {
    _stall?.cancel();
    _kv?.onUpdate = null;
    _controller.close();
  }
}
