/// Tests for LedgerSyncer's static processing methods.
/// No package:matrix import — methods take plain Dart types only.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';

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
  });
}
