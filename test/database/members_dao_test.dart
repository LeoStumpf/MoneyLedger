/// Participant identity (virtual users, M1): the Members row now carries a
/// display name and an optional Matrix-account claim. Sync targets are only the
/// active, *claimed* participants; pure-local participants are ledger data only.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';

import '../helpers/in_memory_database.dart';

void main() {
  late AppDatabase db;
  late MembersDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = MembersDao(db);
  });

  tearDown(() => db.close());

  Future<void> add(
    String id, {
    String? matrixId,
    String name = '',
    String status = 'active',
    int updatedAt = 1000,
  }) => dao.upsertMemberLww(
    MembersCompanion(
      groupId: const Value('g1'),
      userId: Value(id),
      displayName: Value(name),
      matrixId: Value(matrixId),
      status: Value(status),
      updatedAt: Value(updatedAt),
    ),
  );

  group('MembersDao — participant identity', () {
    test('round-trips displayName and matrixId', () async {
      await add('p1', name: 'Alice', matrixId: '@alice:x.org');
      final m = (await dao.getMembers('g1')).single;
      expect(m.userId, 'p1');
      expect(m.displayName, 'Alice');
      expect(m.matrixId, '@alice:x.org');
      expect(m.isClaimed, true);
    });

    test('a local participant has no matrixId and is not claimed', () async {
      await add('p-local', name: 'Cash', matrixId: null);
      final m = (await dao.getMembers('g1')).single;
      expect(m.matrixId, isNull);
      expect(m.isClaimed, false);
    });

    test(
      'activeClaimedMatrixIds returns only active, claimed participants',
      () async {
        await add('p1', name: 'Alice', matrixId: '@alice:x.org');
        await add('p2', name: 'Bob', matrixId: '@bob:y.org', status: 'removed');
        await add('p-local', name: 'Cash', matrixId: null);

        final targets = await dao.activeClaimedMatrixIds('g1');
        expect(targets, ['@alice:x.org']);
      },
    );

    test('memberByMatrixId finds the claiming participant', () async {
      await add('p1', name: 'Alice', matrixId: '@alice:x.org');
      await add('p-local', name: 'Cash', matrixId: null);

      final found = await dao.memberByMatrixId('g1', '@alice:x.org');
      expect(found?.userId, 'p1');
      expect(await dao.memberByMatrixId('g1', '@nobody:z.org'), isNull);
    });

    test('LWW upsert still ignores a staler write', () async {
      await add('p1', name: 'Alice', matrixId: '@alice:x.org', updatedAt: 2000);
      // Stale unclaim attempt — older clock, must be ignored.
      await add('p1', name: 'Alice', matrixId: null, updatedAt: 1000);
      final m = (await dao.getMembers('g1')).single;
      expect(m.matrixId, '@alice:x.org');

      // Newer unclaim wins.
      await add('p1', name: 'Alice', matrixId: null, updatedAt: 3000);
      expect((await dao.getMembers('g1')).single.matrixId, isNull);
    });
  });

  group('v4 migration backfill (SQL)', () {
    // Mirrors the onUpgrade statements: pre-virtual-users rows have userId ==
    // MXID, so matrixId is copied from it and displayName is the localpart.
    Future<void> runBackfill() async {
      await db.customStatement('UPDATE members SET matrix_id = user_id');
      await db.customStatement(
        "UPDATE members SET display_name = "
        "substr(user_id, 2, instr(user_id, ':') - 2) "
        "WHERE user_id LIKE '@%:%'",
      );
      await db.customStatement(
        "UPDATE members SET display_name = user_id "
        "WHERE user_id NOT LIKE '@%:%'",
      );
    }

    test('an MXID row backfills matrixId and the localpart name', () async {
      await add('@alice:matrix.org', name: '', matrixId: null);
      await runBackfill();
      final m = (await dao.getMembers('g1')).single;
      expect(m.matrixId, '@alice:matrix.org');
      expect(m.displayName, 'alice');
    });

    test('a non-MXID id falls back to the full id as the name', () async {
      await add('weird-id', name: '', matrixId: null);
      await runBackfill();
      final m = (await dao.getMembers('g1')).single;
      expect(m.matrixId, 'weird-id');
      expect(m.displayName, 'weird-id');
    });
  });
}
