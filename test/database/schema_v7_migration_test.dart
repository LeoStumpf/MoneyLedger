/// G16: schema v6 → v7 migration. A v6 database (exact G6 table layout,
/// `user_version = 6`) with rows is opened by the current AppDatabase: the
/// expense `category` / `note` columns appear (NULL for existing rows —
/// their signatures and version hashes are unchanged), refused *expense*
/// versions are forgotten (a pre-G16 build refused signed versions carrying
/// the new fields), other refusals stay, and v7 writes work.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/record_signature.dart';

const _bool = 'INTEGER NOT NULL DEFAULT 0 CHECK';
const _v6Schema = [
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
      "pending_sign $_bool (pending_sign IN (0, 1)), PRIMARY KEY (id))",
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
      "'p1', '{\"p1\":2100,\"p2\":2100}', 20, 20, 0, "
      "'{\"user\":\"@a:x\",\"device\":\"D\",\"key\":\"K\",\"sig\":\"S\"}', "
      "NULL, 0)",
  "INSERT INTO rejected_versions VALUES ('g1', 'expense', 'e2', 50, "
      "'bad_signature', '@b:x', '@b:x', 60)",
  "INSERT INTO rejected_versions VALUES ('g1', 'member', 'p9', 70, "
      "'unsigned', '@b:x', NULL, 80)",
  'PRAGMA user_version = 6',
];

void main() {
  test('v6 → v7 adds category + note and forgets expense refusals', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final stmt in _v6Schema) {
            raw.execute(stmt);
          }
        },
      ),
    );
    addTearDown(db.close);
    expect(db.schemaVersion, 7);

    final expenses = ExpensesDao(db);
    final e = (await expenses.getExpenseById('e1'))!;
    expect(e.description, 'Dinner');
    expect(e.category, isNull);
    expect(e.note, isNull);
    expect(e.sig, isNotNull); // G6 signature kept
    // The stored version's hash is the one a pre-G16 peer computes.
    const pre = ExpenseModel(
      id: 'e1',
      roomId: 'g1',
      description: 'Dinner',
      amountCents: 4200,
      currency: 'EUR',
      paidBy: 'p1',
      splitsJson: '{"p1":2100,"p2":2100}',
      createdAt: 20,
      updatedAt: 20,
    );
    expect(expenseVersionHash(e), expenseVersionHash(pre));

    final signing = SigningDao(db);
    expect(await signing.rejectedClock('g1', 'expense', 'e2'), isNull);
    expect(await signing.rejectedClock('g1', 'member', 'p9'), 70);

    // v7 writes with the new fields work.
    await expenses.upsertExpenseLww(
      expenseCompanion(
        ExpenseModel(
          id: 'e1',
          roomId: 'g1',
          description: 'Dinner',
          amountCents: 4200,
          currency: 'EUR',
          paidBy: 'p1',
          splitsJson: '{"p1":2100,"p2":2100}',
          createdAt: 20,
          updatedAt: 30,
          category: 'food',
          note: 'Tip included',
          sig: RecordSignature.decode(
            '{"user":"@a:x","device":"D","key":"K","sig":"S2"}',
          ),
        ),
      ),
    );
    final updated = (await expenses.getExpenseById('e1'))!;
    expect((updated.category, updated.note), ('food', 'Tip included'));
  });
}
