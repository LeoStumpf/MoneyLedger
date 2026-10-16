import 'dart:convert';

/// One Ed25519 signature over a ledger record version (G6), as carried on the
/// wire (`sig` / `origin`) and stored verbatim in Drift: who signed
/// ([user] = MXID, [device] = Matrix device id), with which key ([key] = the
/// device's base64 Ed25519 fingerprint key) and the base64 signature [sig].
///
/// Relayers pass it on unchanged — a record rebuilt from the database must
/// verify exactly like the original (see `record_signing.dart`).
class RecordSignature {
  final String user;
  final String device;
  final String key;
  final String sig;

  const RecordSignature({
    required this.user,
    required this.device,
    required this.key,
    required this.sig,
  });

  Map<String, String> toJson() => {
    'user': user,
    'device': device,
    'key': key,
    'sig': sig,
  };

  /// Parses a wire/stored signature object; null when absent or malformed
  /// (every field must be a non-empty string).
  static RecordSignature? fromJson(Object? json) {
    if (json is! Map) return null;
    final user = json['user'];
    final device = json['device'];
    final key = json['key'];
    final sig = json['sig'];
    if (user is! String || device is! String || key is! String) return null;
    if (sig is! String) return null;
    if (user.isEmpty || device.isEmpty || key.isEmpty || sig.isEmpty) {
      return null;
    }
    return RecordSignature(user: user, device: device, key: key, sig: sig);
  }

  /// The Drift column encoding (JSON text).
  String encode() => jsonEncode(toJson());

  /// Inverse of [encode]; null for a NULL / malformed column.
  static RecordSignature? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      return fromJson(jsonDecode(text));
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RecordSignature &&
      other.user == user &&
      other.device == device &&
      other.key == key &&
      other.sig == sig;

  @override
  int get hashCode => Object.hash(user, device, key, sig);

  @override
  String toString() => 'RecordSignature($user/$device)';
}
