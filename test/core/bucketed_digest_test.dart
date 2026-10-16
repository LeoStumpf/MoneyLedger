/// G14 bucketed digests + G27 same-clock detection in the pure digest
/// functions ([buildDigestMessages], [compareDigest]).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/sync/payload_budget.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

const _group = GroupModel(
  roomId: 'g1',
  name: 'Trip',
  currency: 'EUR',
  updatedAt: 1,
);
const _members = [
  MemberModel(
    groupId: 'g1',
    userId: '@a:x.org',
    matrixId: '@a:x.org',
    status: 'active',
    updatedAt: 1,
  ),
];

ExpenseModel _e(int i, {int at = 100, String description = 'Dinner'}) =>
    ExpenseModel(
      id: '0199e3a0-0000-7000-a000-${i.toString().padLeft(12, '0')}',
      roomId: 'g1',
      description: description,
      amountCents: 100 + i,
      currency: 'EUR',
      paidBy: '@a:x.org',
      splitsJson: '{"@a:x.org":${100 + i}}',
      createdAt: 1,
      updatedAt: at,
    );

/// [compareDigest] for local [expenses] against [remote].
DigestDiff _compare(
  List<ExpenseModel> expenses,
  Map<String, dynamic> remote,
) => compareDigest(
  localMetaUpdatedAt: _group.updatedAt,
  localMetaHash: groupMetaVersionHash(_group),
  localMembers: {
    for (final m in _members)
      m.userId: (status: m.status, updatedAt: m.updatedAt),
  },
  localMemberHashes: {for (final m in _members) m.userId: memberVersionHash(m)},
  localExpenses: {for (final e in expenses) e.id: e.updatedAt},
  localExpenseHashes: {for (final e in expenses) e.id: expenseVersionHash(e)},
  localSettlements: const {},
  remote: remote,
);

List<Map<String, dynamic>> _digest(
  List<ExpenseModel> expenses, {
  int budget = kMaxPayloadBytes,
  int? bits,
  Set<int> detail = const {},
  bool reply = false,
}) => buildDigestMessages(
  _group,
  _members,
  expenses,
  const [],
  reply: reply,
  budget: budget,
  bits: bits,
  detail: detail,
);

void main() {
  final records = [for (var i = 0; i < 200; i++) _e(i)];

  test('fits → one flat digest; too big → one bucketed summary', () {
    final flat = _digest(records);
    expect(flat, hasLength(1));
    expect(flat.single.containsKey('bucket_bits'), isFalse);

    final bucketed = _digest(records, budget: 3000);
    expect(bucketed, hasLength(1));
    final m = bucketed.single;
    expect(m['bucket_bits'], digestBucketBitsFor(200));
    expect(m['buckets'], hasLength(1 << (m['bucket_bits'] as int)));
    expect(m['detail'], isEmpty);
    expect(m['expenses'], isEmpty);
    expect(m['members'], isNotEmpty, reason: 'gossip stays in every digest');
    expect(encodedPayloadBytes(m), lessThanOrEqualTo(3000));
  });

  test('detail is spread over several messages within the budget', () {
    final all = {for (var b = 0; b < 16; b++) b};
    final msgs = _digest(records, budget: 3000, bits: 4, detail: all);
    expect(msgs.length, greaterThan(1));
    final detailed = <int>{};
    var entries = 0;
    for (final m in msgs) {
      expect(encodedPayloadBytes(m), lessThanOrEqualTo(3000));
      detailed.addAll((m['detail'] as List).cast<int>());
      entries += (m['expenses'] as Map).length;
    }
    expect(detailed, all);
    expect(entries, 200);
  });

  test('same state: every bucket matches → identical, nothing to do', () {
    final remote = _digest(records, budget: 3000).single;
    final d = _compare(records, remote);
    expect(d.identical, isTrue);
    expect(d.unresolvedBuckets, isEmpty);
    expect(d.expenseIdsToSend, isEmpty);
    expect(d.bucketBits, 4);
  });

  test('a differing bucket is unresolved until detailed, then repaired', () {
    // The sender lacks record 7.
    final theirs = [...records]..removeAt(7);
    final b = digestBucketOf(records[7].id, 4);
    final summary = _digest(theirs, budget: 3000, bits: 4).single;
    final d1 = _compare(records, summary);
    expect(d1.unresolvedBuckets, {b});
    expect(d1.identical, isFalse);
    expect(d1.expenseIdsToSend, isEmpty, reason: 'no entries for bucket $b');

    final detail = _digest(theirs, budget: 3000, bits: 4, detail: {b}).single;
    final d2 = _compare(records, detail);
    expect(d2.unresolvedBuckets, isEmpty);
    expect(d2.expenseIdsToSend, [records[7].id]);
    expect(d2.differingIds, {records[7].id});
    expect(d2.detailBuckets, {b});
  });

  test('G27: same clock, different content — the higher hash is sent', () {
    final mine = _e(1, description: 'Dinner');
    final other = _e(1, description: 'Lunch');
    final mineWins =
        expenseVersionHash(mine).compareTo(expenseVersionHash(other)) > 0;
    final winner = mineWins ? mine : other;
    final loser = mineWins ? other : mine;

    // Flat: the side holding the winner re-sends it; the other side only
    // learns that the sender is newer.
    final atWinner = _compare([winner], _digest([loser]).single);
    expect(atWinner.expenseIdsToSend, [winner.id]);
    expect(atWinner.senderHasNewer, isFalse);
    final atLoser = _compare([loser], _digest([winner]).single);
    expect(atLoser.expenseIdsToSend, isEmpty);
    expect(atLoser.senderHasNewer, isTrue);
    expect(atLoser.identical, isFalse);

    // Same version on both sides → identical.
    expect(_compare([winner], _digest([winner]).single).identical, isTrue);

    // Bucketed: the bucket hashes differ although the clocks are equal.
    final summary = _digest([loser], budget: 100, bits: 4).single;
    expect(_compare([winner], summary).unresolvedBuckets, {
      digestBucketOf(winner.id, 4),
    });
  });

  test('a digest without hashes (bare clocks) still compares by clock', () {
    final d = _compare(
      [_e(1)],
      {
        'group': 'g1',
        'meta_updated_at': 1,
        'members': {
          '@a:x.org': {'status': 'active', 'updated_at': 1},
        },
        'expenses': {_e(1).id: 100},
      },
    );
    expect(d.expenseIdsToSend, isEmpty);
    expect(d.senderHasNewer, isFalse);
  });
}
