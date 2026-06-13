import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';

import '../helpers/in_memory_database.dart';

const _roomA = '!roomA:matrix.org';
const _roomB = '!roomB:matrix.org';

ExpensesCompanion _expense(String id, String roomId,
        {String description = 'Dinner',
        int updatedAt = 1000,
        bool deleted = false}) =>
    ExpensesCompanion(
      id: Value(id),
      roomId: Value(roomId),
      description: Value(description),
      amountCents: const Value(4200),
      currency: const Value('EUR'),
      paidBy: const Value('@alice:matrix.org'),
      splitsJson: const Value('{"@alice:matrix.org":2100,"@bob:matrix.org":2100}'),
      createdAt: const Value(1000),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
    );

SettlementsCompanion _settlement(String id, String roomId,
        {int updatedAt = 2000, bool deleted = false}) =>
    SettlementsCompanion(
      id: Value(id),
      roomId: Value(roomId),
      amountCents: const Value(2100),
      currency: const Value('EUR'),
      fromUser: const Value('@bob:matrix.org'),
      toUser: const Value('@alice:matrix.org'),
      createdAt: const Value(2000),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
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
      await dao.upsertExpenseLww(_expense('e1', _roomA));

      final rows = await dao.watchExpensesForRoom(_roomA).first;
      expect(rows.length, 1);
      expect(rows.first.id, 'e1');
      expect(rows.first.roomId, _roomA);
      expect(rows.first.description, 'Dinner');
      expect(rows.first.amountCents, 4200);
      expect(rows.first.paidBy, '@alice:matrix.org');
    });

    test('upsert same id twice — one row (idempotent)', () async {
      await dao.upsertExpenseLww(_expense('e1', _roomA));
      await dao.upsertExpenseLww(_expense('e1', _roomA));

      final rows = await dao.watchExpensesForRoom(_roomA).first;
      expect(rows.length, 1);
    });

    test('expenses in room A do not appear in room B stream', () async {
      await dao.upsertExpenseLww(_expense('e1', _roomA));

      final rowsB = await dao.watchExpensesForRoom(_roomB).first;
      expect(rowsB, isEmpty);
    });
  });

  group('ExpensesDao — LWW', () {
    test('newer updatedAt wins', () async {
      await dao.upsertExpenseLww(
          _expense('e1', _roomA, description: 'old', updatedAt: 1000));
      await dao.upsertExpenseLww(
          _expense('e1', _roomA, description: 'new', updatedAt: 2000));

      final rows = await dao.watchExpensesForRoom(_roomA).first;
      expect(rows.single.description, 'new');
      expect(rows.single.updatedAt, 2000);
    });

    test('stale updatedAt is ignored', () async {
      await dao.upsertExpenseLww(
          _expense('e1', _roomA, description: 'current', updatedAt: 2000));
      await dao.upsertExpenseLww(
          _expense('e1', _roomA, description: 'stale', updatedAt: 1000));

      final rows = await dao.watchExpensesForRoom(_roomA).first;
      expect(rows.single.description, 'current');
      expect(rows.single.updatedAt, 2000);
    });

    test('stale settlement upsert is ignored', () async {
      await dao.upsertSettlementLww(_settlement('s1', _roomA, updatedAt: 2000));
      await dao.upsertSettlementLww(
          _settlement('s1', _roomA, updatedAt: 1000, deleted: true));

      final rows = await dao.watchSettlementsForRoom(_roomA).first;
      expect(rows.single.id, 's1');
      expect(rows.single.deleted, false);
    });
  });

  group('ExpensesDao — tombstones', () {
    test('deleted expense is hidden from watch and get', () async {
      await dao.upsertExpenseLww(_expense('e1', _roomA));
      await dao.upsertExpenseLww(
          _expense('e1', _roomA, updatedAt: 2000, deleted: true));

      expect(await dao.watchExpensesForRoom(_roomA).first, isEmpty);
      expect(await dao.getExpensesForRoom(_roomA), isEmpty);
    });

    test('deleted expense is still returned by getAllExpensesForGroup',
        () async {
      await dao.upsertExpenseLww(_expense('e1', _roomA));
      await dao.upsertExpenseLww(
          _expense('e1', _roomA, updatedAt: 2000, deleted: true));
      await dao.upsertExpenseLww(_expense('e2', _roomA));

      final all = await dao.getAllExpensesForGroup(_roomA);
      expect(all.length, 2);
      expect(all.firstWhere((e) => e.id == 'e1').deleted, true);
      expect(all.firstWhere((e) => e.id == 'e2').deleted, false);
    });

    test('a stale live payload cannot resurrect a tombstone', () async {
      await dao.upsertExpenseLww(
          _expense('e1', _roomA, updatedAt: 2000, deleted: true));
      await dao.upsertExpenseLww(_expense('e1', _roomA, updatedAt: 1000));

      expect(await dao.watchExpensesForRoom(_roomA).first, isEmpty);
      final all = await dao.getAllExpensesForGroup(_roomA);
      expect(all.single.deleted, true);
    });

    test('deleted settlement hidden from watch, returned by getAll', () async {
      await dao.upsertSettlementLww(
          _settlement('s1', _roomA, updatedAt: 3000, deleted: true));

      expect(await dao.watchSettlementsForRoom(_roomA).first, isEmpty);
      expect(await dao.getSettlementsForRoom(_roomA), isEmpty);
      final all = await dao.getAllSettlementsForGroup(_roomA);
      expect(all.single.deleted, true);
    });
  });

  group('ExpensesDao — settlements', () {
    test('watchSettlementsForRoom starts empty', () async {
      final rows = await dao.watchSettlementsForRoom(_roomA).first;
      expect(rows, isEmpty);
    });

    test('upsert settlement — stream emits it with correct fields', () async {
      await dao.upsertSettlementLww(_settlement('s1', _roomA));

      final rows = await dao.watchSettlementsForRoom(_roomA).first;
      expect(rows.length, 1);
      expect(rows.first.id, 's1');
      expect(rows.first.amountCents, 2100);
      expect(rows.first.fromUser, '@bob:matrix.org');
      expect(rows.first.toUser, '@alice:matrix.org');
    });

    test('settlements in room A do not appear in room B stream', () async {
      await dao.upsertSettlementLww(_settlement('s1', _roomA));

      final rowsB = await dao.watchSettlementsForRoom(_roomB).first;
      expect(rowsB, isEmpty);
    });
  });
}
