import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';

import '../helpers/in_memory_database.dart';

const _roomA = '!roomA:matrix.org';
const _roomB = '!roomB:matrix.org';

ExpensesCompanion _expense(String id, String roomId) => ExpensesCompanion(
      id: Value(id),
      roomId: Value(roomId),
      description: const Value('Dinner'),
      amountCents: const Value(4200),
      currency: const Value('EUR'),
      paidBy: const Value('@alice:matrix.org'),
      splitsJson: const Value('{"@alice:matrix.org":2100,"@bob:matrix.org":2100}'),
      createdAt: const Value(1000),
    );

SettlementsCompanion _settlement(String id, String roomId) =>
    SettlementsCompanion(
      id: Value(id),
      roomId: Value(roomId),
      amountCents: const Value(2100),
      currency: const Value('EUR'),
      fromUser: const Value('@bob:matrix.org'),
      toUser: const Value('@alice:matrix.org'),
      createdAt: const Value(2000),
    );

void main() {
  late AppDatabase db;
  late ExpensesDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = ExpensesDao(db);
  });

  tearDown(() => db.close());

  group('ExpensesDao — expenses', () {
    test('watchExpensesForRoom starts empty', () async {
      final rows = await dao.watchExpensesForRoom(_roomA).first;
      expect(rows, isEmpty);
    });

    test('upsert expense — stream emits it with correct fields', () async {
      await dao.upsertExpense(_expense('e1', _roomA));

      final rows = await dao.watchExpensesForRoom(_roomA).first;
      expect(rows.length, 1);
      expect(rows.first.id, 'e1');
      expect(rows.first.roomId, _roomA);
      expect(rows.first.description, 'Dinner');
      expect(rows.first.amountCents, 4200);
      expect(rows.first.paidBy, '@alice:matrix.org');
    });

    test('upsert same id twice — one row (idempotent)', () async {
      await dao.upsertExpense(_expense('e1', _roomA));
      await dao.upsertExpense(_expense('e1', _roomA));

      final rows = await dao.watchExpensesForRoom(_roomA).first;
      expect(rows.length, 1);
    });

    test('expenses in room A do not appear in room B stream', () async {
      await dao.upsertExpense(_expense('e1', _roomA));

      final rowsB = await dao.watchExpensesForRoom(_roomB).first;
      expect(rowsB, isEmpty);
    });
  });

  group('ExpensesDao — settlements', () {
    test('watchSettlementsForRoom starts empty', () async {
      final rows = await dao.watchSettlementsForRoom(_roomA).first;
      expect(rows, isEmpty);
    });

    test('upsert settlement — stream emits it with correct fields', () async {
      await dao.upsertSettlement(_settlement('s1', _roomA));

      final rows = await dao.watchSettlementsForRoom(_roomA).first;
      expect(rows.length, 1);
      expect(rows.first.id, 's1');
      expect(rows.first.amountCents, 2100);
      expect(rows.first.fromUser, '@bob:matrix.org');
      expect(rows.first.toUser, '@alice:matrix.org');
    });

    test('settlements in room A do not appear in room B stream', () async {
      await dao.upsertSettlement(_settlement('s1', _roomA));

      final rowsB = await dao.watchSettlementsForRoom(_roomB).first;
      expect(rowsB, isEmpty);
    });
  });
}
