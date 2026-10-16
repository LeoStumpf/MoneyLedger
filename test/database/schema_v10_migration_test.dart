/// G18 review 2: schema v9 → v10 makes `rejected_versions` a small set per
/// record — the refused version (clock + hash) joins the primary key, so a
/// lower refused version is no longer forgotten once a higher one is refused
/// (it used to be re-sent by its holder on every digest). Existing refusals
/// are kept.
library;

// (The refusal fixture is a settlement: the v13 step forgets expense
// refusals — G49.)

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';

const _bool = 'INTEGER NOT NULL DEFAULT 0 CHECK';
const _v9Schema = [
  "CREATE TABLE groups (room_id TEXT NOT NULL, name TEXT NOT NULL, "
      "currency TEXT NOT NULL DEFAULT 'EUR', "
      "updated_at INTEGER NOT NULL DEFAULT 0, sig TEXT NULL, "
      "pending_sign $_bool (pending_sign IN (0, 1)), PRIMARY KEY (room_id))",
  "CREATE TABLE expenses (id TEXT NOT NULL, room_id TEXT NOT NULL, "
      "matrix_event_id TEXT NULL, description TEXT NOT NULL, "
      "amount_cents INTEGER NOT NULL, currency TEXT NOT NULL, "
      "paid_by TEXT NOT NULL, splits_json TEXT NOT NULL, "
      "created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL DEFAULT 0, "
      "deleted $_bool (deleted IN (0, 1)), sig TEXT NULL, origin TEXT NULL, "
      "pending_sign $_bool (pending_sign IN (0, 1)), category TEXT NULL, "
      "note TEXT NULL, version_hash TEXT NULL, PRIMARY KEY (id))",
  "CREATE TABLE settlements (id TEXT NOT NULL, room_id TEXT NOT NULL, "
      "matrix_event_id TEXT NULL, amount_cents INTEGER NOT NULL, "
      "currency TEXT NOT NULL, from_user TEXT NOT NULL, to_user TEXT NOT NULL, "
      "created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL DEFAULT 0, "
      "deleted $_bool (deleted IN (0, 1)), sig TEXT NULL, origin TEXT NULL, "
      "pending_sign $_bool (pending_sign IN (0, 1)), version_hash TEXT NULL, "
      "PRIMARY KEY (id))",
  "CREATE TABLE members (group_id TEXT NOT NULL, user_id TEXT NOT NULL, "
      "display_name TEXT NOT NULL DEFAULT '', matrix_id TEXT NULL, "
      "status TEXT NOT NULL DEFAULT 'active', updated_at INTEGER NOT NULL, "
      "sig TEXT NULL, pending_sign $_bool (pending_sign IN (0, 1)), "
      "PRIMARY KEY (group_id, user_id))",
  "CREATE TABLE peer_sync_states (group_id TEXT NOT NULL, "
      "user_id TEXT NOT NULL, last_in_sync_at INTEGER NOT NULL DEFAULT 0, "
      "last_digest_sent_at INTEGER NOT NULL DEFAULT 0, "
      "PRIMARY KEY (group_id, user_id))",
  "CREATE TABLE app_settings (key TEXT NOT NULL, value TEXT NOT NULL, "
      "PRIMARY KEY (key))",
  "CREATE TABLE known_device_keys (user_id TEXT NOT NULL, "
      "device_id TEXT NOT NULL, ed25519_key TEXT NOT NULL, "
      "source TEXT NOT NULL, attested_by TEXT NULL, "
      "first_seen_at INTEGER NOT NULL, "
      "attested_group TEXT NOT NULL DEFAULT '', "
      "PRIMARY KEY (user_id, device_id, ed25519_key, attested_group))",
  "CREATE TABLE rejected_versions (group_id TEXT NOT NULL, "
      "kind TEXT NOT NULL, record_id TEXT NOT NULL, "
      "updated_at INTEGER NOT NULL, reason TEXT NOT NULL, "
      "relayed_by TEXT NOT NULL, claimed_signer TEXT NULL, "
      "rejected_at INTEGER NOT NULL, "
      "version_hash TEXT NOT NULL DEFAULT '', "
      "PRIMARY KEY (group_id, kind, record_id))",
  "INSERT INTO rejected_versions VALUES "
      "('g1', 'settlement', 'e1', 70, 'unsigned', '@m:x', NULL, 3, 'abcd')",
  'PRAGMA user_version = 9',
];

void main() {
  RefusedVersion refused(int at, String hash) => RefusedVersion(
    groupId: 'g1',
    kind: 'settlement',
    recordId: 'e1',
    updatedAt: at,
    reason: 'bad_signature',
    relayedBy: '@m:x',
    versionHash: hash,
  );

  test('v9 → v10: the refusal is kept; a refusal set per record', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final stmt in _v9Schema) {
            raw.execute(stmt);
          }
        },
      ),
    );
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(10));
    final signing = SigningDao(db);
    expect(await signing.rejectedVersion('g1', 'settlement', 'e1'), (
      at: 70,
      hash: 'abcd',
    ));

    // A higher refusal no longer replaces the lower one.
    await signing.recordRejected(refused(90, 'ffff'));
    expect(
      await signing.isRejected('g1', 'settlement', 'e1', (
        at: 70,
        hash: 'abcd',
      )),
      isTrue,
    );
    expect(
      await signing.isRejected('g1', 'settlement', 'e1', (
        at: 90,
        hash: 'ffff',
      )),
      isTrue,
    );
    expect(
      await signing.isRejected('g1', 'settlement', 'e1', (
        at: 90,
        hash: '0000',
      )),
      isFalse,
    );
    expect(await signing.rejectedVersion('g1', 'settlement', 'e1'), (
      at: 90,
      hash: 'ffff',
    ));
    final sets = await signing.rejectedSetsForGroup('g1');
    expect(sets['settlement']!['e1'], [
      (at: 90, hash: 'ffff'),
      (at: 70, hash: 'abcd'),
    ]);

    // Bounded: only the highest kMaxRefusedVersionsPerRecord stay.
    for (var i = 0; i < kMaxRefusedVersionsPerRecord + 2; i++) {
      await signing.recordRejected(refused(100 + i, 'aa$i'));
    }
    final kept = (await signing.rejectedSetsForGroup(
      'g1',
    ))['settlement']!['e1']!;
    expect(kept, hasLength(kMaxRefusedVersionsPerRecord));
    expect(kept.first.at, 100 + kMaxRefusedVersionsPerRecord + 1);
    expect(
      await signing.isRejected('g1', 'settlement', 'e1', (
        at: 70,
        hash: 'abcd',
      )),
      isFalse,
    );

    // A restore clears the refusals up to the version it stored.
    await signing.clearRejectedUpTo('g1', 'settlement', 'e1', (
      at: 103,
      hash: 'aa3',
    ));
    final left = (await signing.rejectedSetsForGroup(
      'g1',
    ))['settlement']!['e1']!;
    expect(left.map((v) => v.at), [105, 104]);
  });
}
