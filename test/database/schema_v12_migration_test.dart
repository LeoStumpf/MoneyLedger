/// G48: schema v11 → v12. A v11 database is opened by the current
/// AppDatabase: `record_history` (+ its indexes) is created and every stored
/// record gets one `initial` entry — its current version, the base a later
/// reset can go back to.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/sync/record_signing.dart' show RecordKind;
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/features/history/group_history.dart';
import 'package:money_ledger/models/expense_model.dart';

const _bool = 'INTEGER NOT NULL DEFAULT 0 CHECK';
const _v11Schema = [
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
  'PRAGMA user_version = 11',
];

void main() {
  test(
    'v11 → v12 creates record_history with one initial entry per record',
    () async {
      historyClock = () => 4242;
      addTearDown(
        () => historyClock = () => DateTime.now().millisecondsSinceEpoch,
      );
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) {
            for (final stmt in _v11Schema) {
              raw.execute(stmt);
            }
          },
        ),
      );
      addTearDown(db.close);
      expect(db.schemaVersion, greaterThanOrEqualTo(12));

      final h = await HistoryDao(db).entriesForGroup('g1');
      expect(h.map((e) => e.kind).toSet(), {
        RecordKind.meta,
        RecordKind.member,
        RecordKind.expense,
        RecordKind.settlement,
      });
      expect(h.every((e) => e.source == HistorySource.initial), isTrue);
      expect(h.every((e) => e.recordedAt == 4242), isTrue);
      final meta = h.firstWhere((e) => e.kind == RecordKind.meta);
      expect(meta.meta!.sig, isNotNull);
      final ex = h.firstWhere((e) => e.kind == RecordKind.expense);
      expect(ex.expense!.category, 'food');
      final stored = (await ExpensesDao(db).getExpenseById('e1'))!;
      expect(ex.versionHash, computeExpenseVersionHash(stored));
      final st = h.firstWhere((e) => e.kind == RecordKind.settlement);
      expect(st.deleted, isTrue);

      final idx = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'record_history'",
          )
          .get();
      expect(
        idx.map((r) => r.read<String>('name')),
        containsAll(['record_history_group', 'record_history_record']),
      );
    },
  );

  test('G62 (DEV-H repro): edits minutes after the update are an undo '
      'point — the backfill is a base of its own', () async {
    var clock = 4242;
    historyClock = () => clock;
    addTearDown(
      () => historyClock = () => DateTime.now().millisecondsSinceEpoch,
    );
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final stmt in _v11Schema) {
            raw.execute(stmt);
          }
        },
      ),
    );
    addTearDown(db.close);
    final expenses = ExpensesDao(db);
    final stored = (await expenses.getExpenseById('e1'))!;
    // A minute after the update: e1 edited, e2 added (< 10 min apart).
    clock += 60 * 1000;
    await expenses.upsertExpenseLww(
      expenseCompanion(
        ExpenseModel(
          id: 'e1',
          roomId: 'g1',
          description: 'Dinner!',
          amountCents: 400,
          currency: 'EUR',
          paidBy: '@a:x',
          splitsJson: '{"@a:x":400}',
          createdAt: 1,
          updatedAt: 700,
        ),
      ),
    );
    clock += 60 * 1000;
    final e2 = ExpenseModel(
      id: 'e2',
      roomId: 'g1',
      description: 'Taxi',
      amountCents: 200,
      currency: 'EUR',
      paidBy: '@a:x',
      splitsJson: '{"@a:x":200}',
      createdAt: clock,
      updatedAt: clock,
    );
    await expenses.upsertExpenseLww(expenseCompanion(e2));

    final h = await HistoryDao(db).entriesForGroup('g1');
    final batches = changeBatches(h, me: '@a:x');
    expect(batches, hasLength(2));
    expect(batches.last.base, isTrue);
    expect(batches.last.resettable, isFalse);
    final mine = batches.first;
    expect(mine.resettable, isTrue);
    expect((mine.added, mine.changed), (1, 1));

    // Undo from here = the state right after the update.
    final plan = planGroupReset(
      groupId: 'g1',
      beforeId: mine.firstId,
      entries: h,
      expenses: await expenses.getAllExpensesForGroup('g1'),
      settlements: await expenses.getAllSettlementsForGroup('g1'),
      meta: null,
      now: clock + 1,
    );
    expect(plan.reverted, 1);
    expect(plan.removed, 1);
    final back = plan.changes
        .firstWhere((c) => c.effect == ResetEffect.reverted)
        .expense!;
    expect(back.description, stored.description);
  });
}
