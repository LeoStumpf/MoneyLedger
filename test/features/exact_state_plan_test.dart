/// G58: the generalised reset planner with a snapshot target — "exactly
/// this state" (absent = didn't exist then, only content this device held
/// is written again, unknown entries left alone, members never touched).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart' show RecordKind;
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/features/history/group_history.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

ExpenseModel _e(
  String id,
  String description, {
  int amount = 100,
  int at = 1,
  bool deleted = false,
}) => ExpenseModel(
  id: id,
  roomId: 'g1',
  description: description,
  amountCents: amount,
  currency: 'EUR',
  paidBy: 'p1',
  splitsJson: '{"p1":$amount}',
  createdAt: 1,
  updatedAt: at,
  deleted: deleted,
);

SettlementModel _s(
  String id, {
  int amount = 50,
  int at = 1,
  bool deleted = false,
}) => SettlementModel(
  id: id,
  roomId: 'g1',
  amountCents: amount,
  currency: 'EUR',
  fromUser: 'p1',
  toUser: 'p2',
  createdAt: 2,
  updatedAt: at,
  deleted: deleted,
);

GroupModel _meta(String name, {int at = 1}) =>
    GroupModel(roomId: 'g1', name: name, currency: 'EUR', updatedAt: at);

const _member = MemberModel(
  groupId: 'g1',
  userId: 'p1',
  displayName: 'Ann',
  matrixId: '@ann:x.org',
  status: 'active',
  updatedAt: 1,
);

var _id = 0;

/// A history entry with the record's real version hash (as the DAOs store).
HistoryEntry _h(Object record) {
  final (kind, id, version, content) = switch (record) {
    ExpenseModel e => (
      RecordKind.expense,
      e.id,
      expenseVersion(e),
      expensePayload(e),
    ),
    SettlementModel s => (
      RecordKind.settlement,
      s.id,
      settlementVersion(s),
      settlementPayload(s),
    ),
    GroupModel g => (
      RecordKind.meta,
      g.roomId,
      groupMetaVersion(g),
      groupMetaPayload(g),
    ),
    _ => throw ArgumentError(record),
  };
  return HistoryEntry(
    id: ++_id,
    groupId: 'g1',
    kind: kind,
    recordId: id,
    updatedAt: version.at,
    versionHash: version.hash,
    content: content,
    source: HistorySource.local,
    recordedAt: _id,
  );
}

/// A snapshot group payload, like the backup export writes it.
Map<String, dynamic> _snapshot({
  GroupModel? meta,
  List<ExpenseModel> expenses = const [],
  List<SettlementModel> settlements = const [],
}) => buildBootstrapContent(
  'g1',
  meta,
  const [_member],
  expenses,
  settlements,
  includePending: true,
);

