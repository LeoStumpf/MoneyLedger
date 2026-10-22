/// G73: schema v16 → v17. A v16 database is opened by the current
/// AppDatabase: every group survives with no exchange rates (its G27 hash
/// unchanged — `exchange_rates` is outside the hash while unset), refused
/// **meta** versions are forgotten (a pre-G73 build refused signed metas
/// carrying rates), other refusals stay, and the migrated schema equals a
/// fresh database's.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/group_model.dart';

const _v16Schema = [
  'CREATE TABLE "app_settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, '
      'PRIMARY KEY ("key"))',
  'CREATE TABLE "expenses" ("id" TEXT NOT NULL, "room_id" TEXT NOT NULL, '
      '"matrix_event_id" TEXT NULL, "description" TEXT NOT NULL, '
      '"amount_cents" INTEGER NOT NULL, "currency" TEXT NOT NULL, '
      '"paid_by" TEXT NOT NULL, "splits_json" TEXT NOT NULL, '
      '"created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL DEFAULT 0, '
      '"deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), '
      '"sig" TEXT NULL, "origin" TEXT NULL, "pending_sign" INTEGER NOT NULL '
      'DEFAULT 0 CHECK ("pending_sign" IN (0, 1)), "category" TEXT NULL, '
      '"note" TEXT NULL, "expense_date" TEXT NULL, "version_hash" TEXT NULL, '
      '"link_author" TEXT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "groups" ("room_id" TEXT NOT NULL, "name" TEXT NOT NULL, '
      '"currency" TEXT NOT NULL DEFAULT \'EUR\', "updated_at" INTEGER NOT NULL '
      'DEFAULT 0, "sig" TEXT NULL, "pending_sign" INTEGER NOT NULL DEFAULT 0 '
      'CHECK ("pending_sign" IN (0, 1)), "categories_json" TEXT NULL, '
      '"link_author" TEXT NULL, "link_epoch" INTEGER NULL, '
      '"link_secret" TEXT NULL, "locked_at" INTEGER NULL, '
      'PRIMARY KEY ("room_id"))',
  'CREATE TABLE "known_device_keys" ("user_id" TEXT NOT NULL, '
      '"device_id" TEXT NOT NULL, "ed25519_key" TEXT NOT NULL, '
      '"source" TEXT NOT NULL, "attested_by" TEXT NULL, '
      '"first_seen_at" INTEGER NOT NULL, "attested_group" TEXT NOT NULL '
      'DEFAULT \'\', PRIMARY KEY ("user_id", "device_id", "ed25519_key", '
      '"attested_group"))',
  'CREATE TABLE "link_channels" ("group_id" TEXT NOT NULL, '
      '"epoch" INTEGER NOT NULL, "secret" TEXT NOT NULL, '
      '"my_participant_id" TEXT NULL, "nostr_priv" TEXT NOT NULL, '
      '"last_published_hash" TEXT NULL, "last_published_at" INTEGER NOT NULL '
      'DEFAULT 0, "last_created_at" INTEGER NOT NULL DEFAULT 0, '
      '"parts" INTEGER NOT NULL DEFAULT 1, "opened_at" INTEGER NOT NULL, '
      'PRIMARY KEY ("group_id"))',
  'CREATE TABLE "link_peers" ("group_id" TEXT NOT NULL, '
      '"pubkey" TEXT NOT NULL, "me" TEXT NULL, "event_ids_json" TEXT NOT NULL '
      'DEFAULT \'{}\', "last_created_at" INTEGER NOT NULL DEFAULT 0, '
      '"last_seen_at" INTEGER NOT NULL DEFAULT 0, "snapshot_digest" TEXT NULL, '
      'PRIMARY KEY ("group_id", "pubkey"))',
  'CREATE TABLE "members" ("group_id" TEXT NOT NULL, "user_id" TEXT NOT NULL, '
      '"display_name" TEXT NOT NULL DEFAULT \'\', "matrix_id" TEXT NULL, '
      '"status" TEXT NOT NULL DEFAULT \'active\', "updated_at" INTEGER NOT NULL, '
      '"sig" TEXT NULL, "pending_sign" INTEGER NOT NULL DEFAULT 0 CHECK '
      '("pending_sign" IN (0, 1)), "link_author" TEXT NULL, '
      'PRIMARY KEY ("group_id", "user_id"))',
  'CREATE TABLE "peer_sync_states" ("group_id" TEXT NOT NULL, '
      '"user_id" TEXT NOT NULL, "last_in_sync_at" INTEGER NOT NULL DEFAULT 0, '
      '"last_digest_sent_at" INTEGER NOT NULL DEFAULT 0, '
      'PRIMARY KEY ("group_id", "user_id"))',
  'CREATE TABLE "record_history" ("id" INTEGER NOT NULL PRIMARY KEY '
      'AUTOINCREMENT, "group_id" TEXT NOT NULL, "kind" TEXT NOT NULL, '
      '"record_id" TEXT NOT NULL, "updated_at" INTEGER NOT NULL, '
      '"version_hash" TEXT NOT NULL, "content" TEXT NOT NULL, '
      '"source" TEXT NOT NULL, "recorded_at" INTEGER NOT NULL)',
  'CREATE INDEX record_history_group ON record_history (group_id, recorded_at)',
  'CREATE INDEX record_history_record ON record_history '
      '(group_id, kind, record_id)',
  'CREATE TABLE "rejected_versions" ("group_id" TEXT NOT NULL, '
      '"kind" TEXT NOT NULL, "record_id" TEXT NOT NULL, '
      '"updated_at" INTEGER NOT NULL, "reason" TEXT NOT NULL, '
      '"relayed_by" TEXT NOT NULL, "claimed_signer" TEXT NULL, '
      '"rejected_at" INTEGER NOT NULL, "version_hash" TEXT NOT NULL DEFAULT '
      '\'\', PRIMARY KEY ("group_id", "kind", "record_id", "updated_at", '
      '"version_hash"))',
  'CREATE TABLE "settlements" ("id" TEXT NOT NULL, "room_id" TEXT NOT NULL, '
      '"matrix_event_id" TEXT NULL, "amount_cents" INTEGER NOT NULL, '
      '"currency" TEXT NOT NULL, "from_user" TEXT NOT NULL, '
      '"to_user" TEXT NOT NULL, "created_at" INTEGER NOT NULL, '
      '"updated_at" INTEGER NOT NULL DEFAULT 0, "deleted" INTEGER NOT NULL '
      'DEFAULT 0 CHECK ("deleted" IN (0, 1)), "sig" TEXT NULL, '
      '"origin" TEXT NULL, "pending_sign" INTEGER NOT NULL DEFAULT 0 CHECK '
      '("pending_sign" IN (0, 1)), "settlement_date" TEXT NULL, '
      '"version_hash" TEXT NULL, "link_author" TEXT NULL, PRIMARY KEY ("id"))',
  "INSERT INTO groups VALUES ('g1', 'Trip', 'EUR', 1000, "
      "'{\"user\":\"@a:x\",\"device\":\"D\",\"key\":\"K\",\"sig\":\"S\"}', 0, "
      "NULL, NULL, NULL, NULL, NULL)",
  "INSERT INTO rejected_versions VALUES "
      "('g1', 'meta', 'g1', 70, 'bad_signature', '@m:x', '@m:x', 3, 'abcd')",
  "INSERT INTO rejected_versions VALUES "
      "('g1', 'expense', 'e9', 80, 'unsigned', '@m:x', NULL, 4, 'ef01')",
  'PRAGMA user_version = 16',
];

