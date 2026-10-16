/// G6 signed records — the crypto ports the sync layer needs from the relay
/// identity (plain Dart; the real adapter lives in `MatrixLedgerTransport`,
/// fakes in `hmac_record_crypto.dart`). No `package:matrix` here.
library;

/// Who signs: an account ([user] MXID), one of its devices ([device]) and
/// that device's Ed25519 fingerprint key ([key], base64).
class SignerId {
  final String user;
  final String device;
  final String key;
  const SignerId({required this.user, required this.device, required this.key});

  Map<String, String> toJson() => {'user': user, 'device': device, 'key': key};

  @override
  bool operator ==(Object other) =>
      other is SignerId &&
      other.user == user &&
      other.device == device &&
      other.key == key;

  @override
  int get hashCode => Object.hash(user, device, key);
}

/// Signs with this device's key and verifies anyone's Ed25519 signature.
abstract interface class RecordCrypto {
  /// This device's signing identity, or null while it can't sign (signed
  /// out / end-to-end encryption not set up yet).
  SignerId? get identity;

  /// Base64 Ed25519 signature of the (ASCII) [message] by this device.
  /// Throws when [identity] is null.
  Future<String> sign(String message);

  /// Whether [signature] (base64) is a valid signature of [message] by the
  /// Ed25519 public [key] (base64). Never throws.
  bool verify(String key, String message, String signature);
}

/// The homeserver's **current** device list — the first-hand source for
/// binding a (user, device) to its key.
abstract interface class DeviceKeyDirectory {
  /// user → device id → Ed25519 key (base64) for the valid (self-signed,
  /// not blocked) devices of [users]. Users the server knows nothing about
  /// are absent. May throw (network).
  Future<Map<String, Map<String, String>>> currentDevices(Set<String> users);
}
