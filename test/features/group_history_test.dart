/// G48: the pure part of "reset group" — change batches from the version
/// history and the reset plan (restored / reverted / removed, tombstones,
/// meta, origin kept, members never touched).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart' show RecordKind;
import 'package:money_ledger/features/history/group_history.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

const _min = 60 * 1000;

const _origin = RecordSignature(
  user: '@ann:x.org',
  device: 'A',
  key: 'KA',
  sig: 'O',
);

ExpenseModel _e(
  String id,
  String description, {
  int amount = 100,
  int at = 1,
  bool deleted = false,
  RecordSignature? sig,
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
  origin: _origin,
  sig: sig,
);

SettlementModel _s(String id, {int amount = 50, bool deleted = false}) =>
    SettlementModel(
      id: id,
      roomId: 'g1',
      amountCents: amount,
      currency: 'EUR',
      fromUser: 'p1',
      toUser: 'p2',
      createdAt: 2,
      updatedAt: 1,
      deleted: deleted,
      origin: _origin,
    );

GroupModel _meta(String name, {int at = 1}) =>
    GroupModel(roomId: 'g1', name: name, currency: 'EUR', updatedAt: at);

var _nextId = 0;

HistoryEntry _entry(
  RecordKind kind,
  String recordId,
  Map<String, dynamic> content,
  int recordedAt, {
  HistorySource source = HistorySource.inbound,
}) => HistoryEntry(
  id: ++_nextId,
  groupId: 'g1',
  kind: kind,
  recordId: recordId,
  updatedAt: content['updated_at'] as int? ?? 0,
  versionHash: 'h',
  content: content,
  source: source,
  recordedAt: recordedAt,
);

HistoryEntry _ex(ExpenseModel e, int at, {HistorySource? source}) => _entry(
  RecordKind.expense,
  e.id,
  expensePayload(e),
  at,
  source: source ?? HistorySource.inbound,
);

HistoryEntry _st(SettlementModel s, int at) =>
    _entry(RecordKind.settlement, s.id, settlementPayload(s), at);

HistoryEntry _mt(GroupModel g, int at) =>
    _entry(RecordKind.meta, g.roomId, groupMetaPayload(g), at);

HistoryEntry _mb(int at) => _entry(
  RecordKind.member,
  'p1',
  memberPayload(
    const MemberModel(
      groupId: 'g1',
      userId: 'p1',
      displayName: 'Ann',
      matrixId: '@ann:x.org',
      status: 'active',
      updatedAt: 1,
    ),
  ),
  at,
);

const _bobSig = RecordSignature(
  user: '@bob:y.org',
  device: 'B',
  key: 'KB',
  sig: 'S',
);

void main() {
  setUp(() => _nextId = 0);

  group('changeBatches', () {
    test('clusters by gap, newest first, counts per record', () {
      final t0 = 1000000;
      final entries = [
        // Batch 1: the group arrives (meta, member, two expenses).
        _mt(_meta('Trip'), t0),
        _mb(t0),
        _ex(_e('e1', 'Dinner'), t0, source: HistorySource.local),
        _ex(_e('e2', 'Taxi'), t0 + 1),
        // Batch 2 (an hour later, Bob): e1 edited twice, e2 deleted, e3 new.
        _ex(_e('e1', 'Dinner!', at: 2, sig: _bobSig), t0 + 60 * _min),
        _ex(_e('e1', 'Dinner!!', at: 3, sig: _bobSig), t0 + 61 * _min),
        _ex(
          _e('e2', 'Taxi', at: 2, deleted: true, sig: _bobSig),
          t0 + 62 * _min,
        ),
        _ex(_e('e3', 'Bar', sig: _bobSig), t0 + 63 * _min),
        _mt(_meta('Trip 2', at: 2), t0 + 63 * _min),
      ];
      final b = changeBatches(entries, me: '@ann:x.org');
      expect(b, hasLength(2));
      final latest = b.first;
      expect(latest.startAt, t0 + 60 * _min);
      expect(latest.firstId, 5);
      expect(latest.lastId, 9);
      expect(latest.added, 1);
      expect(latest.changed, 1);
      expect(latest.deleted, 1);
      expect(latest.otherChanges, 1);
      expect(latest.editors, {'@bob:y.org'});
      expect(latest.byMe, isFalse);
      expect(latest.resettable, isTrue);
      final first = b.last;
      expect(first.added, 2);
      expect(first.otherChanges, 2);
      expect(first.byMe, isTrue);
      // Nothing before the group arrived — not a reset target.
      expect(first.resettable, isFalse);
    });

    test('a batch before the pruning floor is not resettable', () {
      final entries = [
        _mt(_meta('Trip'), 0),
        _ex(_e('e1', 'A'), 100 * _min),
        _ex(_e('e1', 'B', at: 2), 200 * _min),
      ];
      final b = changeBatches(entries, floor: 150 * _min);
      expect(b.map((x) => x.resettable), [true, false, false]);
    });
  });

  group('planGroupReset', () {
    // History: e1 "Dinner", e2 "Taxi", s1 (50), meta "Trip" — then (from
    // id 6 on) the attack: e1 edited, e2 deleted, e3 added, s1 deleted,
    // meta renamed.
    late List<HistoryEntry> entries;
    late int beforeId;
    setUp(() {
      entries = [
        _mt(_meta('Trip'), 1),
        _ex(_e('e1', 'Dinner'), 1),
        _ex(_e('e2', 'Taxi'), 1),
        _st(_s('s1'), 1),
        _mb(1),
      ];
      beforeId = 6;
      entries.addAll([
        _ex(_e('e1', 'Hacked', amount: 999, at: 5), 2),
        _ex(_e('e2', 'Taxi', at: 5, deleted: true), 2),
        _ex(_e('e3', 'New', at: 5), 2),
        _st(_s('s1', deleted: true), 2),
        _mt(_meta('Renamed', at: 5), 2),
      ]);
    });

    test('brings everything back as new versions', () {
      final plan = planGroupReset(
        groupId: 'g1',
        beforeId: beforeId,
        entries: entries,
        expenses: [
          _e('e1', 'Hacked', amount: 999, at: 5),
          _e('e2', 'Taxi', at: 5, deleted: true),
          _e('e3', 'New', at: 5),
        ],
        settlements: [_s('s1', deleted: true)],
        meta: _meta('Renamed', at: 5),
        now: 3,
      );
      expect(plan.restored, 2); // e2 + s1
      expect(plan.reverted, 1); // e1
      expect(plan.removed, 1); // e3
      ExpenseModel byId(String id) =>
          plan.changes.firstWhere((c) => c.expense?.id == id).expense!;
      expect(byId('e1').description, 'Dinner');
      expect(byId('e1').amountCents, 100);
      expect(byId('e1').deleted, isFalse);
      // The next LWW clock after the stored version, unsigned, origin kept.
      expect(byId('e1').updatedAt, 6);
      expect(byId('e1').sig, isNull);
      expect(byId('e1').origin, _origin);
      expect(byId('e2').deleted, isFalse);
      expect(byId('e3').deleted, isTrue);
      expect(byId('e3').description, 'New');
      final s1 = plan.changes.firstWhere((c) => c.settlement != null);
      expect(s1.effect, ResetEffect.restored);
      expect(s1.settlement!.deleted, isFalse);
      expect(plan.meta!.name, 'Trip');
      expect(plan.meta!.updatedAt, 6);
      // Members are never part of a reset.
      expect(plan.changes.every((c) => c.kind != RecordKind.member), isTrue);
    });

    test('unchanged records and records deleted then and now are left '
        'alone; resetting to now is empty', () {
      final plan = planGroupReset(
        groupId: 'g1',
        beforeId: 1000,
        entries: entries,
        expenses: [
          _e('e1', 'Hacked', amount: 999, at: 5),
          _e('e2', 'Taxi', at: 5, deleted: true),
          _e('e3', 'New', at: 5),
        ],
        settlements: [_s('s1', deleted: true)],
        meta: _meta('Renamed', at: 5),
        now: 3,
      );
      expect(plan.isEmpty, isTrue);
    });

    test('a record unknown before the point is removed; a deleted unknown '
        'one stays deleted', () {
      final plan = planGroupReset(
        groupId: 'g1',
        beforeId: 2, // only the meta existed
        entries: entries,
        expenses: [
          _e('e1', 'Dinner'),
          _e('e9', 'Gone', deleted: true),
          // Never in the history (e.g. an adopted legacy row): left alone.
          _e('e8', 'Legacy'),
        ],
        settlements: const [],
        meta: _meta('Trip'),
        now: 3,
      );
      expect(plan.changes, hasLength(1));
      expect(plan.changes.single.effect, ResetEffect.removed);
      expect(plan.changes.single.expense!.id, 'e1');
      expect(plan.meta, isNull);
    });

    test('an earlier version breaking today\'s rules is skipped', () {
      final bad = ExpenseModel(
        id: 'e1',
        roomId: 'g1',
        description: 'Bad split',
        amountCents: 100,
        currency: 'EUR',
        paidBy: 'p1',
        splitsJson: '{"p1":1}',
        createdAt: 1,
        updatedAt: 1,
      );
      final history = [_ex(bad, 1), _ex(_e('e1', 'Fixed', at: 3), 2)];
      final plan = planGroupReset(
        groupId: 'g1',
        beforeId: history[1].id,
        entries: history,
        expenses: [_e('e1', 'Fixed', at: 3)],
        settlements: const [],
        meta: null,
        now: 4,
      );
      expect(plan.changes, isEmpty);
      expect(plan.skipped, 1);
    });
  });
}
