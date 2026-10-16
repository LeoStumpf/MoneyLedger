import 'package:vodozemac/vodozemac.dart' as vod;

/// Verifies an Ed25519 [signature] (base64) of [message] by the device key
/// [key] (base64) — the check behind every G6 record signature. Needs no
/// Matrix client (only an initialised vodozemac, `vod.init()` in `main()`),
/// so local mode (G40) can verify a restored backup too (G41). Any failure —
/// malformed key / signature, vodozemac not initialised — is "not valid".
bool verifyEd25519(String key, String message, String signature) {
  try {
    vod.Ed25519PublicKey.fromBase64(key).verify(
      message: message,
      signature: vod.Ed25519Signature.fromBase64(signature),
    );
    return true;
  } catch (_) {
    return false;
  }
}
