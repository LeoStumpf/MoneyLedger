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
        _ex(_e('e1', 'Dinner'), t0),
        _ex(_e('e2', 'Taxi'), t0 + 1),
        // Batch 2 (an hour later, Bob): e1 edited twice, e2 deleted, e3 new.
        _ex(_e('e1', 'Dinner!', at: 2, sig: _bobSig), t0 + 60 * _min),
        _ex(_e('e1', 'Dinner!!', at: 3, sig: _bobSig), t0 + 61 * _min),
        _ex(
          _e('e2', 'Taxi', at: 2, deleted: true, sig: _bobSig),
          t0 + 62 * _min,
        ),
        _ex(_e('e3', 'Bar', sig: _bobSig), t0 + 63 * _min),
        _mt(
          const GroupModel(
            roomId: 'g1',
            name: 'Trip 2',
            currency: 'EUR',
            updatedAt: 2,
            sig: _bobSig,
          ),
          t0 + 63 * _min,
        ),
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
      expect(first.byMe, isFalse);
      // Nothing before the group arrived — not a reset target.
      expect(first.resettable, isFalse);
      expect(first.base, isTrue);
      expect(latest.base, isFalse);
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

  group('changeBatches — G62 (base batch + author boundaries)', () {
    const me = '@ann:x.org';
    const meSig = RecordSignature(user: me, device: 'A2', key: 'KA2', sig: 'M');

    /// The plan for undoing [batch], given the current stored records.
    GroupResetPlan undo(
      ChangeBatch batch,
      List<HistoryEntry> entries,
      List<ExpenseModel> now, {
      GroupModel? meta,
    }) => planGroupReset(
      groupId: 'g1',
      beforeId: batch.firstId,
      entries: entries,
      expenses: now,
      settlements: const [],
      meta: meta ?? _meta('Trip'),
      now: 1000,
    );

    test('DEV-H repro: after the v12 backfill, edits < 10 min later are '
        'offered (the initial entries are a base of their own)', () {
      final t0 = 5000000;
      HistoryEntry init(HistoryEntry e) => HistoryEntry(
        id: e.id,
        groupId: e.groupId,
        kind: e.kind,
        recordId: e.recordId,
        updatedAt: e.updatedAt,
        versionHash: e.versionHash,
        content: e.content,
        source: HistorySource.initial,
        recordedAt: e.recordedAt,
      );
      final entries = [
        // The v12 migration: one `initial` entry per stored record.
        init(_mt(_meta('Trip'), t0)),
        init(_mb(t0)),
        for (final id in ['e1', 'e2', 'e3', 'e4']) init(_ex(_e(id, id), t0)),
        // The user, a minute after the update: edits, adds, deletes.
        _ex(_e('e1', 'e1!', at: 2), t0 + _min, source: HistorySource.local),
        _ex(_e('e5', 'New', at: 2), t0 + 2 * _min, source: HistorySource.local),
        _ex(
          _e('e2', 'e2', at: 2, deleted: true),
          t0 + 3 * _min,
          source: HistorySource.local,
        ),
      ];
      final b = changeBatches(entries, me: me);
      expect(b, hasLength(2));
      expect(b.last.base, isTrue);
      expect(b.last.resettable, isFalse);
      expect(b.last.added, 4);
      final mine = b.first;
      expect(mine.resettable, isTrue);
      expect(mine.byMe, isTrue);
      expect((mine.added, mine.changed, mine.deleted), (1, 1, 1));
      // Undo from here = the state after the update (just before the batch).
      final plan = undo(mine, entries, [
        _e('e1', 'e1!', at: 2),
        _e('e2', 'e2', at: 2, deleted: true),
        _e('e3', 'e3'),
        _e('e4', 'e4'),
        _e('e5', 'New', at: 2),
      ]);
      expect((plan.restored, plan.reverted, plan.removed), (1, 1, 1));
    });

    test('a brand-new group: its first expenses right after creating it '
        'are an undo point', () {
      final t0 = 5000000;
      final entries = [
        // GroupCreator: meta + the creator, one write.
        _entry(
          RecordKind.meta,
          'g1',
          groupMetaPayload(_meta('Trip')),
          t0,
          source: HistorySource.local,
        ),
        _entry(
          RecordKind.member,
          'p1',
          _mb(t0).content,
          t0 + 3,
          source: HistorySource.local,
        ),
        // Seconds later — a quick first expense is not part of creating
        // the group (local arrival window: 2 s).
        _ex(_e('e1', 'Dinner'), t0 + 5000, source: HistorySource.local),
        _ex(_e('e2', 'Taxi'), t0 + 2 * _min, source: HistorySource.local),
      ];
      final b = changeBatches(entries, me: me);
      expect(b, hasLength(2));
      expect(b.last.base, isTrue);
      expect(b.last.otherChanges, 2);
      expect(b.first.resettable, isTrue);
      expect(b.first.added, 2);
      final plan = undo(b.first, entries, [
        _e('e1', 'Dinner'),
        _e('e2', 'Taxi'),
      ]);
      expect(plan.removed, 2);
      expect(plan.meta, isNull);
    });

    test('a received bootstrap (several signers, chunked parts) is one '
        'base; my edits right after it are an undo point', () {
      final t0 = 5000000;
      final entries = [
        _mt(_meta('Trip'), t0),
        _mb(t0 + 2),
        _ex(_e('e1', 'Dinner', sig: _bobSig), t0 + 4),
        _ex(_e('e2', 'Taxi', sig: meSig), t0 + 6),
        // Part 2 of the snapshot, a few seconds later.
        _ex(_e('e3', 'Bar'), t0 + 8000),
        // Me, a minute later.
        _ex(_e('e1', 'Dinner!', at: 2), t0 + _min, source: HistorySource.local),
      ];
      final b = changeBatches(entries, me: me);
      expect(b, hasLength(2));
      expect(b.last.base, isTrue);
      expect(b.last.lastId, entries[4].id);
      expect(b.last.added, 3);
      expect(b.first.resettable, isTrue);
      expect(b.first.changed, 1);
      final plan = undo(b.first, entries, [
        _e('e1', 'Dinner!', at: 2),
        _e('e2', 'Taxi', sig: meSig),
        _e('e3', 'Bar'),
      ]);
      expect(plan.reverted, 1);
      expect(plan.changes.single.expense!.description, 'Dinner');
    });

    test('a group adopted from local mode (one transaction, records '
        'included) is one base', () {
      final t0 = 5000000;
      final entries = [
        _entry(
          RecordKind.meta,
          'g1',
          groupMetaPayload(_meta('Trip')),
          t0,
          source: HistorySource.local,
        ),
        _ex(_e('e1', 'Dinner'), t0 + 1, source: HistorySource.local),
        _ex(_e('e2', 'Taxi'), t0 + 2, source: HistorySource.local),
        _ex(_e('e3', 'Bar'), t0 + 3 * _min, source: HistorySource.local),
      ];
      final b = changeBatches(entries, me: me);
      expect(b, hasLength(2));
      expect(b.last.base, isTrue);
      expect(b.last.added, 2);
      expect(b.first.resettable, isTrue);
      expect(b.first.added, 1);
    });

    test('a second version of a record ends the arrival (it is an edit)', () {
      final t0 = 5000000;
      final entries = [
        _mt(_meta('Trip'), t0),
        _ex(_e('e1', 'Dinner'), t0 + 2),
        _ex(_e('e1', 'Dinner!', at: 2, sig: _bobSig), t0 + 1000),
      ];
      final b = changeBatches(entries, me: me);
      expect(b, hasLength(2));
      expect(b.first.resettable, isTrue);
      expect(b.first.changed, 1);
    });

    test('a pause longer than the arrival window ends the base', () {
      final t0 = 5000000;
      final entries = [
        _mt(_meta('Trip'), t0),
        _ex(_e('e1', 'Dinner', sig: _bobSig), t0 + _min),
      ];
      final b = changeBatches(entries, me: me);
      expect(b.map((x) => (x.base, x.resettable)), [
        (false, true),
        (true, false),
      ]);
    });

    test('a restored / imported group is a base too', () {
      for (final source in [HistorySource.restore, HistorySource.csvImport]) {
        final t0 = 5000000;
        final entries = [
          _entry(
            RecordKind.meta,
            'g1',
            groupMetaPayload(_meta('Trip')),
            t0,
            source: source,
          ),
          _ex(_e('e1', 'Dinner'), t0 + 1, source: source),
          _ex(_e('e2', 'Taxi'), t0 + _min, source: HistorySource.local),
        ];
        final b = changeBatches(entries, me: me);
        expect(b, hasLength(2), reason: source.wire);
        expect(b.last.base, isTrue);
        expect(b.first.resettable, isTrue);
        expect(b.first.added, 1);
      }
    });

    test('another author starts a new batch: undoing Bob\'s deletes keeps '
        'my edits from minutes before', () {
      final t0 = 5000000;
      final entries = [
        _mt(_meta('Trip'), t0),
        _ex(_e('e1', 'Dinner'), t0 + 1),
        _ex(_e('e2', 'Taxi'), t0 + 2),
        // Me, an hour later.
        _ex(
          _e('e1', 'Dinner!', at: 2),
          t0 + 60 * _min,
          source: HistorySource.local,
        ),
        // My other device (signed by my account) — same author.
        _ex(_e('e3', 'Bar', sig: meSig), t0 + 61 * _min),
        // Bob, 3 minutes later: deletes everything.
        for (final (id, d) in [
          ('e1', 'Dinner!'),
          ('e2', 'Taxi'),
          ('e3', 'Bar'),
        ])
          _ex(_e(id, d, at: 3, deleted: true, sig: _bobSig), t0 + 64 * _min),
      ];
      final b = changeBatches(entries, me: me);
      expect(b, hasLength(3));
      final bob = b[0];
      final mine = b[1];
      expect(bob.editors, {'@bob:y.org'});
      expect(bob.byMe, isFalse);
      expect(bob.deleted, 3);
      expect(mine.byMe, isTrue);
      expect(mine.editors, isEmpty);
      expect((mine.added, mine.changed), (1, 1));
      expect([bob.resettable, mine.resettable], [true, true]);
      final plan = undo(bob, entries, [
        _e('e1', 'Dinner!', at: 3, deleted: true),
        _e('e2', 'Taxi', at: 3, deleted: true),
        _e('e3', 'Bar', at: 3, deleted: true),
      ]);
      expect(plan.restored, 3);
      final e1 = plan.changes.firstWhere((c) => c.expense!.id == 'e1');
      expect(e1.expense!.description, 'Dinner!');
    });

    test('no meta in the history: nothing is resettable (unchanged)', () {
      final b = changeBatches([
        _ex(_e('e1', 'Dinner'), 0),
        _ex(_e('e1', 'Dinner!', at: 2), 60 * _min),
      ]);
      expect(b.every((x) => !x.resettable && !x.base), isTrue);
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

    test('G49: the expense date travels with the content — a reset brings '
        'back the earlier day', () {
      ExpenseModel dated(String date, int at) => ExpenseModel(
        id: 'e1',
        roomId: 'g1',
        description: 'Dinner',
        amountCents: 100,
        currency: 'EUR',
        paidBy: 'p1',
        splitsJson: '{"p1":100}',
        createdAt: 1,
        updatedAt: at,
        origin: _origin,
        date: date,
      );
      final first = _ex(dated('2026-01-05', 1), 1);
      final second = _ex(dated('2026-02-01', 5), 2);
      final plan = planGroupReset(
        groupId: 'g1',
        beforeId: second.id,
        entries: [first, second],
        expenses: [dated('2026-02-01', 5)],
        settlements: const [],
        meta: null,
        now: 3,
      );
      expect(plan.reverted, 1);
      expect(plan.changes.single.expense!.date, '2026-01-05');
    });
  });
}
