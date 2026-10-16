/// In-memory [DeviceGateway] for testing the devices UI — no real homeserver,
/// no olm. The verification session emits a fixed emoji list and, on confirm,
/// marks the device verified (and reports it as the verified device, G11).
library;

import 'dart:async';

import 'package:money_ledger/core/matrix/device_gateway.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:money_ledger/core/matrix/record_crypto.dart';
import 'package:money_ledger/features/devices/device_provider.dart';

class FakeDeviceGateway implements DeviceGateway {
  List<DeviceInfo> devices;

  /// G11: other members' devices by MXID.
  Map<String, List<DeviceInfo>> peers;

  FakeDeviceGateway(this.devices, {Map<String, List<DeviceInfo>>? peers})
    : peers = peers ?? {};

  static const sampleEmojis = [
    SasEmoji('🐶', 'Dog', number: 0),
    SasEmoji('🐱', 'Cat', number: 1),
    SasEmoji('🦁', 'Lion', number: 2),
  ];

  /// Push incoming verification requests here.
  final incoming = StreamController<IncomingVerification>.broadcast();

  @override
  Future<List<DeviceInfo>> myDevices() async => devices;

  @override
  Future<List<DeviceInfo>> userDevices(String userId) async =>
      peers[userId] ?? const [];

  @override
  VerificationSession verifyDevice(String deviceId, {String? userId}) =>
      FakeVerificationSession(this, deviceId, peerUserId: userId);

  @override
  Stream<IncomingVerification> get incomingVerifications => incoming.stream;
}

class FakeVerificationSession implements VerificationSession {
  final FakeDeviceGateway _gateway;
  final String _deviceId;
  final String? peerUserId;
  // Like the real session: every listener (the G11 trust recorder, the
  // dialog's StreamBuilder attaching a frame later) first gets the latest
  // state, then live updates.
  final _controller = StreamController<VerificationState>.broadcast();
  VerificationState _last = const VerificationState(VerificationPhase.starting);

  FakeVerificationSession(this._gateway, this._deviceId, {this.peerUserId}) {
    _emit(
      const VerificationState(
        VerificationPhase.compareEmojis,
        emojis: FakeDeviceGateway.sampleEmojis,
      ),
    );
  }

  void _emit(VerificationState s) {
    _last = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  @override
  Stream<VerificationState> get updates => Stream.multi((c) {
    c.add(_last);
    final sub = _controller.stream.listen(c.add, onDone: c.close);
    c.onCancel = sub.cancel;
  });

  List<DeviceInfo> _mark(List<DeviceInfo> list) => [
    for (final d in list)
      if (d.deviceId == _deviceId)
        DeviceInfo(
          deviceId: d.deviceId,
          displayName: d.displayName,
          userId: d.userId,
          ed25519Key: d.ed25519Key,
          isThisDevice: d.isThisDevice,
          verified: true,
        )
      else
        d,
  ];

  @override
  Future<void> confirmMatch() async {
    final user = peerUserId;
    DeviceInfo? device;
    if (user == null) {
      device = _gateway.devices.where((d) => d.deviceId == _deviceId).first;
      _gateway.devices = _mark(_gateway.devices);
    } else {
      device = (_gateway.peers[user] ?? const <DeviceInfo>[])
          .where((d) => d.deviceId == _deviceId)
          .firstOrNull;
      // A peer's verified flag lives only in the app's record (the SDK
      // forgets it) — don't flip it here.
    }
    _emit(
      VerificationState(
        VerificationPhase.success,
        verifiedDevice: SignerId(
          user: user ?? device?.userId ?? '',
          device: _deviceId,
          key: device?.ed25519Key ?? 'key-$_deviceId',
        ),
      ),
    );
  }

  @override
  Future<void> cancel() async {
    _emit(const VerificationState(VerificationPhase.failed));
  }

  @override
  void dispose() => _controller.close();
}

/// G11: the app's verified-device record + the verified-only flag, in
/// memory (no drift stream timers in widget tests).
class FakeTrustStore {
  FakeTrustStore({Set<SignerId>? trusted, this.verifiedOnly = false})
    : trusted = {...?trusted};

  final Set<SignerId> trusted;
  bool verifiedOnly;
  final _changes = StreamController<Set<SignerId>>.broadcast();

  Future<void> record(SignerId device) async {
    trusted.add(device);
    _changes.add({...trusted});
  }

  Stream<Set<SignerId>> watch() async* {
    yield {...trusted};
    yield* _changes.stream;
  }

  /// Overrides for the device-trust providers backed by this store and
  /// [gateway].
  List<Override> overrides(FakeDeviceGateway gateway) => [
    deviceGatewayProvider.overrideWith((ref) async => gateway),
    trustedDevicesProvider.overrideWith((ref) => watch()),
    deviceTrustRecorderProvider.overrideWithValue(record),
    verifiedOnlySyncProvider.overrideWith((ref) => Stream.value(verifiedOnly)),
  ];
}
