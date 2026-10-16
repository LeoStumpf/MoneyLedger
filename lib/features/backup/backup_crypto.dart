/// Optional passphrase encryption of a backup file (G34).
///
/// An encrypted backup wraps the plain backup JSON (`ledger_backup.dart`):
///
/// ```json
/// {
///   "format": "moneyledger-backup-encrypted",
///   "version": 1,
///   "kdf": { "name": "argon2id", "memory_kib": 32768, "iterations": 3,
///            "parallelism": 1, "salt": "<base64, 16 bytes>" },
///   "cipher": { "name": "aes-256-gcm", "nonce": "<base64, 12 bytes>" },
///   "ciphertext": "<base64: AES-GCM ciphertext followed by its 16-byte tag>"
/// }
/// ```
///
/// The key is derived with **Argon2id** (memory-hard) from the passphrase and
/// a random salt; the backup JSON is sealed with **AES-256-GCM** (random
/// nonce, authenticated — a wrong passphrase and a modified file both fail
/// the tag check). Every parameter is stored in the file, so later versions
/// can raise the cost and still read old files. The header is bound to the
/// ciphertext as associated data, so it can't be swapped either.
///
/// Library: `cryptography` (Apache-2.0), its **pure-Dart** implementations
/// ([DartArgon2id], [DartAesGcm]) on every platform — identical behaviour on
/// Android and the web, no platform channel. Argon2id yields to the event
/// loop while it works (the spinner keeps turning). Pure Dart, no Flutter.
library;

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'ledger_backup.dart';

/// The `format` marker of an encrypted backup file.
const encryptedBackupFormat = 'moneyledger-backup-encrypted';

/// The newest encrypted-wrapper version this build writes and reads.
const encryptedBackupVersion = 1;

/// Argon2id cost parameters (stored in each file).
class BackupKdfParams {
  /// Memory in KiB.
  final int memoryKib;
  final int iterations;
  final int parallelism;
  const BackupKdfParams({
    required this.memoryKib,
    required this.iterations,
    required this.parallelism,
  });

  /// What new backups use: 32 MiB, 3 passes, 1 lane — above the OWASP
  /// Argon2id minimum (19 MiB, t = 2); measured 0.8 s on a Pixel 4a,
  /// 1.1 s on the emulator, ≈ 2 s as dart2js (see CLAUDE.md "Backup").
  static const standard = BackupKdfParams(
    memoryKib: 32768,
    iterations: 3,
    parallelism: 1,
  );

  /// Upper bounds a file may ask for — a crafted file must not make the app
  /// allocate gigabytes or spin for minutes.
  static const maxMemoryKib = 262144; // 256 MiB
  static const maxIterations = 16;
  static const maxParallelism = 8;

  bool get withinLimits =>
      parallelism >= 1 &&
      parallelism <= maxParallelism &&
      iterations >= 1 &&
      iterations <= maxIterations &&
      memoryKib >= 8 * parallelism &&
      memoryKib <= maxMemoryKib;
}

/// The passphrase was wrong — or the file was modified (AES-GCM can't tell
/// the two apart). The UI asks again.
class WrongPassphraseException implements Exception {
  const WrongPassphraseException();
  @override
  String toString() => 'WrongPassphraseException';
}

/// Whether [text] is an encrypted backup (cheap check, no decryption).
bool isEncryptedBackup(String text) {
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('{')) return false;
  try {
    final root = jsonDecode(trimmed);
    return root is Map && root['format'] == encryptedBackupFormat;
  } on FormatException {
    return false;
  }
}

const _saltLength = 16;
const _nonceLength = 12;

List<int> _random(int n, Random rng) => [
  for (var i = 0; i < n; i++) rng.nextInt(256),
];

/// The associated data: the header (everything but the ciphertext, keys
/// sorted — so re-indenting the file doesn't matter), so the stored
/// parameters are authenticated along with the content.
List<int> _aad(Map<String, Object?> header) => utf8.encode(
  jsonEncode(
    _sorted({
      'format': header['format'],
      'version': header['version'],
      'kdf': header['kdf'],
      'cipher': header['cipher'],
    }),
  ),
);

Object? _sorted(Object? v) => v is Map
    ? {
        for (final k in (v.keys.map((k) => '$k').toList()..sort()))
          k: _sorted(v[k]),
      }
    : v;

Future<SecretKey> _deriveKey(
  String passphrase,
  List<int> salt,
  BackupKdfParams p,
) => DartArgon2id(
  memory: p.memoryKib,
  iterations: p.iterations,
  parallelism: p.parallelism,
  hashLength: 32,
).deriveKeyFromPassword(password: passphrase, nonce: salt);

