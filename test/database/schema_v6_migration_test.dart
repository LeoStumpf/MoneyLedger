/// G6: schema v5 → v6 migration. A v5 database (exact pre-G6 table layout,
/// `user_version = 5`) with rows is opened by the current AppDatabase: the
/// signature columns and the two new tables appear, existing rows survive
/// as grandfathered legacy rows (`sig` NULL, not pending), and v6 writes work.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/sync/record_verifier.dart';

const _v5Schema = [
  "CREATE TABLE groups (room_id TEXT NOT NULL, name TEXT NOT NULL, "
      "currency TEXT NOT NULL DEFAULT 'EUR', "
      "updated_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (room_id))",
  "CREATE TABLE expenses (id TEXT NOT NULL, room_id TEXT NOT NULL, "
      "matrix_event_id TEXT NULL, description TEXT NOT NULL, "
      "amount_cents INTEGER NOT NULL, currency TEXT NOT NULL, "
      "paid_by TEXT NOT NULL, splits_json TEXT NOT NULL, "
      "created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL DEFAULT 0, "
      "deleted INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0, 1)), "
      "PRIMARY KEY (id))",
  "CREATE TABLE settlements (id TEXT NOT NULL, room_id TEXT NOT NULL, "
      "matrix_event_id TEXT NULL, amount_cents INTEGER NOT NULL, "
      "currency TEXT NOT NULL, from_user TEXT NOT NULL, to_user TEXT NOT NULL, "
      "created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL DEFAULT 0, "
      "deleted INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0, 1)), "
      "PRIMARY KEY (id))",
  "CREATE TABLE members (group_id TEXT NOT NULL, user_id TEXT NOT NULL, "
      "display_name TEXT NOT NULL DEFAULT '', matrix_id TEXT NULL, "
      "status TEXT NOT NULL DEFAULT 'active', updated_at INTEGER NOT NULL, "
      "PRIMARY KEY (group_id, user_id))",
  "CREATE TABLE peer_sync_states (group_id TEXT NOT NULL, "
      "user_id TEXT NOT NULL, last_in_sync_at INTEGER NOT NULL DEFAULT 0, "
      "last_digest_sent_at INTEGER NOT NULL DEFAULT 0, "
      "PRIMARY KEY (group_id, user_id))",
  "CREATE TABLE app_settings (key TEXT NOT NULL, value TEXT NOT NULL, "
      "PRIMARY KEY (key))",
  "INSERT INTO groups VALUES ('g1', 'Trip', 'EUR', 10)",
  "INSERT INTO members VALUES ('g1', '@a:x', 'Alex', '@a:x', 'active', 10)",
  "INSERT INTO expenses VALUES ('e1', 'g1', NULL, 'Dinner', 4200, 'EUR', "
      "'@a:x', '{\"@a:x\":4200}', 20, 20, 0)",
  "INSERT INTO settlements VALUES ('s1', 'g1', NULL, 100, 'EUR', '@a:x', "
      "'p2', 30, 30, 0)",
  'PRAGMA user_version = 5',
];

void main() {
  test('v5 → v6 keeps every row as legacy and adds the G6 schema', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final stmt in _v5Schema) {
            raw.execute(stmt);
          }
        },
      ),
    );
    addTearDown(db.close);
    expect(db.schemaVersion, 7); // v5 → v6 → v7 (G16)

    final group = await GroupsDao(db).getGroup('g1');
    expect(group!.name, 'Trip');
    expect(group.sig, isNull);
    expect(group.pendingSign, isFalse);

    final member = (await MembersDao(db).getMembers('g1')).single;
    expect(member.displayName, 'Alex');
    expect(member.sig, isNull);

    final expenses = ExpensesDao(db);
    final e = await expenses.getExpenseById('e1');
    expect(e!.description, 'Dinner');
    expect(e.sig, isNull);
    expect(e.origin, isNull);
    expect(e.pendingSign, isFalse);
    expect(signatureStatus(e.sig, const []).status, SigStatus.legacy);
    final s = await expenses.getSettlementById('s1');
    expect(s!.amountCents, 100);
    expect(s.sig, isNull);

    // The new tables exist and work.
    final signing = SigningDao(db);
    await signing.pinServerKeys({
      '@a:x': {'D1': 'K1'},
    });
    expect((await signing.keysFor('@a:x', 'D1')).single.isServer, isTrue);
    await signing.recordRejected(
      const RefusedVersion(
        groupId: 'g1',
        kind: 'expense',
        recordId: 'e1',
        updatedAt: 99,
        reason: 'unsigned',
        relayedBy: '@b:x',
      ),
    );
    expect(await signing.rejectedClock('g1', 'expense', 'e1'), 99);

    // purgeGroup clears refused versions too.
    await db.purgeGroup('g1');
    expect(await signing.rejectedClock('g1', 'expense', 'e1'), isNull);
    expect(await signing.keysFor('@a:x', 'D1'), isNotEmpty);
  });
}
