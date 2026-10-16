/// G47: schema v10 → v11. A v10 database (exact G18-review-2 layout,
/// `user_version = 10`) is opened by the current AppDatabase: groups gain the
/// nullable `categories_json` column (NULL for existing metas — their
/// signatures and G27 hashes are unchanged), refused *meta* versions are
/// forgotten (a pre-G47 build refused signed metas carrying categories),
/// other refusals stay, and v11 writes with categories work.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/expense_category.dart';
import 'package:money_ledger/models/group_model.dart';

const _bool = 'INTEGER NOT NULL DEFAULT 0 CHECK';
const _v10Schema = [
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
      "PRIMARY KEY (group_id, kind, record_id, updated_at, version_hash))",
  "INSERT INTO groups VALUES ('g1', 'Trip', 'EUR', 1000, "
      "'{\"user\":\"@a:x\",\"device\":\"D\",\"key\":\"K\",\"sig\":\"S\"}', 0)",
  "INSERT INTO rejected_versions VALUES "
      "('g1', 'expense', 'e1', 70, 'unsigned', '@m:x', NULL, 3, 'abcd')",
  "INSERT INTO rejected_versions VALUES "
      "('g1', 'meta', 'g1', 90, 'bad_signature', '@m:x', '@m:x', 4, 'ef01')",
  'PRAGMA user_version = 10',
];

void main() {
  test('v10 → v11 adds categories_json and forgets meta refusals', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final stmt in _v10Schema) {
            raw.execute(stmt);
          }
        },
      ),
    );
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(11));

    final groups = GroupsDao(db);
    final g = (await groups.getGroup('g1'))!;
    expect(g.name, 'Trip');
    expect(g.categories, isEmpty);
    expect(g.sig, isNotNull); // G6 signature kept
    // The stored meta's hash is the one a pre-G47 peer computes.
    expect(
      groupMetaVersionHash(g),
      groupMetaVersionHash(
        const GroupModel(
          roomId: 'g1',
          name: 'Trip',
          currency: 'EUR',
          updatedAt: 1000,
        ),
      ),
    );

    final signing = SigningDao(db);
    expect(await signing.rejectedClock('g1', 'meta', 'g1'), isNull);
    expect(await signing.rejectedClock('g1', 'expense', 'e1'), 70);

    // v11 writes with categories work.
    const dog = CustomCategory(id: 'c:dog', name: 'Dog', icon: 'pets');
    await groups.upsertGroupLww(
      groupCompanion(
        const GroupModel(
          roomId: 'g1',
          name: 'Trip',
          currency: 'EUR',
          updatedAt: 2000,
          categories: [dog],
        ),
      ),
    );
    expect((await groups.getGroup('g1'))!.categories, [dog]);
  });
}