AppDatabase _openV16() => AppDatabase.forTesting(
  NativeDatabase.memory(
    setup: (raw) {
      for (final stmt in _v16Schema) {
        raw.execute(stmt);
      }
    },
  ),
);

Future<List<String>> _schemaOf(AppDatabase db) async => [
  for (final r
      in await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )
          .get())
    r.read<String>('name'),
  for (final t in [
    'groups',
    'expenses',
    'settlements',
    'members',
    'link_channels',
  ])
    for (final c
        in await db
            .customSelect("SELECT * FROM pragma_table_info('$t') ORDER BY name")
            .get())
      '$t.${c.read<String>('name')}:${c.read<String>('type')}:'
          '${c.read<int>('notnull')}:${c.readNullable<String>('dflt_value')}',
];

void main() {
  test('v16 → v17: groups keep their version, meta refusals are '
      'forgotten', () async {
    final db = _openV16();
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(17));
    final g = (await GroupsDao(db).getGroup('g1'))!;
    expect(g.name, 'Trip');
    expect(g.exchangeRates, isNull);
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
    // v18 (G76, opened at the current version) forgets expense refusals.
    expect(await signing.rejectedClock('g1', 'expense', 'e9'), isNull);
  });

  test('the migrated schema equals a fresh database', () async {
    final migrated = _openV16();
    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(migrated.close);
    addTearDown(fresh.close);
    expect(await _schemaOf(migrated), await _schemaOf(fresh));
  });
}
