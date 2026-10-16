/// G6: the digest's `rejected` map — refused versions never loop through
/// targeted repair, and "agree to disagree" counts as in sync.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';

void main() {
  DigestDiff diff({
    Map<String, int> local = const {'e1': 100},
    Map<String, Map<String, RecordVersion>> localRejected = const {},
    Map<String, String> localHashes = const {},
    required Map<String, dynamic> remote,
  }) => compareDigest(
    localMetaUpdatedAt: 1,
    localMembers: const {},
    localExpenses: local,
    localExpenseHashes: localHashes,
    localSettlements: const {},
    localRejected: localRejected,
    remote: {'meta_updated_at': 1, 'members': const {}, ...remote},
  );

  test('without rejections: an older peer is repaired', () {
    final d = diff(
      remote: {
        'expenses': {'e1': 50},
      },
    );
    expect(d.expenseIdsToSend, ['e1']);
    expect(d.identical, isFalse);
  });

  test('we do not re-send a version the sender refused', () {
    final d = diff(
      remote: {
        'expenses': {'e1': 50},
        'rejected': {
          'expenses': {'e1': 100},
        },
      },
    );
    expect(d.expenseIdsToSend, isEmpty);
    expect(d.identical, isTrue, reason: 'agree to disagree');
  });

  test('a sender holding exactly what we refused is not "newer"', () {
    final d = diff(
      localRejected: {
        'expense': {'e1': (at: 200, hash: '')},
      },
      remote: {
        'expenses': {'e1': 200},
      },
    );
    expect(d.senderHasNewer, isFalse);
    expect(d.identical, isTrue);
  });

  test('a version newer than the refused one is still news', () {
    final d = diff(
      localRejected: {
        'expense': {'e1': (at: 200, hash: '')},
      },
      remote: {
        'expenses': {'e1': 300},
      },
    );
    expect(d.senderHasNewer, isTrue);
    expect(d.identical, isFalse);
  });

  test('a refused record we never stored is not news either', () {
    final d = diff(
      local: const {},
      localRejected: {
        'expense': {'e9': (at: 5, hash: '')},
      },
      remote: {
        'expenses': {'e9': 5},
      },
    );
    expect(d.senderHasNewer, isFalse);
    expect(d.identical, isTrue);
  });

  test('refused member versions and meta behave the same', () {
    final d = compareDigest(
      localMetaUpdatedAt: 10,
      localMembers: const {'p1': (status: 'active', updatedAt: 5)},
      localExpenses: const {},
      localSettlements: const {},
      localRejected: const {
        'member': {'p1': (at: 9, hash: '')},
        'meta': {'g': (at: 20, hash: '')},
      },
      remote: const {
        'meta_updated_at': 20,
        'members': {
          'p1': {'status': 'removed', 'updated_at': 9},
        },
      },
    );
    expect(d.senderHasNewer, isFalse);
    expect(d.identical, isTrue);
  });

  test('digestRejectedMap converts kinds to the digest format', () {
    expect(
      digestRejectedMap({
        'expense': {'e1': (at: 1, hash: 'abcdef0123')},
        'member': {'p': (at: 2, hash: '')},
        'meta': {'g': (at: 3, hash: 'ff00ff00ff')},
      }),
      {
        'expenses': {'e1': '1:abcdef01'},
        'members': {'p': '2'},
        'meta': '3:ff00ff00',
      },
    );
    expect(digestRejectedMap(const {}), isEmpty);
  });

  // G18 review: a refusal names one exact version — it never suppresses the
  // repair of a different version of the record.
  group('exact refused versions', () {
    test('a refusal of a newer version does not stop repairing ours', () {
      final d = diff(
        remote: {
          'expenses': {'e1': 50},
          'rejected': {
            'expenses': {'e1': '200:aaaaaaaa'},
          },
        },
      );
      expect(d.expenseIdsToSend, ['e1']);
      expect(d.identical, isFalse);
    });

    test('same clock, other hash: still repaired', () {
      final d = diff(
        localHashes: const {'e1': 'bbbbbbbbbbbb'},
        remote: {
          'expenses': {'e1': '50:cccccccc'},
          'rejected': {
            'expenses': {'e1': '100:aaaaaaaa'},
          },
        },
      );
      expect(d.expenseIdsToSend, ['e1']);
    });

    test('same clock and hash: the refused version is not re-sent', () {
      final d = diff(
        localHashes: const {'e1': 'aaaaaaaabbbb'},
        remote: {
          'expenses': {'e1': '50:cccccccc'},
          'rejected': {
            'expenses': {'e1': '100:aaaaaaaa'},
          },
        },
      );
      expect(d.expenseIdsToSend, isEmpty);
      expect(d.identical, isTrue);
    });

    test('a lower version than the one we refused is news', () {
      final d = diff(
        localRejected: {
          'expense': {'e1': (at: 300, hash: '')},
        },
        remote: {
          'expenses': {'e1': 200},
        },
      );
      expect(d.senderHasNewer, isTrue);
    });
  });
}
