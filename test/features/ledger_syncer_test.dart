/// Tests for LedgerSyncer's static processing methods.
/// No package:matrix import — methods take plain Dart types only.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/models/expense_model.dart';

import '../helpers/in_memory_database.dart';

void main() {
  late AppDatabase db;
  late ExpensesDao expDao;
  late GroupsDao groupDao;
  late MembersDao memberDao;

  setUp(() {
    db = openTestDatabase();
    expDao = ExpensesDao(db);
    groupDao = GroupsDao(db);
    memberDao = MembersDao(db);
  });

  tearDown(() => db.close());

  group('LedgerSyncer.processExpense', () {
    test('writes expense row to DB', () async {
      LedgerSyncer.processExpense({
        'id': 'uuid-1',
        'group': 'g1',
        'description': 'Pizza',
        'amount': 3000,
        'currency': 'EUR',
        'paid_by': '@alice:m.org',
        'split': {'@alice:m.org': 1500, '@bob:m.org': 1500},
        'created_at': 1000000,
      }, expDao);

      final rows = await expDao.watchExpensesForRoom('g1').first;
      expect(rows.length, 1);
      expect(rows.first.id, 'uuid-1');
      expect(rows.first.description, 'Pizza');
      expect(rows.first.amountCents, 3000);
      expect(rows.first.paidBy, '@alice:m.org');
      expect(rows.first.createdAt, 1000000);
    });

    test('missing id or group — no row written', () async {
      LedgerSyncer.processExpense({'description': 'No id'}, expDao);
      LedgerSyncer.processExpense({'id': 'x', 'description': 'No group'}, expDao);
      final rows = await expDao.watchExpensesForRoom('g1').first;
      expect(rows, isEmpty);
    });

    test('calling twice with same id is idempotent', () async {
      final content = {
        'id': 'uuid-1',
        'group': 'g1',
        'description': 'Pizza',
        'amount': 3000,
        'currency': 'EUR',
        'paid_by': '@alice:m.org',
        'split': <String, int>{},
        'created_at': 0,
      };
      LedgerSyncer.processExpense(content, expDao);
      LedgerSyncer.processExpense(content, expDao);
      final rows = await expDao.watchExpensesForRoom('g1').first;
      expect(rows.length, 1);
    });
  });

  group('LedgerSyncer.processSettlement', () {
    test('writes settlement row to DB', () async {
      LedgerSyncer.processSettlement({
        'id': 'settle-1',
        'group': 'g1',
        'amount': 1500,
        'currency': 'EUR',
        'from': '@bob:m.org',
        'to': '@alice:m.org',
        'created_at': 2000000,
      }, expDao);

      final rows = await expDao.watchSettlementsForRoom('g1').first;
      expect(rows.length, 1);
      expect(rows.first.id, 'settle-1');
      expect(rows.first.amountCents, 1500);
      expect(rows.first.fromUser, '@bob:m.org');
      expect(rows.first.toUser, '@alice:m.org');
    });

    test('missing id — no row written', () async {
      LedgerSyncer.processSettlement({'group': 'g1', 'amount': 100}, expDao);
      final rows = await expDao.watchSettlementsForRoom('g1').first;
      expect(rows, isEmpty);
    });
  });

  group('LedgerSyncer.processGroupMeta', () {
    test('writes group row to DB', () async {
      LedgerSyncer.processGroupMeta(
          {'group': 'g1', 'name': 'Alpine Hut', 'currency': 'CHF'}, groupDao);
      final groups = await groupDao.watchAllGroups().first;
      expect(groups.length, 1);
      expect(groups.first.roomId, 'g1');
      expect(groups.first.name, 'Alpine Hut');
      expect(groups.first.currency, 'CHF');
    });

    test('missing currency falls back to EUR', () async {
      LedgerSyncer.processGroupMeta({'group': 'g1', 'name': 'X'}, groupDao);
      final groups = await groupDao.watchAllGroups().first;
      expect(groups.first.currency, 'EUR');
    });
  });

  group('LedgerSyncer.processMember', () {
    test('writes member row (active)', () async {
      LedgerSyncer.processMember({
        'group': 'g1',
        'user': '@bob:m.org',
        'status': 'active',
        'updated_at': 100,
      }, memberDao);
      final members = await memberDao.getMembers('g1');
      expect(members.length, 1);
      expect(members.first.userId, '@bob:m.org');
      expect(members.first.isActive, true);
    });

    test('older update is ignored (last-writer-wins)', () async {
      LedgerSyncer.processMember({
        'group': 'g1',
        'user': '@bob:m.org',
        'status': 'removed',
        'updated_at': 200,
      }, memberDao);
      // An older "active" must not overwrite the newer "removed".
      LedgerSyncer.processMember({
        'group': 'g1',
        'user': '@bob:m.org',
        'status': 'active',
        'updated_at': 100,
      }, memberDao);
      final members = await memberDao.getMembers('g1');
      expect(members.single.status, 'removed');
    });

    test('reads participant_id + name + matrix_id (virtual-users shape)',
        () async {
      LedgerSyncer.processMember({
        'group': 'g1',
        'participant_id': 'p-uuid',
        'name': 'Cash',
        'matrix_id': null, // pure-local participant
        'status': 'active',
        'updated_at': 100,
      }, memberDao);
      final m = (await memberDao.getMembers('g1')).single;
      expect(m.userId, 'p-uuid');
      expect(m.displayName, 'Cash');
      expect(m.matrixId, isNull);
      expect(m.isClaimed, false);
    });

    test('a newer payload claims a participant (sets matrixId via LWW)',
        () async {
      LedgerSyncer.processMember({
        'group': 'g1',
        'participant_id': 'p-uuid',
        'name': 'Bob',
        'matrix_id': null,
        'status': 'active',
        'updated_at': 100,
      }, memberDao);
      // Bob joins and claims the slot.
      LedgerSyncer.processMember({
        'group': 'g1',
        'participant_id': 'p-uuid',
        'name': 'Bob',
        'matrix_id': '@bob:y.org',
        'status': 'active',
        'updated_at': 200,
      }, memberDao);
      final m = (await memberDao.getMembers('g1')).single;
      expect(m.matrixId, '@bob:y.org');
      expect(m.userId, 'p-uuid'); // identity unchanged by the claim
    });
  });

  group('LedgerSyncer.processBootstrap', () {
    test('applies group meta, members and ledger in one payload', () async {
      LedgerSyncer.processBootstrap({
        'group': 'g1',
        'name': 'Trip',
        'currency': 'USD',
        'members': [
          {'group': 'g1', 'user': '@a:m.org', 'status': 'active', 'updated_at': 1},
          {'group': 'g1', 'user': '@b:m.org', 'status': 'active', 'updated_at': 1},
        ],
        'expenses': [
          {
            'group': 'g1',
            'id': 'e1',
            'description': 'Hotel',
            'amount': 8000,
            'currency': 'USD',
            'paid_by': '@a:m.org',
            'split': {'@a:m.org': 4000, '@b:m.org': 4000},
            'created_at': 5,
          },
        ],
        'settlements': [
          {
            'group': 'g1',
            'id': 's1',
            'amount': 4000,
            'currency': 'USD',
            'from': '@b:m.org',
            'to': '@a:m.org',
            'created_at': 6,
          },
        ],
      }, groupDao, memberDao, expDao);

      expect((await groupDao.watchAllGroups().first).single.currency, 'USD');
      expect((await memberDao.getMembers('g1')).length, 2);
      expect((await expDao.watchExpensesForRoom('g1').first).single.id, 'e1');
      expect((await expDao.watchSettlementsForRoom('g1').first).single.id, 's1');
    });

    test('bootstrap containing a tombstone deletes the local live copy',
        () async {
      LedgerSyncer.processExpense({
        'id': 'e1',
        'group': 'g1',
        'description': 'Hotel',
        'amount': 8000,
        'currency': 'EUR',
        'paid_by': '@a:m.org',
        'split': <String, int>{},
        'created_at': 5,
        'updated_at': 5,
      }, expDao);

      LedgerSyncer.processBootstrap({
        'group': 'g1',
        'name': 'Trip',
        'currency': 'EUR',
        'members': const [],
        'expenses': [
          {
            'group': 'g1',
            'id': 'e1',
            'description': 'Hotel',
            'amount': 8000,
            'currency': 'EUR',
            'paid_by': '@a:m.org',
            'split': <String, int>{},
            'created_at': 5,
            'updated_at': 10,
            'deleted': true,
          },
        ],
        'settlements': const [],
      }, groupDao, memberDao, expDao);

      expect(await expDao.watchExpensesForRoom('g1').first, isEmpty);
      final all = await expDao.getAllExpensesForGroup('g1');
      expect(all.single.deleted, true);
    });
  });

  group('LedgerSyncer — LWW edits and tombstones (protocol v1)', () {
    Map<String, dynamic> expenseContent(
            {required int updatedAt,
            String description = 'Pizza',
            bool deleted = false}) =>
        {
          'v': 1,
          'id': 'e1',
          'group': 'g1',
          'description': description,
          'amount': 3000,
          'currency': 'EUR',
          'paid_by': '@alice:m.org',
          'split': {'@alice:m.org': 3000},
          'created_at': 1000,
          'updated_at': updatedAt,
          'deleted': deleted,
        };

    test('a stale edit does not overwrite a newer row', () async {
      LedgerSyncer.processExpense(
          expenseContent(updatedAt: 2000, description: 'current'), expDao);
      LedgerSyncer.processExpense(
          expenseContent(updatedAt: 1500, description: 'stale'), expDao);

      final rows = await expDao.watchExpensesForRoom('g1').first;
      expect(rows.single.description, 'current');
    });

    test('a newer edit wins', () async {
      LedgerSyncer.processExpense(
          expenseContent(updatedAt: 1000, description: 'v1'), expDao);
      LedgerSyncer.processExpense(
          expenseContent(updatedAt: 2000, description: 'v2'), expDao);

      final rows = await expDao.watchExpensesForRoom('g1').first;
      expect(rows.single.description, 'v2');
    });

    test('a delete payload tombstones the expense', () async {
      LedgerSyncer.processExpense(expenseContent(updatedAt: 1000), expDao);
      LedgerSyncer.processExpense(
          expenseContent(updatedAt: 2000, deleted: true), expDao);

      expect(await expDao.watchExpensesForRoom('g1').first, isEmpty);
    });

    test('an older live payload cannot resurrect a tombstone', () async {
      LedgerSyncer.processExpense(
          expenseContent(updatedAt: 2000, deleted: true), expDao);
      LedgerSyncer.processExpense(expenseContent(updatedAt: 1000), expDao);

      expect(await expDao.watchExpensesForRoom('g1').first, isEmpty);
      expect((await expDao.getAllExpensesForGroup('g1')).single.deleted, true);
    });

    test('payload without updated_at falls back to created_at (pre-v1 peer)',
        () async {
      LedgerSyncer.processExpense({
        'id': 'e1',
        'group': 'g1',
        'description': 'Legacy',
        'amount': 100,
        'currency': 'EUR',
        'paid_by': '@a:m.org',
        'split': <String, int>{},
        'created_at': 1234,
      }, expDao);

      final rows = await expDao.watchExpensesForRoom('g1').first;
      expect(rows.single.updatedAt, 1234);
    });

    test('stale group meta does not overwrite a newer rename', () async {
      LedgerSyncer.processGroupMeta({
        'group': 'g1',
        'name': 'New Name',
        'currency': 'EUR',
        'updated_at': 2000,
      }, groupDao);
      LedgerSyncer.processGroupMeta({
        'group': 'g1',
        'name': 'Old Name',
        'currency': 'USD',
        'updated_at': 1000,
      }, groupDao);

      final groups = await groupDao.watchAllGroups().first;
      expect(groups.single.name, 'New Name');
    });
  });

  group('ledger_payloads codec', () {
    test('expensePayload round-trips through processExpense', () async {
      const expense = ExpenseModel(
        id: 'e1',
        roomId: 'g1',
        description: 'Dinner',
        amountCents: 4200,
        currency: 'CHF',
        paidBy: '@alice:m.org',
        splitsJson: '{"@alice:m.org":2100,"@bob:m.org":2100}',
        createdAt: 1000,
        updatedAt: 1500,
      );

      final payload = expensePayload(expense);
      expect(payload['v'], protocolVersion);
      LedgerSyncer.processExpense(payload, expDao);

      final row = (await expDao.watchExpensesForRoom('g1').first).single;
      expect(row.id, expense.id);
      expect(row.description, expense.description);
      expect(row.amountCents, expense.amountCents);
      expect(row.currency, expense.currency);
      expect(row.paidBy, expense.paidBy);
      expect(row.createdAt, expense.createdAt);
      expect(row.updatedAt, expense.updatedAt);
      expect(row.deleted, false);
    });

    test('settlementPayload round-trips through processSettlement', () async {
      const settlement = SettlementModel(
        id: 's1',
        roomId: 'g1',
        amountCents: 2100,
        currency: 'CHF',
        fromUser: '@bob:m.org',
        toUser: '@alice:m.org',
        createdAt: 2000,
        updatedAt: 2500,
      );

      LedgerSyncer.processSettlement(settlementPayload(settlement), expDao);

      final row = (await expDao.watchSettlementsForRoom('g1').first).single;
      expect(row.id, settlement.id);
      expect(row.amountCents, settlement.amountCents);
      expect(row.fromUser, settlement.fromUser);
      expect(row.toUser, settlement.toUser);
      expect(row.updatedAt, settlement.updatedAt);
    });
  });
}
