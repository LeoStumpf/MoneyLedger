/// G49: schema v12 → v13. A v12 database is opened by the current
/// AppDatabase: expenses gain the nullable `expense_date` column (NULL for
/// existing rows — their signatures and G27 hashes are unchanged), refused
/// *expense* versions are forgotten (a pre-G49 build refused signed versions
/// carrying a `date`), other refusals stay, and dated writes work.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/expense_model.dart';

const _bool = 'INTEGER NOT NULL DEFAULT 0 CHECK';
const _v12Schema = [
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
      "'{\"user\":\"@a:x\",\"device\":\"D\",\"key\":\"K\",\"sig\":\"S\"}', 0, NULL)",
  "INSERT INTO members VALUES ('g1', '@a:x', 'Ann', '@a:x', 'active', 900, "
      "NULL, 0)",
  "INSERT INTO expenses VALUES ('e1', 'g1', NULL, 'Dinner', 400, 'EUR', "
      "'@a:x', '{\"@a:x\":400}', 1, 500, 0, NULL, NULL, 0, 'food', NULL, NULL)",
  "INSERT INTO settlements VALUES ('s1', 'g1', NULL, 100, 'EUR', '@a:x', "
      "'p2', 2, 600, 1, NULL, NULL, 0, NULL)",
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
      "('g1', 'member', 's9', 80, 'unsigned', '@m:x', NULL, 4, 'ef01')",
  'PRAGMA user_version = 12',
];

void main() {
  test('v12 → v13 adds expense_date and forgets expense refusals', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final stmt in _v12Schema) {
            raw.execute(stmt);
          }
        },
      ),
    );
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(13));

    final dao = ExpensesDao(db);
    final e = (await dao.getExpenseById('e1'))!;
    expect(e.date, isNull);
    expect(e.category, 'food');
    // The stored expense's hash is the one a pre-G49 peer computes.
    const legacy = ExpenseModel(
      id: 'e1',
      roomId: 'g1',
      description: 'Dinner',
      amountCents: 400,
      currency: 'EUR',
      paidBy: '@a:x',
      splitsJson: '{"@a:x":400}',
      createdAt: 1,
      updatedAt: 500,
      category: 'food',
    );
    expect(computeExpenseVersionHash(e), computeExpenseVersionHash(legacy));

    final signing = SigningDao(db);
    expect(await signing.rejectedClock('g1', 'expense', 'e9'), isNull);
    // v19 (G57 / G74) forgets member refusals too.
    expect(await signing.rejectedClock('g1', 'member', 's9'), isNull);

    // v13 writes with a date work and round-trip.
    await dao.upsertExpenseLww(
      expenseCompanion(
        const ExpenseModel(
          id: 'e2',
          roomId: 'g1',
          description: 'Lunch',
          amountCents: 300,
          currency: 'EUR',
          paidBy: '@a:x',
          splitsJson: '{"@a:x":300}',
          createdAt: 2,
          updatedAt: 700,
          date: '2026-10-10',
        ),
      ),
    );
    final e2 = (await dao.getExpenseById('e2'))!;
    expect(e2.date, '2026-10-10');
    expect(e2.versionHash, computeExpenseVersionHash(e2));
  });

  test('a fresh v13 database has the column too', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final cols = await db
        .customSelect("SELECT name FROM pragma_table_info('expenses')")
        .get();
    expect(cols.map((r) => r.read<String>('name')), contains('expense_date'));
  });
}
