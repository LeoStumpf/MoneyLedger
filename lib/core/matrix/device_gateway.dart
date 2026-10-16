/// Device-verification port: a narrow, plain-Dart interface over listing the
/// user's own (and, G11, other members') Matrix devices and running an SAS
/// (emoji) verification — started here or accepted from the other side. The real
/// implementation (`matrix_device_gateway.dart`) wraps the Matrix client;
/// tests use an in-memory fake.
///
/// **No `package:matrix` import may ever be added to this file.** Keeps the
/// device list + verification view-model simulatable without a real homeserver.
library;

import 'dart:async';

import '../../l10n/app_localizations.dart';
import 'record_crypto.dart';
import 'ledger_transport.dart' show isDeviceTrusted;

/// One Matrix device/session — the user's own, or (G11) another member's.
class DeviceInfo {
  final String deviceId;
  final String? displayName;

  /// The device's account (empty when unknown — older fakes / own list).
  final String userId;

  /// The device's Ed25519 fingerprint key (base64); null when unknown.
  final String? ed25519Key;

  /// True for the session this app instance is signed in on.
  final bool isThisDevice;

  /// Whether this device is verified — by the Matrix SDK's store, or (after
  /// [withTrust]) by this account's own emoji-verification record.
  final bool verified;

  const DeviceInfo({
    required this.deviceId,
    this.displayName,
    this.userId = '',
    this.ed25519Key,
    required this.isThisDevice,
    required this.verified,
  });

  /// This device with [verified] also honouring the app's own record of
  /// emoji-verified devices ([trusted], G11). The Matrix SDK forgets the
  /// verified flag of other users' devices in a roomless app, so the app's
  /// record is what makes a peer's verification stick.
  DeviceInfo withTrust(Set<SignerId> trusted) => DeviceInfo(
    deviceId: deviceId,
    displayName: displayName,
    userId: userId,
    ed25519Key: ed25519Key,
    isThisDevice: isThisDevice,
    verified: isDeviceTrusted(
      user: userId,
      deviceId: deviceId,
      key: ed25519Key,
      sdkVerified: verified,
      trusted: trusted,
    ),
  );

  /// A device the user can act on (verify) — another, not-yet-verified session.
  bool get needsVerification => !isThisDevice && !verified;

  String get label => (displayName != null && displayName!.isNotEmpty)
      ? displayName!
      : deviceId;
}

/// One short authentication string emoji to compare across the two devices.
class SasEmoji {
  final String emoji;
  final String name;
  const SasEmoji(this.emoji, this.name);
}

/// Phases of an SAS verification as the UI sees them.
enum VerificationPhase {
  /// Started; waiting for the other device to join / accept.
  starting,

  /// Both sides are ready — compare [VerificationState.emojis].
  compareEmojis,

  /// The other device confirmed; this device is now verified.
  success,

  /// Cancelled, timed out, or the emojis didn't match.
  failed,
}

class VerificationState {
  final VerificationPhase phase;
  final List<SasEmoji> emojis;
  final String? error;

  /// On [VerificationPhase.success]: the (user, device, Ed25519 key) that was
  /// verified — recorded by the app (G11, [recordingTrust]).
  final SignerId? verifiedDevice;

  const VerificationState(
    this.phase, {
    this.emojis = const [],
    this.error,
    this.verifiedDevice,
  });
}

/// A running SAS verification. The UI listens to [updates] and calls
/// [confirmMatch] / [cancel] in response to the user.
abstract interface class VerificationSession {
  Stream<VerificationState> get updates;

  /// The user confirmed the emojis match on both devices.
  Future<void> confirmMatch();

  /// The user aborted, or said the emojis don't match.
  Future<void> cancel();

  void dispose();
}

/// A verification request another device sent us (one of our own devices,
/// or a member verifying this device — G11). The UI asks the user, then
/// calls [accept] (and drives the returned session) or [reject].
abstract interface class IncomingVerification {
  /// The requesting account (our own MXID for our own other device).
  String get userId;

  /// The requesting device, when known.
  String? get deviceId;

  VerificationSession accept();

  Future<void> reject();
}

abstract interface class DeviceGateway {
  /// The signed-in user's own devices/sessions.
  Future<List<DeviceInfo>> myDevices();

  /// G11: the current devices of another account ([userId]), as the
  /// homeserver lists them (refreshed). Never marks [DeviceInfo.isThisDevice].
  Future<List<DeviceInfo>> userDevices(String userId);

  /// Begins verifying [deviceId] of [userId] (default: our own account); the
  /// returned session streams SAS state.
  VerificationSession verifyDevice(String deviceId, {String? userId});

  /// Verification requests from other devices (own or other members'),
  /// while the app runs.
  Stream<IncomingVerification> get incomingVerifications;
}

/// Wraps [session] so that a successful verification is recorded via
/// [record] (G11: the app's own verified-device list), whether or not the UI
/// is still showing the dialog. Errors from [record] are swallowed (the
/// verification itself still succeeded in the Matrix store).
VerificationSession recordingTrust(
  VerificationSession session,
  Future<void> Function(SignerId device) record,
) => _RecordingSession(session, record);

class _RecordingSession implements VerificationSession {
  _RecordingSession(this._inner, this._record) {
    _sub = _inner.updates.listen((s) async {
      final d = s.verifiedDevice;
      if (s.phase == VerificationPhase.success && d != null && !_recorded) {
        _recorded = true;
        try {
          await _record(d);
        } catch (_) {}
      }
    });
  }

  final VerificationSession _inner;
  final Future<void> Function(SignerId) _record;
  late final StreamSubscription<VerificationState> _sub;
  bool _recorded = false;

  @override
  Stream<VerificationState> get updates => _inner.updates;

  @override
  Future<void> confirmMatch() => _inner.confirmMatch();

  @override
  Future<void> cancel() => _inner.cancel();

  @override
  void dispose() {
    _sub.cancel();
    _inner.dispose();
  }
}

/// How many of a member's devices are unverified (G11, members page).
class PeerDeviceTrust {
  final int total;
  final int unverified;
  const PeerDeviceTrust({required this.total, required this.unverified});

  /// Some device of this member isn't verified — warn.
  bool get needsAttention => unverified > 0;

  /// The member has devices and none of them is verified — under
  /// verified-only sync they receive nothing.
  bool get noneVerified => total > 0 && unverified == total;
}

/// Summarises [devices] (already [DeviceInfo.withTrust]-resolved). Pure.
PeerDeviceTrust peerDeviceTrust(List<DeviceInfo> devices) => PeerDeviceTrust(
  total: devices.length,
  unverified: devices.where((d) => !d.verified).length,
);

/// Orders devices for display: this device first, then the ones needing
/// verification (so they draw the eye), then the rest — alphabetically by label
/// within each group. Pure; unit-tested.
List<DeviceInfo> sortDevices(List<DeviceInfo> devices) {
  int rank(DeviceInfo d) => d.isThisDevice
      ? 0
      : d.needsVerification
      ? 1
      : 2;
  final sorted = [...devices];
  sorted.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return sorted;
}

/// A one-line trust summary for the device list header, localized through
/// [l]. Pure; unit-tested.
String deviceTrustSummary(List<DeviceInfo> devices, AppLocalizations l) {
  final pending = devices.where((d) => d.needsVerification).length;
  if (devices.length <= 1) return l.onlyDevice;
  if (pending == 0) return l.allDevicesVerified;
  return l.devicesNeedVerification(pending);
}
