/// CSV export from the DB (Phase D, M3): the testable seam — render a group's
/// rows to CSV; the file save/share around it is manual-smoke only.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/features/backup/csv_export.dart';
import 'package:money_ledger/features/backup/ledger_csv.dart';

import '../helpers/in_memory_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  test('exports a group to CSV that parses back to its expenses', () async {
    await GroupsDao(db).upsertGroupLww(const GroupsCompanion(
        roomId: Value('g1'),
        name: Value('Trip'),
        currency: Value('EUR'),
        updatedAt: Value(1000)));
    await MembersDao(db).upsertMemberLww(const MembersCompanion(
        groupId: Value('g1'),
        userId: Value('pa'),
        displayName: Value('Alex'),
        matrixId: Value('@alex:x.org'),
        status: Value('active'),
        updatedAt: Value(1)));
    await MembersDao(db).upsertMemberLww(const MembersCompanion(
        groupId: Value('g1'),
        userId: Value('pb'),
        displayName: Value('Sam'),
        status: Value('active'),
        updatedAt: Value(1)));
    await ExpensesDao(db).upsertExpenseLww(const ExpensesCompanion(
        id: Value('e1'),
        roomId: Value('g1'),
        description: Value('Dinner'),
        amountCents: Value(4200),
        currency: Value('EUR'),
        paidBy: Value('pa'),
        splitsJson: Value('{"pa":2100,"pb":2100}'),
        createdAt: Value(1760000000000),
        updatedAt: Value(1760000050000)));

    final csv = await buildGroupCsvForExport(
        GroupsDao(db), MembersDao(db), ExpensesDao(db), 'g1');

    final parsed = parseGroupCsv(csv);
    expect(parsed.groupId, 'g1');
    expect(parsed.participantNames, ['Alex', 'Sam']);
    final r = parsed.rows.single;
    expect(r.id, 'e1');
    expect(r.amountCents, 4200);
    expect(r.paidByName, 'Alex');
    expect(r.sharesByName, {'Alex': 2100, 'Sam': 2100});
  });

  test('a missing group exports as empty', () async {
    final csv = await buildGroupCsvForExport(
        GroupsDao(db), MembersDao(db), ExpensesDao(db), 'nope');
    expect(csv, isEmpty);
  });

  test('csvFileName sanitises the group name', () {
    expect(csvFileName('Trip to Italy!'), 'Trip to Italy.csv');
    expect(csvFileName('  '), 'group.csv');
  });
}
