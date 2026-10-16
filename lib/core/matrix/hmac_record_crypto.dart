import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'record_crypto.dart';

/// A **stand-in** for Ed25519 device keys, for the offline demo and the
/// tests (G6) — NOT a real signature scheme. Each fake device gets a random
/// secret; its "public key" is a hash of the secret, and a "signature" is an
/// HMAC-SHA256 under the secret. [verify] resolves the public key to its
/// secret through this registry, which only the owner of the fake network
/// holds — so, like Ed25519, nobody can sign for a device without its secret.
///
/// The registry also plays the homeserver's device list
/// ([DeviceKeyDirectory]): [deviceCrypto] registers a device there,
/// [removeDevice] models a sign-out (the device vanishes from the directory,
/// its old signatures still verify against the key).
class HmacKeyRegistry implements DeviceKeyDirectory {
  final Random _random = Random.secure();
  final Map<String, List<int>> _secretByKey = {};
  final Map<String, Map<String, String>> _directory = {};
  final Map<String, HmacRecordCrypto> _cryptoByDevice = {};

  /// The signer for [device] of [user], registered in the directory (created
  /// on first use; the same instance afterwards).
  HmacRecordCrypto deviceCrypto(String user, String device) =>
      _cryptoByDevice.putIfAbsent('$user|$device', () {
        final c = _newCrypto(user, device);
        (_directory[user] ??= {})[device] = c.identity!.key;
        return c;
      });

  /// A signer claiming [device] of [user] that the directory never lists —
  /// a fabricated device (or one that signed out before anyone saw it).
  HmacRecordCrypto unlistedCrypto(String user, String device) =>
      _newCrypto(user, device);

  /// Sign-out: [device] disappears from the directory (its key still
  /// verifies old signatures).
  void removeDevice(String user, String device) {
    _directory[user]?.remove(device);
    _cryptoByDevice.remove('$user|$device');
  }

  HmacRecordCrypto _newCrypto(String user, String device) {
    final secret = List<int>.generate(32, (_) => _random.nextInt(256));
    final key = 'hmac:${base64.encode(sha256.convert(secret).bytes)}';
    _secretByKey[key] = secret;
    return HmacRecordCrypto._(
      this,
      SignerId(user: user, device: device, key: key),
      secret,
    );
  }

  bool _verify(String key, String message, String signature) {
    final secret = _secretByKey[key];
    if (secret == null) return false;
    final expected = base64.encode(
      Hmac(sha256, secret).convert(utf8.encode(message)).bytes,
    );
    return expected == signature;
  }

  @override
  Future<Map<String, Map<String, String>>> currentDevices(
    Set<String> users,
  ) async => {
    for (final u in users)
      if (_directory[u] case final devices? when devices.isNotEmpty)
        u: Map.of(devices),
  };
}

/// One fake device's signer (see [HmacKeyRegistry]).
class HmacRecordCrypto implements RecordCrypto {
  HmacRecordCrypto._(this._registry, this._identity, this._secret);

  final HmacKeyRegistry _registry;
  final SignerId _identity;
  final List<int> _secret;

  /// When false, behaves like a device whose encryption isn't ready yet:
  /// [identity] is null and [sign] throws.
  bool ready = true;

  @override
  SignerId? get identity => ready ? _identity : null;

  @override
  Future<String> sign(String message) async {
    if (!ready) throw StateError('signer not ready');
    return base64.encode(
      Hmac(sha256, _secret).convert(utf8.encode(message)).bytes,
    );
  }

  @override
  bool verify(String key, String message, String signature) =>
      _registry._verify(key, message, signature);
}
