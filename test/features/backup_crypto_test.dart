/// Encrypted backups (G34): Argon2id + AES-256-GCM wrapper around the plain
/// backup JSON — round trip, wrong passphrase, tampering, stored parameters,
/// and that plaintext backups are still recognised as such.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/backup/backup_crypto.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';

// Cheap parameters for the bulk of the tests (the standard cost is covered
// by one test below).
const fast = BackupKdfParams(memoryKib: 64, iterations: 1, parallelism: 1);

final plain = buildBackupJson(
  account: '@me:x',
  exportedAt: 1760000000000,
  groups: const [],
);

Map<String, dynamic> decode(String s) => jsonDecode(s) as Map<String, dynamic>;

void main() {
  test('round trip with the standard parameters', () async {
    final enc = await encryptBackup(plain, 'correct horse battery');
    expect(isEncryptedBackup(enc), isTrue);
    expect(enc, isNot(contains('@me:x')));
    expect(await decryptBackup(enc, 'correct horse battery'), plain);
    // The decrypted text is an ordinary backup.
    expect(
      parseBackup(await decryptBackup(enc, 'correct horse battery')).account,
      '@me:x',
    );
  });

  test('the file stores every parameter needed to decrypt it', () async {
    final enc = await encryptBackup(plain, 'pw', params: fast);
    final root = decode(enc);
    expect(root['format'], encryptedBackupFormat);
    expect(root['version'], encryptedBackupVersion);
    expect(root['kdf'], {
      'name': 'argon2id',
      'memory_kib': 64,
      'iterations': 1,
      'parallelism': 1,
      'salt': isA<String>(),
    });
    expect(base64Decode(root['kdf']['salt'] as String), hasLength(16));
    expect(root['cipher']['name'], 'aes-256-gcm');
    expect(base64Decode(root['cipher']['nonce'] as String), hasLength(12));
    // Decrypting uses the file's parameters, not the current defaults.
    expect(await decryptBackup(enc, 'pw'), plain);
    // Standard parameters are recorded too.
    final std = decode(await encryptBackup(plain, 'pw'));
    expect(std['kdf']['memory_kib'], BackupKdfParams.standard.memoryKib);
    expect(std['kdf']['iterations'], BackupKdfParams.standard.iterations);
  });

  test('fresh salt and nonce per file', () async {
    final a = decode(await encryptBackup(plain, 'pw', params: fast));
    final b = decode(await encryptBackup(plain, 'pw', params: fast));
    expect(a['kdf']['salt'], isNot(b['kdf']['salt']));
    expect(a['cipher']['nonce'], isNot(b['cipher']['nonce']));
    expect(a['ciphertext'], isNot(b['ciphertext']));
  });

  test('a wrong passphrase is reported as such', () async {
    final enc = await encryptBackup(plain, 'right', params: fast);
    await expectLater(
      decryptBackup(enc, 'wrong'),
      throwsA(isA<WrongPassphraseException>()),
    );
    // …and the right one still works afterwards (retry).
    expect(await decryptBackup(enc, 'right'), plain);
  });

  test('a tampered ciphertext fails authentication', () async {
    final root = decode(await encryptBackup(plain, 'pw', params: fast));
    final bytes = base64Decode(root['ciphertext'] as String);
    bytes[3] ^= 0x01;
    root['ciphertext'] = base64Encode(bytes);
    await expectLater(
      decryptBackup(jsonEncode(root), 'pw'),
      throwsA(isA<WrongPassphraseException>()),
    );
  });

  test('a tampered header (parameters) fails too', () async {
    final root = decode(await encryptBackup(plain, 'pw', params: fast));
    root['cipher']['nonce'] = base64Encode(List.filled(12, 7));
    await expectLater(
      decryptBackup(jsonEncode(root), 'pw'),
      throwsA(isA<WrongPassphraseException>()),
    );
  });

  test('re-indenting the file does not break it', () async {
    final enc = await encryptBackup(plain, 'pw', params: fast);
    final compact = jsonEncode(decode(enc));
    expect(await decryptBackup(compact, 'pw'), plain);
  });

  test('absurd parameters and unknown algorithms are rejected', () async {
    final root = decode(await encryptBackup(plain, 'pw', params: fast));
    Future<void> rejects(void Function(Map<String, dynamic>) change) async {
      final copy = decode(jsonEncode(root));
      change(copy);
      await expectLater(
        decryptBackup(jsonEncode(copy), 'pw'),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.kind,
            'kind',
            BackupErrorKind.malformed,
          ),
        ),
      );
    }

    await rejects((r) => r['kdf']['memory_kib'] = 1 << 30);
    await rejects((r) => r['kdf']['iterations'] = 1000);
    await rejects((r) => r['kdf']['name'] = 'pbkdf2');
    await rejects((r) => r['cipher']['name'] = 'rot13');
    await rejects((r) => r.remove('ciphertext'));
  });

  test('a newer wrapper version asks for an app update', () async {
    final root = decode(await encryptBackup(plain, 'pw', params: fast));
    root['version'] = encryptedBackupVersion + 1;
    await expectLater(
      decryptBackup(jsonEncode(root), 'pw'),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.kind,
          'kind',
          BackupErrorKind.newerVersion,
        ),
      ),
    );
  });

  test('plaintext backups and other files are not "encrypted"', () {
    expect(isEncryptedBackup(plain), isFalse);
    expect(parseBackup(plain).groups, isEmpty); // still imports
    expect(isEncryptedBackup('Date,Description\n'), isFalse);
    expect(isEncryptedBackup(''), isFalse);
    expect(
      isEncryptedBackup('{"format": "moneyledger-backup-encrypted"'),
      isFalse,
    );
  });

  test('an empty passphrase is not allowed for encryption', () async {
    expect(() => encryptBackup(plain, ''), throwsArgumentError);
  });

  test('injected randomness makes the output deterministic', () async {
    final a = await encryptBackup(plain, 'pw', params: fast, random: Random(1));
    final b = await encryptBackup(plain, 'pw', params: fast, random: Random(1));
    expect(a, b);
  });

  test('passphrase strength hint', () {
    expect(passphraseStrength(''), PassphraseStrength.empty);
    expect(passphraseStrength('abc'), PassphraseStrength.weak);
    expect(passphraseStrength('password'), PassphraseStrength.weak);
    expect(passphraseStrength('Passw0rd!'), PassphraseStrength.fair);
    expect(passphraseStrength('longerpassphrase'), PassphraseStrength.fair);
    expect(passphraseStrength('Tr0ub4dor&3xyz'), PassphraseStrength.strong);
    expect(
      passphraseStrength('correct horse battery staple'),
      PassphraseStrength.strong,
    );
  });
}
