/// G6: the digest's `rejected` map — refused versions never loop through
/// targeted repair, and "agree to disagree" counts as in sync.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';

void main() {
  DigestDiff diff({
    Map<String, int> local = const {'e1': 100},
    Map<String, Map<String, int>> localRejected = const {},
    required Map<String, dynamic> remote,
  }) => compareDigest(
    localMetaUpdatedAt: 1,
    localMembers: const {},
    localExpenses: local,
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
        'expense': {'e1': 200},
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
        'expense': {'e1': 200},
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
        'expense': {'e9': 5},
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
        'member': {'p1': 9},
        'meta': {'g': 20},
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
        'expense': {'e1': 1},
        'member': {'p': 2},
        'meta': {'g': 3},
      }),
      {
        'expenses': {'e1': 1},
        'members': {'p': 2},
        'meta': 3,
      },
    );
    expect(digestRejectedMap(const {}), isEmpty);
  });
}
