/// Unit tests for the SyncEngine's pure digest functions (plain Dart, no DB,
/// no package:matrix).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

void main() {
  group('buildDigestContent', () {
    test('maps records to id→updatedAt, tombstones included', () {
      const group = GroupModel(
        roomId: 'g1',
        name: 'Trip',
        currency: 'EUR',
        updatedAt: 7,
      );
      final content = buildDigestContent(
        group,
        [
          const MemberModel(
            groupId: 'g1',
            userId: '@a:x.org',
            status: 'active',
            updatedAt: 1,
          ),
          const MemberModel(
            groupId: 'g1',
            userId: '@b:y.org',
            status: 'removed',
            updatedAt: 2,
          ),
        ],
        [
          const ExpenseModel(
            id: 'e1',
            roomId: 'g1',
            description: 'x',
            amountCents: 1,
            currency: 'EUR',
            paidBy: '@a:x.org',
            splitsJson: '{}',
            createdAt: 1,
            updatedAt: 10,
          ),
          const ExpenseModel(
            id: 'e2',
            roomId: 'g1',
            description: 'gone',
            amountCents: 1,
            currency: 'EUR',
            paidBy: '@a:x.org',
            splitsJson: '{}',
            createdAt: 1,
            updatedAt: 20,
            deleted: true,
          ),
        ],
        [
          const SettlementModel(
            id: 's1',
            roomId: 'g1',
            amountCents: 1,
            currency: 'EUR',
            fromUser: '@b:y.org',
            toUser: '@a:x.org',
            createdAt: 1,
            updatedAt: 30,
          ),
        ],
        reply: false,
      );

      expect(content['v'], protocolVersion);
      expect(content['group'], 'g1');
      expect(content['reply'], false);
      expect(content['meta_updated_at'], 7);
      // id → "<updatedAt>:<hash8>" (G27), tombstone included.
      final exp = content['expenses'] as Map;
      expect(exp.keys, {'e1', 'e2'});
      expect(parseDigestVersion(exp['e1'])!.at, 10);
      expect(parseDigestVersion(exp['e2'])!.at, 20);
      expect(parseDigestVersion(exp['e1'])!.hash, hasLength(8));
      final st = content['settlements'] as Map;
      expect(parseDigestVersion(st['s1'])!.at, 30);
      expect(content['meta_hash'], hasLength(8));
      expect(content['members'], {
        '@a:x.org': {
          'status': 'active',
          'updated_at': 1,
          'name': '',
          'matrix_id': null,
        },
        '@b:y.org': {
          'status': 'removed',
          'updated_at': 2,
          'name': '',
          'matrix_id': null,
        },
      });
    });
  });

  group('compareDigest', () {
    const localMembers = {'@a:x.org': (status: 'active', updatedAt: 1)};
    const remoteMembers = {
      '@a:x.org': {'status': 'active', 'updated_at': 1},
    };

    Map<String, dynamic> remote({
      int meta = 5,
      Map<String, dynamic> expenses = const {},
      Map<String, dynamic> settlements = const {},
      Map<String, dynamic> members = remoteMembers,
    }) => {
      'v': 1,
      'group': 'g1',
      'reply': false,
      'meta_updated_at': meta,
      'members': members,
      'expenses': expenses,
      'settlements': settlements,
    };

    test('identical digests', () {
      final diff = compareDigest(
        localMetaUpdatedAt: 5,
        localMembers: localMembers,
        localExpenses: {'e1': 10},
        localSettlements: {'s1': 30},
        remote: remote(expenses: {'e1': 10}, settlements: {'s1': 30}),
      );
      expect(diff.identical, true);
      expect(diff.senderHasNewer, false);
      expect(diff.expenseIdsToSend, isEmpty);
      expect(diff.settlementIdsToSend, isEmpty);
      expect(diff.sendGroupMeta, false);
    });

    test('sender lacks a record — we re-send it', () {
      final diff = compareDigest(
        localMetaUpdatedAt: 5,
        localMembers: localMembers,
        localExpenses: {'e1': 10, 'e2': 20},
        localSettlements: {},
        remote: remote(expenses: {'e1': 10}),
      );
      expect(diff.expenseIdsToSend, ['e2']);
      expect(diff.senderHasNewer, false);
      expect(diff.identical, false);
    });

    test('sender has a stale revision — we re-send it (covers tombstones)', () {
      // e1 was deleted locally (tombstone at 20), the sender still has the
      // live revision (10): the tombstone must be re-sent, never the reverse.
      final diff = compareDigest(
        localMetaUpdatedAt: 5,
        localMembers: localMembers,
        localExpenses: {'e1': 20},
        localSettlements: {},
        remote: remote(expenses: {'e1': 10}),
      );
      expect(diff.expenseIdsToSend, ['e1']);
      expect(diff.senderHasNewer, false);
    });

    test(
      'sender has newer/unknown records — flagged so our reply repairs us',
      () {
        final diff = compareDigest(
          localMetaUpdatedAt: 5,
          localMembers: localMembers,
          localExpenses: {'e1': 10},
          localSettlements: {'s1': 30},
          remote: remote(
            expenses: {'e1': 15, 'e9': 1},
            settlements: {'s1': 30},
          ),
        );
        expect(diff.senderHasNewer, true);
        expect(diff.expenseIdsToSend, isEmpty);
        expect(diff.identical, false);
      },
    );

    test(
      'newer local group meta is re-sent; newer remote meta flags sender',
      () {
        final newerLocal = compareDigest(
          localMetaUpdatedAt: 9,
          localMembers: localMembers,
          localExpenses: {},
          localSettlements: {},
          remote: remote(meta: 5),
        );
        expect(newerLocal.sendGroupMeta, true);
        expect(newerLocal.identical, false);

        final newerRemote = compareDigest(
          localMetaUpdatedAt: 3,
          localMembers: localMembers,
          localExpenses: {},
          localSettlements: {},
          remote: remote(meta: 5),
        );
        expect(newerRemote.sendGroupMeta, false);
        expect(newerRemote.senderHasNewer, true);
      },
    );

    test('differing members break exactness but trigger no record sends', () {
      final diff = compareDigest(
        localMetaUpdatedAt: 5,
        localMembers: {
          '@a:x.org': (status: 'active', updatedAt: 1),
          '@b:y.org': (status: 'active', updatedAt: 2),
        },
        localExpenses: {},
        localSettlements: {},
        remote: remote(), // remote only knows @a
      );
      expect(diff.identical, false);
      expect(diff.expenseIdsToSend, isEmpty);
      expect(diff.senderHasNewer, false);
    });
  });
}
