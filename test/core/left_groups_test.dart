/// G9: the pure left-group tombstone helpers and the LedgerSyncer gate for a
/// group we left / deleted.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/sync/left_groups.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';

const me = '@bob:y.org';

Map<String, dynamic> rec(String? mxid, String status, int at) => {
  'matrix_id': mxid,
  'status': status,
  'updated_at': at,
};

void main() {
  group('classifyPeerViewOfMe', () {
    PeerViewOfMe classify(List<Object?> records) =>
        classifyPeerViewOfMe(memberRecords: records, myMxid: me, leftAt: 100);

    test('unaware when we are absent or removed', () {
      expect(classify([rec('@a:x', 'active', 500)]), PeerViewOfMe.unaware);
      expect(classify([rec(me, 'removed', 500)]), PeerViewOfMe.unaware);
    });
    test('stale when we are active with an older / equal clock', () {
      expect(classify([rec(me, 'active', 100)]), PeerViewOfMe.staleActive);
    });
    test('re-added when we are active with a newer clock', () {
      expect(
        classify([rec(me, 'active', 50), rec(me, 'active', 101)]),
        PeerViewOfMe.readded,
      );
    });
  });

  test('tombstone round-trips; corrupt values still mean "left"', () {
    const t = LeftGroupTombstone(
      leftAt: 7,
      removalNotice: {'status': 'removed'},
    );
    final back = LeftGroupTombstone.decode(t.encode())!;
    expect(back.leftAt, 7);
    expect(back.removalNotice, {'status': 'removed'});
    expect(
      LeftGroupTombstone.decode(
        const LeftGroupTombstone(leftAt: 3).encode(),
      )!.removalNotice,
      isNull,
    );
    expect(LeftGroupTombstone.decode('not json'), isNotNull);
    expect(LeftGroupTombstone.decode(null), isNull);
  });

  group('LedgerSyncer.acceptsForLeftGroup', () {
    const tomb = LeftGroupTombstone(leftAt: 100);
    bool accepts(String type, List members, {String? myMxid = me}) =>
        LedgerSyncer.acceptsForLeftGroup(
          type: type,
          content: {'group': 'g', 'members': members},
          myMxid: myMxid,
          tombstone: tomb,
        );

    test('a bootstrap that re-adds us is accepted', () {
      expect(accepts(bootstrapEventType, [rec(me, 'active', 200)]), isTrue);
    });
    test('a stale bootstrap (old clock / removed) is dropped', () {
      expect(accepts(bootstrapEventType, [rec(me, 'active', 90)]), isFalse);
      expect(accepts(bootstrapEventType, [rec(me, 'removed', 200)]), isFalse);
      expect(accepts(bootstrapEventType, const []), isFalse);
    });
    test('every other record type is dropped', () {
      for (final t in [
        expenseEventType,
        settlementEventType,
        groupMetaEventType,
        memberEventType,
      ]) {
        expect(accepts(t, [rec(me, 'active', 200)]), isFalse, reason: t);
      }
    });
    test('unknown own MXID → dropped', () {
      expect(
        accepts(bootstrapEventType, [rec(me, 'active', 200)], myMxid: null),
        isFalse,
      );
    });
  });
}
