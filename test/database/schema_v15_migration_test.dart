/// G52: schema v14 → v15. A v14 database is opened by the current
/// AppDatabase: every row survives unchanged (their G27 hashes too — the new
/// `link_author` columns are NULL and outside the hash), no refusal is
/// forgotten, the new `link_channels` / `link_peers` tables exist and are
/// empty, and the migrated schema equals a fresh database's.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/models/link_model.dart';

const _bool = 'INTEGER NOT NULL DEFAULT 0 CHECK';
const _v14Schema = [
  "CREATE TABLE groups (room_id TEXT NOT NULL, name TEXT NOT NULL, "
      "currency TEXT NOT NULL DEFAULT 'EUR', "
      "updated_at INTEGER NOT NULL DEFAULT 0, sig TEXT NULL, "
      "pending_sign $_bool (pending_sign IN (0, 1)), categories_json TEXT NULL, "
      "PRIMARY KEY (room_id))",
  "CREATE TABLE expenses (id TEXT NOT NULL, room_id TEXT NOT NULL, "
      "matrix_event_id TEXT NULL, description TEXT NOT NULL, "
      "amount_cents INTEGER NOT NULL, currency TEXT NOT NULL, "
      "paid_by TEXT NOT NULL, splits_json TEXT NOT NULL, "
      "created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL DEFAULT 0, "
      "deleted $_bool (deleted IN (0, 1)), sig TEXT NULL, origin TEXT NULL, "
      "pending_sign $_bool (pending_sign IN (0, 1)), category TEXT NULL, "
      "note TEXT NULL, version_hash TEXT NULL, expense_date TEXT NULL, "
      "PRIMARY KEY (id))",
  "CREATE TABLE settlements (id TEXT NOT NULL, room_id TEXT NOT NULL, "
      "matrix_event_id TEXT NULL, amount_cents INTEGER NOT NULL, "
      "currency TEXT NOT NULL, from_user TEXT NOT NULL, to_user TEXT NOT NULL, "
      "created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL DEFAULT 0, "
      "deleted $_bool (deleted IN (0, 1)), sig TEXT NULL, origin TEXT NULL, "
      "pending_sign $_bool (pending_sign IN (0, 1)), version_hash TEXT NULL, "
      "settlement_date TEXT NULL, PRIMARY KEY (id))",
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
      "'{\"user\":\"@a:x\",\"device\":\"D\",\"key\":\"K\",\"sig\":\"S\"}', 0, NULL)",
  "INSERT INTO members VALUES ('g1', '@a:x', 'Ann', '@a:x', 'active', 900, "
      "NULL, 0)",
  "INSERT INTO expenses VALUES ('e1', 'g1', NULL, 'Dinner', 400, 'EUR', "
      "'@a:x', '{\"@a:x\":400}', 1, 500, 0, NULL, NULL, 0, 'food', NULL, NULL, "
      "'2025-12-24')",
  "INSERT INTO settlements VALUES ('s1', 'g1', NULL, 100, 'EUR', '@a:x', "
      "'p2', 2, 600, 1, NULL, NULL, 0, NULL, '2026-01-02')",
  "CREATE TABLE record_history (id INTEGER NOT NULL PRIMARY KEY "
      "AUTOINCREMENT, group_id TEXT NOT NULL, kind TEXT NOT NULL, "
      "record_id TEXT NOT NULL, updated_at INTEGER NOT NULL, "
      "version_hash TEXT NOT NULL, content TEXT NOT NULL, "
      "source TEXT NOT NULL, recorded_at INTEGER NOT NULL)",
  'CREATE INDEX record_history_group ON record_history '
      '(group_id, recorded_at)',
  'CREATE INDEX record_history_record ON record_history '
      '(group_id, kind, record_id)',
  "INSERT INTO rejected_versions VALUES "
      "('g1', 'expense', 'e9', 70, 'bad_signature', '@m:x', '@m:x', 3, 'abcd')",
  "INSERT INTO rejected_versions VALUES "
      "('g1', 'settlement', 's9', 80, 'unsigned', '@m:x', NULL, 4, 'ef01')",
  'PRAGMA user_version = 14',
];

AppDatabase _openV14() => AppDatabase.forTesting(
  NativeDatabase.memory(
    setup: (raw) {
      for (final stmt in _v14Schema) {
        raw.execute(stmt);
      }
    },
  ),
);

/// `table → [column name:type:notnull:default:pk]`, for every table.
Future<Map<String, List<String>>> _schemaOf(AppDatabase db) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  return {
    for (final t in tables)
      t.read<String>('name'): [
        for (final c
            in await db
                .customSelect(
                  "SELECT * FROM pragma_table_info('${t.read<String>('name')}') "
                  'ORDER BY name',
                )
                .get())
          '${c.read<String>('name')}:${c.read<String>('type')}:'
              '${c.read<int>('notnull')}:${c.readNullable<String>('dflt_value')}:'
              '${c.read<int>('pk')}',
      ],
  };
}

void main() {
  test('v14 → v15 keeps every row and adds empty link tables', () async {
    final db = _openV14();
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(15));

    final groups = GroupsDao(db);
    final g = (await groups.getGroup('g1'))!;
    expect(g.name, 'Trip');
    expect(g.updatedAt, 1000);
    expect(g.sig, isNotNull);

    final members = await MembersDao(db).getMembers('g1');
    expect(members.single.displayName, 'Ann');
    expect(members.single.matrixId, '@a:x');

    final expenses = ExpensesDao(db);
    final e = (await expenses.getExpenseById('e1'))!;
    expect(e.date, '2025-12-24');
    expect(e.category, 'food');
    final s = (await expenses.getSettlementById('s1'))!;
    expect(s.date, '2026-01-02');
    expect(s.deleted, isTrue);

    // No refusal is forgotten by v15.
    final signing = SigningDao(db);
    expect(await signing.rejectedClock('g1', 'expense', 'e9'), 70);
    expect(await signing.rejectedClock('g1', 'settlement', 's9'), 80);

    // The new columns are NULL for existing rows.
    for (final table in ['groups', 'members', 'expenses', 'settlements']) {
      final rows = await db
          .customSelect('SELECT link_author FROM $table')
          .get();
      expect(rows, isNotEmpty, reason: table);
      expect(
        rows.map((r) => r.readNullable<String>('link_author')),
        everyElement(isNull),
        reason: table,
      );
    }

    // The link tables exist, start empty and work.
    final link = LinkDao(db);
    expect(await link.getAllChannels(), isEmpty);
    expect(await link.getPeers('g1'), isEmpty);
    await link.putChannel(
      const LinkChannelModel(
        groupId: 'g1',
        epoch: 1,
        secret: 's',
        nostrPriv: 'k',
        openedAt: 5,
      ),
    );
    expect((await link.getChannel('g1'))!.parts, 1);
  });

  test('the migrated schema equals a fresh database', () async {
    final migrated = _openV14();
    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(migrated.close);
    addTearDown(fresh.close);
    expect(await _schemaOf(migrated), await _schemaOf(fresh));
  });
}
