/// G18 review: schema v8 → v9 scopes device-key attestations to a group
/// (`known_device_keys.attested_group`, part of the primary key) and records
/// the exact refused version (`rejected_versions.version_hash`). The old
/// account-wide attestations are dropped; first-hand pins and refusals stay.
library;

// (The refusal fixture is a settlement: the v13 step forgets expense
// refusals — G49.)

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';

const _bool = 'INTEGER NOT NULL DEFAULT 0 CHECK';
const _v8Schema = [
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
      "PRIMARY KEY (user_id, device_id, ed25519_key))",
  "CREATE TABLE rejected_versions (group_id TEXT NOT NULL, "
      "kind TEXT NOT NULL, record_id TEXT NOT NULL, "
      "updated_at INTEGER NOT NULL, reason TEXT NOT NULL, "
      "relayed_by TEXT NOT NULL, claimed_signer TEXT NULL, "
      "rejected_at INTEGER NOT NULL, "
      "PRIMARY KEY (group_id, kind, record_id))",
  "INSERT INTO known_device_keys VALUES "
      "('@a:x', 'D1', 'K1', 'server', NULL, 1)",
  "INSERT INTO known_device_keys VALUES "
      "('@a:x', 'FAKE', 'K2', 'attested', '@m:x', 2)",
  "INSERT INTO rejected_versions VALUES "
      "('g1', 'settlement', 'e1', 70, 'unsigned', '@m:x', NULL, 3)",
  'PRAGMA user_version = 8',
];

void main() {
  test('v8 → v9: attestations dropped (unscopable), server pins and '
      'refusals kept, new columns usable', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final stmt in _v8Schema) {
            raw.execute(stmt);
          }
        },
      ),
    );
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(9));
    final signing = SigningDao(db);

    final keys = await signing.allKeys();
    expect(keys, hasLength(1));
    expect(keys.single.isServer, isTrue);
    expect(keys.single.group, isNull);

    // An unknown hash ('') matches any version at that clock.
    expect(await signing.rejectedVersion('g1', 'settlement', 'e1'), (
      at: 70,
      hash: '',
    ));

    // The same key may now be attested for two groups (new PK column).
    for (final g in ['gA', 'gB']) {
      await signing.pinAttestedKeys(
        {
          '@b:x': {'D9': 'K9'},
        },
        '@c:x',
        group: g,
      );
    }
    expect(
      (await signing.keysFor('@b:x', 'D9')).map((k) => k.group),
      unorderedEquals(['gA', 'gB']),
    );
    // A first-hand pin of an attested key is its own (unscoped) row.
    await signing.pinServerKeys({
      '@b:x': {'D9': 'K9'},
    });
    expect(
      (await signing.keysFor('@b:x', 'D9')).where((k) => k.isServer),
      hasLength(1),
    );

    // Exact refused versions: the highest one is kept.
    await signing.recordRejected(
      const RefusedVersion(
        groupId: 'g1',
        kind: 'settlement',
        recordId: 'e1',
        updatedAt: 70,
        reason: 'bad_signature',
        relayedBy: '@m:x',
        versionHash: 'ffff',
      ),
    );
    await signing.recordRejected(
      const RefusedVersion(
        groupId: 'g1',
        kind: 'settlement',
        recordId: 'e1',
        updatedAt: 60,
        reason: 'bad_signature',
        relayedBy: '@m:x',
        versionHash: 'aaaa',
      ),
    );
    expect(await signing.rejectedVersion('g1', 'settlement', 'e1'), (
      at: 70,
      hash: 'ffff',
    ));
  });
}
