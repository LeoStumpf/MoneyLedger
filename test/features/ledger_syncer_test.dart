/// Tests for LedgerSyncer's static processing methods.
/// No package:matrix import — methods take plain Dart types only.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';

import '../helpers/in_memory_database.dart';

void main() {
  late AppDatabase db;
  late ExpensesDao expDao;
  late GroupsDao groupDao;

  setUp(() {
    db = openTestDatabase();
    expDao = ExpensesDao(db);
    groupDao = GroupsDao(db);
  });

  tearDown(() => db.close());

  group('LedgerSyncer.processExpense', () {
    test('writes expense row to DB', () async {
      LedgerSyncer.processExpense(
        '!r:m.org',
        '\$event1',
        {
          'id': 'uuid-1',
          'description': 'Pizza',
          'amount': 3000,
          'currency': 'EUR',
          'paid_by': '@alice:m.org',
          'split': {'@alice:m.org': 1500, '@bob:m.org': 1500},
        },
        1_000_000,
        expDao,
      );

      final rows = await expDao.watchExpensesForRoom('!r:m.org').first;
      expect(rows.length, 1);
      expect(rows.first.id, 'uuid-1');
      expect(rows.first.description, 'Pizza');
      expect(rows.first.amountCents, 3000);
      expect(rows.first.currency, 'EUR');
      expect(rows.first.paidBy, '@alice:m.org');
      expect(rows.first.createdAt, 1_000_000);
    });

    test('missing id field — no row written', () async {
      LedgerSyncer.processExpense(
        '!r:m.org', null, {'description': 'No id'}, 0, expDao);

      final rows = await expDao.watchExpensesForRoom('!r:m.org').first;
      expect(rows, isEmpty);
    });

    test('calling twice with same id is idempotent', () async {
      final content = {
        'id': 'uuid-1',
        'description': 'Pizza',
        'amount': 3000,
        'currency': 'EUR',
        'paid_by': '@alice:m.org',
        'split': <String, int>{},
      };
      LedgerSyncer.processExpense('!r:m.org', '\$e1', content, 0, expDao);
      LedgerSyncer.processExpense('!r:m.org', '\$e1', content, 0, expDao);

      final rows = await expDao.watchExpensesForRoom('!r:m.org').first;
      expect(rows.length, 1);
    });
  });

  group('LedgerSyncer.processSettlement', () {
    test('writes settlement row to DB', () async {
      LedgerSyncer.processSettlement(
        '!r:m.org',
        '\$event2',
        {
          'id': 'settle-1',
          'amount': 1500,
          'currency': 'EUR',
          'from': '@bob:m.org',
          'to': '@alice:m.org',
        },
        2_000_000,
        expDao,
      );

      final rows = await expDao.watchSettlementsForRoom('!r:m.org').first;
      expect(rows.length, 1);
      expect(rows.first.id, 'settle-1');
      expect(rows.first.amountCents, 1500);
      expect(rows.first.fromUser, '@bob:m.org');
      expect(rows.first.toUser, '@alice:m.org');
    });

    test('missing id field — no row written', () async {
      LedgerSyncer.processSettlement(
          '!r:m.org', null, {'amount': 100}, 0, expDao);

      final rows = await expDao.watchSettlementsForRoom('!r:m.org').first;
      expect(rows, isEmpty);
    });
  });

  group('LedgerSyncer.processGroupState', () {
    test('writes group row to DB', () async {
      LedgerSyncer.processGroupState(
        '!r:m.org',
        {'currency': 'CHF'},
        'Alpine Hut',
        groupDao,
      );

      final groups = await groupDao.watchAllGroups().first;
      expect(groups.length, 1);
      expect(groups.first.roomId, '!r:m.org');
      expect(groups.first.name, 'Alpine Hut');
      expect(groups.first.currency, 'CHF');
    });

    test('missing currency falls back to EUR', () async {
      LedgerSyncer.processGroupState('!r:m.org', {}, 'No Currency', groupDao);

      final groups = await groupDao.watchAllGroups().first;
      expect(groups.first.currency, 'EUR');
    });

    test('calling twice with same roomId is idempotent', () async {
      LedgerSyncer.processGroupState(
          '!r:m.org', {'currency': 'USD'}, 'v1', groupDao);
      LedgerSyncer.processGroupState(
          '!r:m.org', {'currency': 'GBP'}, 'v2', groupDao);

      final groups = await groupDao.watchAllGroups().first;
      expect(groups.length, 1);
      expect(groups.first.currency, 'GBP');
    });
  });
}
