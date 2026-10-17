import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/link/link_envelope.dart';
import 'package:money_ledger/core/link/link_keys.dart';
import 'package:money_ledger/core/link/link_snapshot.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

const _group = '0192a6b4-7c3e-7a01-9f00-5e1d2c3b4a59';

String _uuid(Random r) {
  final h = hexOf(List<int>.generate(16, (_) => r.nextInt(256)));
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-7${h.substring(13, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// A bootstrap (unsigned, like a pure link group) with [expenses] expenses
/// and [settlements] payments; incompressible notes when [noisy].
Map<String, dynamic> _bootstrap({
  int expenses = 20,
  int settlements = 3,
  bool noisy = false,
}) {
  final r = Random(7);
  final members = [
    for (var i = 0; i < 4; i++)
      MemberModel(
        groupId: _group,
        userId: 'p$i',
        displayName: 'Person $i',
        status: 'active',
        updatedAt: 1760000000000 + i,
      ),
  ];
  String noise() => hexOf(List<int>.generate(60, (_) => r.nextInt(256)));
  return buildBootstrapContent(
    _group,
    GroupModel(
      roomId: _group,
      name: 'Trip',
      currency: 'EUR',
      updatedAt: 1760000000000,
    ),
    members,
    [
      for (var i = 0; i < expenses; i++)
        ExpenseModel(
          id: _uuid(r),
          roomId: _group,
          description: 'Dinner $i',
          amountCents: 1000 + i,
          currency: 'EUR',
          paidBy: 'p${i % 4}',
          splitsJson: '{"p0":${500 + i},"p1":500}',
          createdAt: 1760000000000 + i,
          updatedAt: 1760000000000 + i,
          deleted: i % 9 == 0,
          note: noisy ? noise() : null,
        ),
    ],
    [
      for (var i = 0; i < settlements; i++)
        SettlementModel(
          id: _uuid(r),
          roomId: _group,
          amountCents: 300,
          currency: 'EUR',
          fromUser: 'p1',
          toUser: 'p2',
          createdAt: 1760000000000 + i,
          updatedAt: 1760000000000 + i,
        ),
    ],
  );
}

Set<String> _ids(Map<String, dynamic> part) => {
  for (final e in part['expenses'] as List) (e as Map)['id'] as String,
  for (final s in part['settlements'] as List) (s as Map)['id'] as String,
};

void main() {
  test('part topics', () {
    expect(linkPartTopic('t', 0), 't');
    expect(linkPartTopic('t', 3), 't.3');
    expect(linkPartTopics('t'), [
      't',
      't.1',
      't.2',
      't.3',
      't.4',
      't.5',
      't.6',
      't.7',
    ]);
    expect(() => linkPartTopic('t', 8), throwsRangeError);
    expect(() => linkPartTopic('t', -1), throwsRangeError);
  });

  test('linkPartOf = fnv1a(id) % parts, stable', () {
    // FNV-1a 32 of "a" = 0xe40c292c.
    expect(linkPartOf('a', 1), 0);
    expect(linkPartOf('a', 2), 0xe40c292c % 2);
    expect(linkPartOf('a', 4), 0xe40c292c % 4);
    expect(linkPartOf('a', 8), 0xe40c292c % 8);
    expect(() => linkPartOf('a', 3), throwsArgumentError);
    // Halving the part count folds part i and i + n/2 together.
    final r = Random(1);
    for (var i = 0; i < 100; i++) {
      final id = _uuid(r);
      expect(linkPartOf(id, 8) % 4, linkPartOf(id, 4));
      expect(linkPartOf(id, 4) % 2, linkPartOf(id, 2));
    }
  });

  test('the header replaces the bootstrap header; records keep v 2', () {
    final b = _bootstrap();
    final s = buildLinkSnapshotPart(b, me: 'p0', app: '1.4.0');
    expect(s['format'], 'moneyledger-link');
    expect(s['v'], 1);
    expect(s['group'], _group);
    expect(s['me'], 'p0');
    expect(s['part'], 0);
    expect(s['parts'], 1);
    expect(s['app'], '1.4.0');
    for (final k in ['name', 'currency', 'updated_at', 'meta', 'members']) {
      expect(s[k], b[k], reason: k);
    }
    expect(s['expenses'], b['expenses']);
    expect(s['settlements'], b['settlements']);
    expect(((s['expenses'] as List).first as Map)['v'], protocolVersion);
    expect(s.keys.take(7), [
      'format',
      'v',
      'group',
      'me',
      'part',
      'parts',
      'app',
    ]);
    final h = parseLinkSnapshotHeader(s);
    expect(h.group, _group);
    expect(h.me, 'p0');
    expect((h.part, h.parts, h.retired), (0, 1, false));
  });

  test('a small group is one part, all records', () {
    final b = _bootstrap();
    final plan = planLinkSnapshot(b, me: 'p0', app: '1');
    expect(plan.parts, hasLength(1));
    expect(_ids(plan.parts.single.snapshot), hasLength(23));
    expect(plan.parts.single.contentLength, lessThan(kLinkContentBudget));
  });

  test('shards up to 2 / 4 / 8 parts within the budget', () {
    final b = _bootstrap(expenses: 200, settlements: 20, noisy: true);
    final all = _ids({
      'expenses': b['expenses'],
      'settlements': b['settlements'],
    });
    final single = planLinkSnapshot(b, me: 'p0', app: '1', budget: 1 << 30);
    final size = single.parts.single.contentLength;
    for (final (budget, parts) in [
      (size, 1),
      (size * 3 ~/ 4, 2),
      (size * 3 ~/ 8, 4),
      (size * 3 ~/ 16, 8),
    ]) {
      final plan = planLinkSnapshot(b, me: 'p0', app: '1', budget: budget);
      expect(plan.parts, hasLength(parts), reason: '$budget');
      final seen = <String>{};
      for (final (i, p) in plan.parts.indexed) {
        expect(p.index, i);
        expect(p.contentLength, lessThanOrEqualTo(budget));
        expect(p.snapshot['part'], i);
        expect(p.snapshot['parts'], parts);
        expect(p.snapshot['members'], b['members']); // self-contained
        expect(p.snapshot['meta'], b['meta']);
        final ids = _ids(p.snapshot);
        expect(seen.intersection(ids), isEmpty); // disjoint
        seen.addAll(ids);
        for (final id in ids) {
          expect(linkPartOf(id, parts), i);
        }
      }
      expect(seen, all); // complete
    }
  });

  test('a sealed part fits the budget it was planned for', () async {
    final b = _bootstrap(expenses: 300, noisy: true);
    final keys = await deriveLinkKeys(List.filled(32, 1));
    final plan = planLinkSnapshot(b, me: 'p0', app: '1', budget: 20000);
    expect(plan.parts.length, greaterThan(1));
    for (final p in plan.parts) {
      final d = linkPartTopic(keys.topic, p.index);
      final c = await sealLinkContent(
        p.packed,
        keys.encKey,
        d: d,
        pubkey: 'ab' * 32,
      );
      expect(c.length, p.contentLength);
      expect(c.length, lessThanOrEqualTo(20000));
      final back = await openLinkContent(
        c,
        keys.encKey,
        d: d,
        pubkey: 'ab' * 32,
      );
      expect(back, p.snapshot);
    }
  });

  test('too big for 8 parts → LinkSnapshotTooLargeException', () {
    final b = _bootstrap(expenses: 100, noisy: true);
    expect(
      () => planLinkSnapshot(b, me: 'p0', app: '1', budget: 500),
      throwsA(
        isA<LinkSnapshotTooLargeException>()
            .having((e) => e.budget, 'budget', 500)
            .having((e) => e.largestContentLength, 'largest', greaterThan(500)),
      ),
    );
  });

  test('the default budget holds ~200 unsigned records in one part', () {
    final plan = planLinkSnapshot(
      _bootstrap(expenses: 180, settlements: 20),
      me: 'p0',
      app: '1',
    );
    expect(plan.parts, hasLength(1));
  });

  test('shrinking: retired parts + header-only parts', () {
    expect(retiredLinkParts(8, 2), [2, 3, 4, 5, 6, 7]);
    expect(retiredLinkParts(4, 1), [1, 2, 3]);
    expect(retiredLinkParts(2, 4), isEmpty);
    expect(retiredLinkParts(2, 2), isEmpty);
    final b = _bootstrap();
    final r = buildRetiredLinkPart(b, me: 'p0', app: '1', index: 3, parts: 2);
    expect(r['part'], 3);
    expect(r['parts'], 2);
    expect(r['expenses'], isEmpty);
    expect(r['settlements'], isEmpty);
    expect(r['members'], b['members']);
    expect(r['meta'], b['meta']);
    expect(parseLinkSnapshotHeader(r).retired, isTrue);
    expect(
      () => buildRetiredLinkPart(b, me: 'p0', app: '1', index: 1, parts: 2),
      throwsRangeError,
    );
  });

  group('parseLinkSnapshotHeader', () {
    Map<String, dynamic> ok() => {
      'format': 'moneyledger-link',
      'v': 1,
      'group': 'g',
      'me': 'p0',
      'part': 1,
      'parts': 2,
      'app': '1.4.0',
    };

    Matcher fails(LinkSnapshotError kind) => throwsA(
      isA<LinkSnapshotException>().having((e) => e.kind, 'kind', kind),
    );

    test('valid; me / app optional', () {
      final h = parseLinkSnapshotHeader({...ok(), 'me': null, 'app': 3});
      expect((h.group, h.me, h.app, h.part, h.parts), ('g', null, null, 1, 2));
    });

    test('errors', () {
      expect(
        () =>
            parseLinkSnapshotHeader({...ok(), 'format': 'moneyledger-backup'}),
        fails(LinkSnapshotError.notASnapshot),
      );
      expect(
        () => parseLinkSnapshotHeader({...ok(), 'v': 2}),
        fails(LinkSnapshotError.unsupportedVersion),
      );
      for (final bad in <Map<String, dynamic>>[
        {'v': '1'},
        {'v': 0},
        {'group': null},
        {'group': ''},
        {'group': 5},
        {'part': '1'},
        {'part': -1},
        {'part': 8},
        {'parts': 3},
        {'parts': 16},
        {'parts': null},
      ]) {
        expect(
          () => parseLinkSnapshotHeader({...ok(), ...bad}),
          fails(LinkSnapshotError.malformed),
          reason: '$bad',
        );
      }
    });
  });
}