/// Encrypts the backup JSON [plain] with [passphrase] (must not be empty).
/// [random] is injectable for tests; the default is a secure RNG.
Future<String> encryptBackup(
  String plain,
  String passphrase, {
  BackupKdfParams params = BackupKdfParams.standard,
  Random? random,
}) async {
  if (passphrase.isEmpty) {
    throw ArgumentError.value(passphrase, 'passphrase', 'must not be empty');
  }
  final rng = random ?? Random.secure();
  final salt = _random(_saltLength, rng);
  final nonce = _random(_nonceLength, rng);
  final header = <String, Object?>{
    'format': encryptedBackupFormat,
    'version': encryptedBackupVersion,
    'kdf': {
      'name': 'argon2id',
      'memory_kib': params.memoryKib,
      'iterations': params.iterations,
      'parallelism': params.parallelism,
      'salt': base64Encode(salt),
    },
    'cipher': {'name': 'aes-256-gcm', 'nonce': base64Encode(nonce)},
  };
  final key = await _deriveKey(passphrase, salt, params);
  final box = await DartAesGcm.with256bits().encrypt(
    utf8.encode(plain),
    secretKey: key,
    nonce: nonce,
    aad: _aad(header),
  );
  return const JsonEncoder.withIndent('  ').convert({
    ...header,
    'ciphertext': base64Encode([...box.cipherText, ...box.mac.bytes]),
  });
}

/// Decrypts an encrypted backup [text] → the plain backup JSON.
///
/// Throws [WrongPassphraseException] for a wrong passphrase or a modified
/// file, and [BackupFormatException] for a file that isn't an encrypted
/// backup, a newer wrapper version, or unsupported / out-of-range
/// parameters.
Future<String> decryptBackup(String text, String passphrase) async {
  Never bad(String why) =>
      throw BackupFormatException(BackupErrorKind.malformed, why);
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException catch (e) {
    throw BackupFormatException(BackupErrorKind.notABackup, e.message);
  }
  if (root is! Map || root['format'] != encryptedBackupFormat) {
    throw const BackupFormatException(
      BackupErrorKind.notABackup,
      'not an encrypted backup',
    );
  }
  final version = root['version'];
  if (version is! int || version < 1) bad('invalid version: $version');
  if (version > encryptedBackupVersion) {
    throw BackupFormatException(
      BackupErrorKind.newerVersion,
      'encrypted version $version > $encryptedBackupVersion',
      version: version,
    );
  }
  final kdf = root['kdf'];
  final cipher = root['cipher'];
  final ct = root['ciphertext'];
  if (kdf is! Map || kdf['name'] != 'argon2id') bad('unsupported kdf');
  if (cipher is! Map || cipher['name'] != 'aes-256-gcm') {
    bad('unsupported cipher');
  }
  if (ct is! String) bad('missing ciphertext');
  final m = kdf['memory_kib'], t = kdf['iterations'], p = kdf['parallelism'];
  if (m is! int || t is! int || p is! int) bad('invalid kdf parameters');
  final params = BackupKdfParams(memoryKib: m, iterations: t, parallelism: p);
  if (!params.withinLimits) bad('kdf parameters out of range');
  final List<int> salt, nonce, sealed;
  try {
    salt = base64Decode(kdf['salt'] as String);
    nonce = base64Decode(cipher['nonce'] as String);
    sealed = base64Decode(ct);
  } catch (_) {
    bad('invalid base64');
  }
  if (salt.length < 8) bad('salt too short');
  if (nonce.length != _nonceLength) bad('invalid nonce');
  if (sealed.length < 16) bad('ciphertext too short');
  final key = await _deriveKey(passphrase, salt, params);
  try {
    final clear = await DartAesGcm.with256bits().decrypt(
      SecretBox(
        sealed.sublist(0, sealed.length - 16),
        nonce: nonce,
        mac: Mac(sealed.sublist(sealed.length - 16)),
      ),
      secretKey: key,
      aad: _aad(Map<String, Object?>.from(root)),
    );
    return utf8.decode(clear);
  } on SecretBoxAuthenticationError {
    throw const WrongPassphraseException();
  } on FormatException {
    // Authenticated but not UTF-8 — can't happen for our own files.
    bad('content is not text');
  }
}

/// A rough passphrase strength for the export dialog's hint (not a security
/// guarantee — Argon2id is what makes guessing expensive).
enum PassphraseStrength { empty, weak, fair, strong }

PassphraseStrength passphraseStrength(String s) {
  if (s.isEmpty) return PassphraseStrength.empty;
  var classes = 0;
  if (RegExp(r'[a-z]').hasMatch(s)) classes++;
  if (RegExp(r'[A-Z]').hasMatch(s)) classes++;
  if (RegExp(r'[0-9]').hasMatch(s)) classes++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(s)) classes++;
  final words = s.trim().split(RegExp(r'\s+')).length;
  if (s.length >= 20 || (words >= 4 && s.length >= 16)) {
    return PassphraseStrength.strong;
  }
  if (s.length >= 12 && classes >= 3) return PassphraseStrength.strong;
  if (s.length >= 10 || (s.length >= 8 && classes >= 3)) {
    return PassphraseStrength.fair;
  }
  return PassphraseStrength.weak;
}
