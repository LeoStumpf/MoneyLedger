import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';

import '../helpers/in_memory_database.dart';

void main() {
  late AppDatabase db;
  late GroupsDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = GroupsDao(db);
  });

  tearDown(() => db.close());

  group('GroupsDao', () {
    test('watchAllGroups starts empty', () async {
      final groups = await dao.watchAllGroups().first;
      expect(groups, isEmpty);
    });

    test('upsert group — stream emits it with correct fields', () async {
      await dao.upsertGroupLww(const GroupsCompanion(
        roomId: Value('!abc:matrix.org'),
        name: Value('Holiday Trip'),
        currency: Value('EUR'),
        updatedAt: Value(1000),
      ));

      final groups = await dao.watchAllGroups().first;
      expect(groups.length, 1);
      expect(groups.first.roomId, '!abc:matrix.org');
      expect(groups.first.name, 'Holiday Trip');
      expect(groups.first.currency, 'EUR');
      expect(groups.first.updatedAt, 1000);
    });

    test('upsert same roomId with newer clock — one row, newer wins', () async {
      await dao.upsertGroupLww(const GroupsCompanion(
        roomId: Value('!abc:matrix.org'),
        name: Value('v1'),
        currency: Value('EUR'),
        updatedAt: Value(1000),
      ));
      await dao.upsertGroupLww(const GroupsCompanion(
        roomId: Value('!abc:matrix.org'),
        name: Value('v2'),
        currency: Value('USD'),
        updatedAt: Value(2000),
      ));

      final groups = await dao.watchAllGroups().first;
      expect(groups.length, 1);
      expect(groups.first.name, 'v2');
      expect(groups.first.currency, 'USD');
    });

    test('stale group meta is ignored (LWW)', () async {
      await dao.upsertGroupLww(const GroupsCompanion(
        roomId: Value('!abc:matrix.org'),
        name: Value('current'),
        currency: Value('EUR'),
        updatedAt: Value(2000),
      ));
      await dao.upsertGroupLww(const GroupsCompanion(
        roomId: Value('!abc:matrix.org'),
        name: Value('stale'),
        currency: Value('USD'),
        updatedAt: Value(1000),
      ));

      final groups = await dao.watchAllGroups().first;
      expect(groups.single.name, 'current');
      expect(groups.single.currency, 'EUR');
    });

    test('delete group — stream emits empty list', () async {
      await dao.upsertGroupLww(const GroupsCompanion(
        roomId: Value('!abc:matrix.org'),
        name: Value('Trip'),
        currency: Value('EUR'),
        updatedAt: Value(1000),
      ));
      await dao.deleteGroup('!abc:matrix.org');

      final groups = await dao.watchAllGroups().first;
      expect(groups, isEmpty);
    });

    test('multiple groups all appear', () async {
      for (var i = 0; i < 3; i++) {
        await dao.upsertGroupLww(GroupsCompanion(
          roomId: Value('!room$i:matrix.org'),
          name: Value('Group $i'),
          currency: const Value('EUR'),
          updatedAt: const Value(1000),
        ));
      }

      final groups = await dao.watchAllGroups().first;
      expect(groups.length, 3);
    });
  });
}
