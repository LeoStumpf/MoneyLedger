/// G37: schema v7 → v8 caches the G27 content hash per expense / settlement
/// (`version_hash`) — existing rows are hashed once by the migration, every
/// LWW upsert stores the hash of what it wrote, and readers use it instead of
/// re-hashing (a 5k-record digest took ~540 ms on a Pixel).
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/expense_model.dart';

import '../helpers/in_memory_database.dart';

const _bool = 'INTEGER NOT NULL DEFAULT 0 CHECK';
const _v7Schema = [
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
      "note TEXT NULL, PRIMARY KEY (id))",
  "CREATE TABLE settlements (id TEXT NOT NULL, room_id TEXT NOT NULL, "
      "matrix_event_id TEXT NULL, amount_cents INTEGER NOT NULL, "
      "currency TEXT NOT NULL, from_user TEXT NOT NULL, to_user TEXT NOT NULL, "
      "created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL DEFAULT 0, "
      "deleted $_bool (deleted IN (0, 1)), sig TEXT NULL, origin TEXT NULL, "
      "pending_sign $_bool (pending_sign IN (0, 1)), PRIMARY KEY (id))",
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
  "INSERT INTO groups VALUES ('g1', 'Trip', 'EUR', 10, NULL, 0)",
  "INSERT INTO expenses VALUES ('e1', 'g1', NULL, 'Dinner', 4200, 'EUR', "
      "'p1', '{\"p1\":2100,\"p2\":2100}', 20, 20, 0, NULL, NULL, 0, "
      "'food', 'Tip')",
  "INSERT INTO settlements VALUES ('s1', 'g1', NULL, 500, 'EUR', 'p2', "
      "'p1', 30, 31, 0, NULL, NULL, 0)",
  'PRAGMA user_version = 7',
];

const _e1 = ExpenseModel(
  id: 'e1',
  roomId: 'g1',
  description: 'Dinner',
  amountCents: 4200,
  currency: 'EUR',
  paidBy: 'p1',
  splitsJson: '{"p1":2100,"p2":2100}',
  createdAt: 20,
  updatedAt: 20,
  category: 'food',
  note: 'Tip',
);

void main() {
  test('v7 → v8 hashes the existing rows once', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final stmt in _v7Schema) {
            raw.execute(stmt);
          }
        },
      ),
    );
    addTearDown(db.close);
    expect(db.schemaVersion, 8);

    final dao = ExpensesDao(db);
    final e = (await dao.getExpenseById('e1'))!;
    expect(e.versionHash, computeExpenseVersionHash(_e1));
    expect(expenseVersionHash(e), computeExpenseVersionHash(_e1));
    final s = (await dao.getSettlementById('s1'))!;
    expect(s.versionHash, isNotNull);
    expect(s.versionHash, computeSettlementVersionHash(s));
  });

  group('DAO keeps the cached hash in step with the content', () {
    late AppDatabase db;
    late ExpensesDao dao;
    setUp(() {
      db = openTestDatabase();
      dao = ExpensesDao(db);
    });
    tearDown(() => db.close());

    test('every LWW write stores the hash of what it wrote', () async {
      await dao.upsertExpenseLww(expenseCompanion(_e1));
      expect(
        (await dao.getExpenseById('e1'))!.versionHash,
        computeExpenseVersionHash(_e1),
      );
      // An edit (newer clock, new content) replaces it.
      const edited = ExpenseModel(
        id: 'e1',
        roomId: 'g1',
        description: 'Dinner + drinks',
        amountCents: 5000,
        currency: 'EUR',
        paidBy: 'p1',
        splitsJson: '{"p1":2500,"p2":2500}',
        createdAt: 20,
        updatedAt: 40,
      );
      await dao.upsertExpenseLww(expenseCompanion(edited));
      final stored = (await dao.getExpenseById('e1'))!;
      expect(stored.description, 'Dinner + drinks');
      expect(stored.versionHash, computeExpenseVersionHash(edited));
      // A losing (older) version changes nothing.
      await dao.upsertExpenseLww(expenseCompanion(_e1));
      expect(
        (await dao.getExpenseById('e1'))!.versionHash,
        computeExpenseVersionHash(edited),
      );
    });

    test('a partial companion stores no hash (computed on demand)', () async {
      await dao.upsertExpenseLww(expenseCompanion(_e1));
      // No category / note columns: those stay as stored, so the hash of
      // the companion alone would be wrong.
      await dao.upsertExpenseLww(
        const ExpensesCompanion(
          id: Value('e1'),
          roomId: Value('g1'),
          description: Value('Dinner'),
          amountCents: Value(4200),
          currency: Value('EUR'),
          paidBy: Value('p1'),
          splitsJson: Value('{"p1":2100,"p2":2100}'),
          createdAt: Value(20),
          updatedAt: Value(50),
          deleted: Value(false),
        ),
      );
      final row = (await dao.getExpenseById('e1'))!;
      expect(row.versionHash, isNull);
      expect(row.category, 'food');
      expect(expenseVersionHash(row), computeExpenseVersionHash(row));
    });

    test('rows inserted without a hash are backfilled', () async {
      await db.into(db.expenses).insert(expenseCompanion(_e1));
      expect((await dao.getExpenseById('e1'))!.versionHash, isNull);
      await backfillVersionHashes(db);
      expect(
        (await dao.getExpenseById('e1'))!.versionHash,
        computeExpenseVersionHash(_e1),
      );
    });
  });
}
