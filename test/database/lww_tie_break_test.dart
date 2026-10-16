/// G27: every DAO LWW upsert breaks a same-clock tie by content hash — the
/// result is the same whatever order two versions arrive in.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import '../helpers/in_memory_database.dart';

ExpenseModel _expense(
  String description, {
  int at = 500,
  bool pending = false,
}) => ExpenseModel(
  id: 'e1',
  roomId: 'g1',
  description: description,
  amountCents: 100,
  currency: 'EUR',
  paidBy: '@a:x.org',
  splitsJson: '{"@a:x.org":100}',
  createdAt: 1,
  updatedAt: at,
  pendingSign: pending,
);

SettlementModel _settlement(int amount) => SettlementModel(
  id: 's1',
  roomId: 'g1',
  amountCents: amount,
  currency: 'EUR',
  fromUser: '@a:x.org',
  toUser: '@b:y.org',
  createdAt: 1,
  updatedAt: 500,
);

MemberModel _member(String name) => MemberModel(
  groupId: 'g1',
  userId: '@a:x.org',
  displayName: name,
  matrixId: '@a:x.org',
  status: 'active',
  updatedAt: 500,
);

GroupModel _meta(String name) =>
    GroupModel(roomId: 'g1', name: name, currency: 'EUR', updatedAt: 500);

/// Orders [a] and [b] as (winner, loser) by their version hash.
(T, T) _rank<T>(T a, T b, String Function(T) hash) =>
    hash(a).compareTo(hash(b)) > 0 ? (a, b) : (b, a);

void main() {
  late AppDatabase db;
  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  test('expenses: the higher hash wins in either arrival order', () async {
    final (win, lose) = _rank(
      _expense('Dinner'),
      _expense('Lunch'),
      expenseVersionHash,
    );
    for (final order in [
      [win, lose],
      [lose, win],
    ]) {
      await db.delete(db.expenses).go();
      final dao = ExpensesDao(db);
      for (final e in order) {
        await dao.upsertExpenseLww(expenseCompanion(e));
      }
      expect((await dao.getExpenseById('e1'))!.description, win.description);
    }
  });

  test('a newer clock still beats any hash', () async {
    final dao = ExpensesDao(db);
    await dao.upsertExpenseLww(expenseCompanion(_expense('B', at: 600)));
    await dao.upsertExpenseLww(expenseCompanion(_expense('A', at: 500)));
    expect((await dao.getExpenseById('e1'))!.description, 'B');
  });

  test('the same version is re-written (pendingSign → signed)', () async {
    final dao = ExpensesDao(db);
    await dao.upsertExpenseLww(
      expenseCompanion(_expense('Dinner', pending: true)),
    );
    const sig = RecordSignature(
      user: '@a:x.org',
      device: 'D',
      key: 'k',
      sig: 's',
    );
    await dao.upsertExpenseLww(
      expenseCompanion(_expense('Dinner').withSigning(sig: sig)),
    );
    final stored = (await dao.getExpenseById('e1'))!;
    expect(stored.pendingSign, isFalse);
    expect(stored.sig, sig);
  });

  test('settlements, members and group meta tie-break the same way', () async {
    final (sWin, sLose) = _rank(
      _settlement(100),
      _settlement(200),
      settlementVersionHash,
    );
    final (mWin, mLose) = _rank(
      _member('Alex'),
      _member('Alexandra'),
      memberVersionHash,
    );
    final (gWin, gLose) = _rank(
      _meta('Trip'),
      _meta('Holiday'),
      groupMetaVersionHash,
    );
    final expenses = ExpensesDao(db);
    final members = MembersDao(db);
    final groups = GroupsDao(db);
    await expenses.upsertSettlementLww(settlementCompanion(sWin));
    await expenses.upsertSettlementLww(settlementCompanion(sLose));
    await members.upsertMemberLww(memberCompanion(mWin));
    await members.upsertMemberLww(memberCompanion(mLose));
    await groups.upsertGroupLww(groupCompanion(gWin));
    await groups.upsertGroupLww(groupCompanion(gLose));

    expect(
      (await expenses.getSettlementById('s1'))!.amountCents,
      sWin.amountCents,
    );
    expect(
      (await members.getMembers('g1')).single.displayName,
      mWin.displayName,
    );
    expect((await groups.getGroup('g1'))!.name, gWin.name);
  });
}
