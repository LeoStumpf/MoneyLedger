/// G27 version ordering (clock, then content hash) and the G14 bucket /
/// bootstrap-part helpers — pure functions.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/payload_budget.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

ExpenseModel _expense(
  String id, {
  String description = 'Dinner',
  int updatedAt = 100,
  RecordSignature? sig,
  bool pendingSign = false,
}) => ExpenseModel(
  id: id,
  roomId: 'g1',
  description: description,
  amountCents: 4200,
  currency: 'EUR',
  paidBy: '@a:x.org',
  splitsJson: '{"@a:x.org":2100,"@b:y.org":2100}',
  createdAt: 1,
  updatedAt: updatedAt,
  sig: sig,
  pendingSign: pendingSign,
);

const _sigA = RecordSignature(
  user: '@a:x.org',
  device: 'A',
  key: 'k',
  sig: 's',
);
const _sigB = RecordSignature(
  user: '@b:y.org',
  device: 'B',
  key: 'k',
  sig: 't',
);

void main() {
  group('version ordering (G27)', () {
    test('the clock decides first', () {
      expect(
        compareVersions((at: 2, hash: '00'), (at: 1, hash: 'ff')),
        greaterThan(0),
      );
      expect(
        compareVersions((at: 1, hash: 'ff'), (at: 2, hash: '00')),
        lessThan(0),
      );
    });

    test('same clock: the higher hash wins, same hash is the same version', () {
      expect(
        compareVersions((at: 5, hash: 'b0'), (at: 5, hash: 'a9')),
        greaterThan(0),
      );
      expect(compareVersions((at: 5, hash: 'ab'), (at: 5, hash: 'ab')), 0);
      expect(versionWins((at: 5, hash: 'ab'), (at: 5, hash: 'ab')), isFalse);
      expect(versionWins((at: 5, hash: 'ab'), null), isTrue);
    });

    test('an unknown hash ties; a short digest hash compares by prefix', () {
      expect(compareVersions((at: 5, hash: ''), (at: 5, hash: 'ff')), 0);
      final full = expenseVersionHash(_expense('e1'));
      expect(
        compareVersions(
          (at: 100, hash: full),
          (at: 100, hash: full.substring(0, kDigestHashChars)),
        ),
        0,
      );
    });

    test('content changes the hash; signatures / pending flag do not', () {
      final base = _expense('e1');
      expect(
        expenseVersionHash(_expense('e1', description: 'Lunch')),
        isNot(expenseVersionHash(base)),
      );
      expect(
        expenseVersionHash(_expense('e1', sig: _sigA)),
        expenseVersionHash(_expense('e1', sig: _sigB, pendingSign: true)),
      );
      expect(expenseVersionHash(base), hasLength(64));
    });

    test('digest encoding round-trips; bare ints parse without a hash', () {
      final v = expenseVersion(_expense('e1'));
      final enc = encodeDigestVersion(v);
      expect(enc, startsWith('100:'));
      expect(parseDigestVersion(enc), (
        at: 100,
        hash: v.hash.substring(0, kDigestHashChars),
      ));
      expect(parseDigestVersion(42), (at: 42, hash: ''));
      expect(parseDigestVersion('x:1'), isNull);
      expect(parseDigestVersion(null), isNull);
    });
  });

  group('digest buckets (G14)', () {
    test('bucket hashes are order-independent and content-sensitive', () {
      final a = {
        'e1': (at: 1, hash: 'aa'),
        'e2': (at: 2, hash: 'bb'),
        'e3': (at: 3, hash: 'cc'),
      };
      final reversed = Map.fromEntries(a.entries.toList().reversed);
      final h1 = digestBucketHashes(expenses: a, settlements: {}, bits: 4);
      final h2 = digestBucketHashes(
        expenses: reversed,
        settlements: {},
        bits: 4,
      );
      expect(h1, h2);
      expect(h1, hasLength(16));
      final changed = digestBucketHashes(
        expenses: {...a, 'e2': (at: 2, hash: 'bc')},
        settlements: {},
        bits: 4,
      );
      final b = digestBucketOf('e2', 4);
      for (var i = 0; i < 16; i++) {
        expect(changed[i] == h1[i], i != b, reason: 'bucket $i');
      }
      expect(h1.where((h) => h.isEmpty).length, greaterThanOrEqualTo(13));
    });

    test('bucket bits grow with the record count, bounded', () {
      expect(digestBucketBitsFor(0), kMinDigestBucketBits);
      expect(digestBucketBitsFor(1000), 6);
      expect(digestBucketBitsFor(5000), 9);
      expect(digestBucketBitsFor(10000000), kMaxDigestBucketBits);
    });
  });

  group('bootstrap parts (G14)', () {
    const group = GroupModel(
      roomId: 'g1',
      name: 'Trip',
      currency: 'EUR',
      updatedAt: 1,
      sig: _sigA,
    );
    const members = [
      MemberModel(
        groupId: 'g1',
        userId: '@a:x.org',
        matrixId: '@a:x.org',
        status: 'active',
        updatedAt: 1,
        sig: _sigA,
      ),
      MemberModel(
        groupId: 'g1',
        userId: '@b:y.org',
        matrixId: '@b:y.org',
        status: 'active',
        updatedAt: 1,
        sig: _sigA,
      ),
    ];
    final expenses = [for (var i = 0; i < 60; i++) _expense('e$i', sig: _sigA)];
    const settlements = [
      SettlementModel(
        id: 's1',
        roomId: 'g1',
        amountCents: 5,
        currency: 'EUR',
        fromUser: '@b:y.org',
        toUser: '@a:x.org',
        createdAt: 1,
        updatedAt: 2,
        sig: _sigB,
      ),
    ];

    test('a small snapshot is one part, identical to the plain bootstrap', () {
      final parts = buildBootstrapParts(
        'g1',
        group,
        members,
        expenses,
        settlements,
        budget: kMaxPayloadBytes,
      );
      expect(parts, hasLength(1));
      expect(
        parts.single,
        buildBootstrapContent('g1', group, members, expenses, settlements),
      );
    });

    test('a large one: disjoint record slices, each part self-contained', () {
      final parts = buildBootstrapParts(
        'g1',
        group,
        members,
        expenses,
        settlements,
        deviceKeys: const {
          '@a:x.org': {'A': 'k'},
        },
        budget: 4000,
      );
      expect(parts.length, greaterThan(3));
      final ids = <String>[];
      for (final (i, p) in parts.indexed) {
        expect(encodedPayloadBytes(p), lessThanOrEqualTo(4000));
        expect(p['part'], i + 1);
        expect(p['parts'], parts.length);
        expect(p['group'], 'g1');
        expect(p['meta'], isNotNull, reason: 'TOFU works on any part');
        expect(p['members'], hasLength(2), reason: 'gate needs the members');
        expect(p['device_keys'], isNotEmpty);
        for (final e in p['expenses'] as List) {
          ids.add((e as Map)['id'] as String);
        }
        for (final s in p['settlements'] as List) {
          ids.add((s as Map)['id'] as String);
        }
      }
      expect(ids.toSet(), {for (final e in expenses) e.id, 's1'});
      expect(ids, hasLength(61), reason: 'each record exactly once');
    });
  });
}