void main() {
  setUp(() => _id = 0);

  // The snapshot: Dinner (100), Taxi (200), a payment, meta "Trip". Since
  // then: Dinner edited, Taxi deleted, New added, the payment deleted, the
  // group renamed.
  final dinner = _e('e1', 'Dinner');
  final taxi = _e('e2', 'Taxi', amount: 200);
  final pay = _s('s1');
  final trip = _meta('Trip');
  final history = [
    _h(trip),
    _h(dinner),
    _h(taxi),
    _h(pay),
    _h(_e('e1', 'Hacked', amount: 999, at: 5)),
    _h(_e('e2', 'Taxi', amount: 200, at: 5, deleted: true)),
    _h(_e('e3', 'New', at: 5)),
    _h(_s('s1', at: 5, deleted: true)),
    _h(_meta('Renamed', at: 5)),
  ];
  final storedExpenses = [
    _e('e1', 'Hacked', amount: 999, at: 5),
    _e('e2', 'Taxi', amount: 200, at: 5, deleted: true),
    _e('e3', 'New', at: 5),
  ];
  final storedSettlements = [_s('s1', at: 5, deleted: true)];

  GroupResetPlan plan(Map<String, dynamic> snapshot, {List<HistoryEntry>? h}) =>
      planGroupResetTo(
        groupId: 'g1',
        target: snapshotResetTarget(snapshot, history: h ?? history),
        expenses: storedExpenses,
        settlements: storedSettlements,
        meta: _meta('Renamed', at: 5),
        now: 3,
      );

  test('makes the group equal to the snapshot as new versions', () {
    final p = plan(
      _snapshot(meta: trip, expenses: [dinner, taxi], settlements: [pay]),
    );
    expect(p.restored, 2); // Taxi + payment
    expect(p.reverted, 1); // Dinner
    expect(p.removed, 1); // New (absent in the snapshot)
    expect(p.arriving, 0);
    expect(p.skipped, 0);
    ExpenseModel byId(String id) =>
        p.changes.firstWhere((c) => c.expense?.id == id).expense!;
    expect(byId('e1').description, 'Dinner');
    expect(byId('e1').amountCents, 100);
    expect(byId('e1').updatedAt, 6); // nextLwwClock(5)
    expect(byId('e2').deleted, isFalse);
    expect(byId('e3').deleted, isTrue);
    expect(byId('e3').description, 'New'); // tombstone keeps today's content
    expect(
      p.changes.firstWhere((c) => c.settlement != null).effect,
      ResetEffect.restored,
    );
    expect(p.meta!.name, 'Trip');
    expect(p.meta!.updatedAt, 6);
    expect(p.changes.every((c) => c.kind != RecordKind.member), isTrue);
  });

  test('a tombstone in the snapshot removes a live record', () {
    final p = plan(
      _snapshot(
        meta: trip,
        expenses: [dinner, taxi, _e('e3', 'New', deleted: true)],
        settlements: [pay],
      ),
    );
    expect(
      p.changes.firstWhere((c) => c.expense?.id == 'e3').effect,
      ResetEffect.removed,
    );
  });

  test('a snapshot equal to what is stored plans nothing', () {
    final p = planGroupResetTo(
      groupId: 'g1',
      target: snapshotResetTarget(
        _snapshot(meta: trip, expenses: [dinner], settlements: [pay]),
        history: history,
      ),
      expenses: [dinner],
      settlements: [pay],
      meta: trip,
    );
    expect(p.isEmpty, isTrue);
  });

  test('records the snapshot has but this device lacks are "arriving" '
      '(the merge brings them, not the plan)', () {
    final p = plan(
      _snapshot(
        meta: trip,
        expenses: [dinner, taxi, _e('e9', 'Elsewhere')],
        settlements: [pay, _s('s9', deleted: true)],
      ),
    );
    expect(p.arriving, 1); // e9; the tombstone s9 doesn't count
    expect(p.changes.any((c) => c.expense?.id == 'e9'), isFalse);
  });

  test('content this device never held is skipped (a hand-edited file '
      'cannot make it sign something new)', () {
    final forged = _e('e1', 'Forged', amount: 1);
    final p = plan(
      _snapshot(
        meta: _meta('Forged name'),
        expenses: [forged, taxi],
        settlements: [pay],
      ),
    );
    expect(p.changes.any((c) => c.expense?.id == 'e1'), isFalse);
    expect(p.meta, isNull);
    expect(p.skipped, 2);
    // The rest still goes back.
    expect(p.restored, 2);
  });

  test('a snapshot version breaking today\'s rules is skipped', () {
    final broken = _e('e1', 'Broken', amount: 100).copyWithSplits('{"p1":1}');
    final p = plan(
      _snapshot(meta: trip, expenses: [broken, taxi], settlements: [pay]),
      h: [...history, _h(broken)],
    );
    expect(p.changes.any((c) => c.expense?.id == 'e1'), isFalse);
    expect(p.skipped, 1);
  });

  test('an unreadable snapshot entry leaves that record alone; no meta '
      'leaves the meta alone', () {
    final snap = _snapshot(expenses: [dinner, taxi], settlements: [pay]);
    (snap['expenses'] as List).add({'id': 'e3', 'group': 'g1'});
    snap.remove('meta');
    final p = plan(snap);
    expect(p.changes.any((c) => c.expense?.id == 'e3'), isFalse);
    expect(p.meta, isNull);
  });

  test('the history reset is unchanged by the generalisation', () {
    final p = planGroupReset(
      groupId: 'g1',
      beforeId: 5,
      entries: history,
      expenses: storedExpenses,
      settlements: storedSettlements,
      meta: _meta('Renamed', at: 5),
      now: 3,
    );
    expect([p.restored, p.reverted, p.removed], [2, 1, 1]);
    expect(p.meta!.name, 'Trip');
  });
}

extension on ExpenseModel {
  ExpenseModel copyWithSplits(String splits) => ExpenseModel(
    id: id,
    roomId: roomId,
    description: description,
    amountCents: amountCents,
    currency: currency,
    paidBy: paidBy,
    splitsJson: splits,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deleted: deleted,
  );
}
