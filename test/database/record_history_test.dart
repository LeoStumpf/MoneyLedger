/// G48: the DAOs' LWW upserts append every **stored, different** version to
/// `record_history` (same transaction), nothing for a re-write of the same
/// version or a losing older one; retention keeps one base per record.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/sync/record_signing.dart' show RecordKind;
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import '../helpers/in_memory_database.dart';

const _day = Duration(days: 1);

ExpenseModel _expense(
  String description, {
  String id = 'e1',
  int at = 500,
  bool deleted = false,
  bool pending = false,
  RecordSignature? sig,
}) => ExpenseModel(
  id: id,
  roomId: 'g1',
  description: description,
  amountCents: 100,
  currency: 'EUR',
  paidBy: '@a:x.org',
  splitsJson: '{"@a:x.org":100}',
  createdAt: 1,
  updatedAt: at,
  deleted: deleted,
  pendingSign: pending,
  sig: sig,
);

const _sig = RecordSignature(user: '@a:x.org', device: 'D', key: 'K', sig: 'S');

void main() {
  late AppDatabase db;
  late ExpensesDao expenses;
  late HistoryDao history;
  var clock = 1000;

  setUp(() {
    db = openTestDatabase();
    expenses = ExpensesDao(db);
    history = HistoryDao(db);
    clock = 1000;
    historyClock = () => clock;
  });
  tearDown(() async {
    historyClock = () => DateTime.now().millisecondsSinceEpoch;
    await db.close();
  });

  test(
    'a new and a changed version are appended, with source and content',
    () async {
      await expenses.upsertExpenseLww(expenseCompanion(_expense('Dinner')));
      clock = 2000;
      await expenses.upsertExpenseLww(
        expenseCompanion(_expense('Lunch', at: 600, sig: _sig)),
        source: HistorySource.inbound,
      );
      final h = await history.entriesForGroup('g1');
      expect(h, hasLength(2));
      expect(h[0].kind, RecordKind.expense);
      expect(h[0].recordId, 'e1');
      expect(h[0].source, HistorySource.local);
      expect(h[0].recordedAt, 1000);
      expect(h[0].expense!.description, 'Dinner');
      expect(h[1].source, HistorySource.inbound);
      expect(h[1].updatedAt, 600);
      expect(h[1].expense!.description, 'Lunch');
      expect(h[1].signer, '@a:x.org');
      expect(h[1].recordedAt, 2000);
      expect(h[1].versionHash, isNotEmpty);
    },
  );

  test('re-writing the same version (signature landing) and an older '
      'version append nothing', () async {
    await expenses.upsertExpenseLww(
      expenseCompanion(_expense('Dinner', pending: true)),
    );
    // pendingSign → signed at the same clock: same version.
    await expenses.upsertExpenseLww(
      expenseCompanion(_expense('Dinner', sig: _sig)),
    );
    // An older version loses LWW.
    await expenses.upsertExpenseLww(expenseCompanion(_expense('Old', at: 100)));
    expect(await history.entriesForGroup('g1'), hasLength(1));
    expect((await expenses.getExpenseById('e1'))!.sig, isNotNull);
  });

  test('a partial companion stores the merged row in the history', () async {
    await expenses.upsertExpenseLww(expenseCompanion(_expense('Dinner')));
    await expenses.upsertExpenseLww(
      // Like the pre-G6 inbound processors: no category / note / signing
      // columns — those keep their stored values.
      const ExpensesCompanion(
        id: Value('e1'),
        roomId: Value('g1'),
        description: Value('Brunch'),
        amountCents: Value(100),
        currency: Value('EUR'),
        paidBy: Value('@a:x.org'),
        splitsJson: Value('{"@a:x.org":100}'),
        createdAt: Value(1),
        updatedAt: Value(700),
      ),
    );
    final last = (await history.entriesForGroup('g1')).last;
    expect(last.expense!.description, 'Brunch');
    expect(last.expense!.amountCents, 100);
    expect(last.updatedAt, 700);
  });

  test('settlements, members and the group meta are recorded too', () async {
    await expenses.upsertSettlementLww(
      settlementCompanion(
        const SettlementModel(
          id: 's1',
          roomId: 'g1',
          amountCents: 50,
          currency: 'EUR',
          fromUser: 'a',
          toUser: 'b',
          createdAt: 1,
          updatedAt: 10,
        ),
      ),
    );
    await MembersDao(db).upsertMemberLww(
      memberCompanion(
        const MemberModel(
          groupId: 'g1',
          userId: 'p1',
          displayName: 'Sam',
          status: 'active',
          updatedAt: 10,
        ),
      ),
    );
    await GroupsDao(db).upsertGroupLww(
      groupCompanion(
        const GroupModel(
          roomId: 'g1',
          name: 'Trip',
          currency: 'EUR',
          updatedAt: 10,
        ),
      ),
    );
    // Same meta again → nothing.
    await GroupsDao(db).upsertGroupLww(
      groupCompanion(
        const GroupModel(
          roomId: 'g1',
          name: 'Trip',
          currency: 'EUR',
          updatedAt: 10,
        ),
      ),
    );
    final h = await history.entriesForGroup('g1');
    expect(h.map((e) => e.kind), [
      RecordKind.settlement,
      RecordKind.member,
      RecordKind.meta,
    ]);
    expect(h[1].member!.displayName, 'Sam');
    expect(h[2].meta!.name, 'Trip');
    expect(h[2].recordId, 'g1');
  });

  test('purging a group drops its history', () async {
    await expenses.upsertExpenseLww(expenseCompanion(_expense('Dinner')));
    await db.purgeGroup('g1');
    expect(await history.entriesForGroup('g1'), isEmpty);
  });

  group('prune', () {
    test('drops old entries but keeps the newest one before the cutoff per '
        'record, and sets the floor', () async {
      final now = DateTime(2026, 10, 16).millisecondsSinceEpoch;
      final old =
          now - (kHistoryRetention + const Duration(days: 10)).inMilliseconds;
      clock = old;
      await expenses.upsertExpenseLww(expenseCompanion(_expense('v1', at: 1)));
      clock = old + _day.inMilliseconds;
      await expenses.upsertExpenseLww(expenseCompanion(_expense('v2', at: 2)));
      // e2 only has an old version → kept (its base).
      await expenses.upsertExpenseLww(
        expenseCompanion(_expense('only', id: 'e2', at: 1)),
      );
      clock = now - _day.inMilliseconds;
      await expenses.upsertExpenseLww(expenseCompanion(_expense('v3', at: 3)));

      expect(await history.prune(now: now), 1);
      final left = await history.entriesForGroup('g1');
      expect(left.map((e) => e.expense!.description), ['v2', 'only', 'v3']);
      expect(await history.floor(), now - kHistoryRetention.inMilliseconds);
      // Idempotent.
      expect(await history.prune(now: now), 0);
    });

    test('over the row cap the cutoff moves forward (bases stay)', () async {
      for (var i = 1; i <= 10; i++) {
        clock = 1000 + i;
        await expenses.upsertExpenseLww(
          expenseCompanion(_expense('v$i', at: i)),
        );
      }
      expect(await history.prune(now: 2000, maxRows: 4), 5);
      final left = await history.entriesForGroup('g1');
      // The 4 newest + v6, the base at the new cutoff.
      expect(left.map((e) => e.expense!.description), [
        'v6',
        'v7',
        'v8',
        'v9',
        'v10',
      ]);
      expect(await history.floor(), 1007);
    });
  });
}
