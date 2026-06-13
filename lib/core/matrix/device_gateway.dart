/// Device-verification port: a narrow, plain-Dart interface over listing the
/// user's own Matrix devices and running an SAS (emoji) verification. The real
/// implementation (`matrix_device_gateway.dart`) wraps the Matrix client;
/// tests use an in-memory fake.
///
/// **No `package:matrix` import may ever be added to this file.** Keeps the
/// device list + verification view-model simulatable without a real homeserver.
library;

/// One of the user's own Matrix devices/sessions.
class DeviceInfo {
  final String deviceId;
  final String? displayName;

  /// True for the session this app instance is signed in on.
  final bool isThisDevice;

  /// Whether this device is cross-signing / SAS verified.
  final bool verified;

  const DeviceInfo({
    required this.deviceId,
    this.displayName,
    required this.isThisDevice,
    required this.verified,
  });

  /// A device the user can act on (verify) — another, not-yet-verified session.
  bool get needsVerification => !isThisDevice && !verified;

  String get label =>
      (displayName != null && displayName!.isNotEmpty) ? displayName! : deviceId;
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

  const VerificationState(this.phase, {this.emojis = const [], this.error});
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

abstract interface class DeviceGateway {
  /// The signed-in user's own devices/sessions.
  Future<List<DeviceInfo>> myDevices();

  /// Begins verifying [deviceId]; the returned session streams SAS state.
  VerificationSession verifyDevice(String deviceId);
}

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

/// A one-line trust summary for the device list header. Pure; unit-tested.
String deviceTrustSummary(List<DeviceInfo> devices) {
  final pending = devices.where((d) => d.needsVerification).length;
  if (devices.length <= 1) return 'This is your only device.';
  if (pending == 0) return 'All your devices are verified.';
  return pending == 1
      ? '1 device needs verification.'
      : '$pending devices need verification.';
}
