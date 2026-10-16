/// G14: how big digests and bootstraps get for realistic groups, measured
/// against the real to-device limit (`payload_budget.dart`). Pure and fast —
/// no DB, no network: builds signed-looking v2 records (4 claimed members,
/// typical descriptions, Ed25519-sized keys / signatures) and encodes them.
///
/// Prints a size table; the assertions pin the documented ceilings so a
/// payload-size regression (e.g. a new per-record field) is caught.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/payload_budget.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

const _members = [
  ('@moneyledger-test-a-c725:matrix.org', 'Alexandra'),
  ('@moneyledger-test-b-c725:matrix.org', 'Benjamin'),
  ('@carla.mustermann:example.org', 'Carla'),
  ('@dominik:fosdem.org', 'Dominik'),
];

const _descriptions = [
  'Dinner',
  'Groceries Lidl',
  'Train tickets Munich - Berlin',
  'Airbnb (3 nights)',
  'Coffee & croissants',
  'Museum entry',
  'Taxi to the airport',
  'Fuel',
  'Supermarket: drinks, snacks and breakfast for the weekend',
  'Pizza',
];

String _b64(Random r, int len) {
  const abc =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  return String.fromCharCodes(
    List.generate(len, (_) => abc.codeUnitAt(r.nextInt(abc.length))),
  );
}

/// An Ed25519-sized signature (43-char key, 86-char signature, 10-char
/// device id) by [user].
RecordSignature _sig(Random r, String user) => RecordSignature(
  user: user,
  device: _b64(r, 10).toUpperCase(),
  key: _b64(r, 43),
  sig: _b64(r, 86),
);

String _uuid(Random r) {
  String hex(int n) =>
      List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${hex(8)}-${hex(4)}-7${hex(3)}-a${hex(3)}-${hex(12)}';
}

class _Group {
  final GroupModel group;
  final List<MemberModel> members;
  final List<ExpenseModel> expenses;
  final List<SettlementModel> settlements;
  final Map<String, Map<String, String>> deviceKeys;
  _Group(
    this.group,
    this.members,
    this.expenses,
    this.settlements,
    this.deviceKeys,
  );
  int get records => expenses.length + settlements.length;
}

/// [n] records: 90 % expenses split between all four, 10 % payments, 5 %
/// tombstones; every version signed (+ origin).
_Group _realisticGroup(int n, {int seed = 1}) {
  final r = Random(seed);
  const gid = '0199e3a0-5a1b-7c2d-8e3f-4a5b6c7d8e9f';
  const t0 = 1760000000000;
  final group = GroupModel(
    roomId: gid,
    name: 'Summer trip 2026',
    currency: 'EUR',
    updatedAt: t0,
    sig: _sig(r, _members.first.$1),
  );
  final members = [
    for (final (mxid, name) in _members)
      MemberModel(
        groupId: gid,
        userId: mxid,
        displayName: name,
        matrixId: mxid,
        status: 'active',
        updatedAt: t0 + r.nextInt(100000),
        sig: _sig(r, _members.first.$1),
      ),
  ];
  final expenses = <ExpenseModel>[];
  final settlements = <SettlementModel>[];
  for (var i = 0; i < n; i++) {
    final created = t0 + i * 60000 + r.nextInt(60000);
    final updated = created + (r.nextBool() ? 0 : r.nextInt(86400000));
    final payer = _members[r.nextInt(4)].$1;
    final editor = _members[r.nextInt(4)].$1;
    if (i % 10 == 9) {
      final to = _members[(r.nextInt(3) + 1) % 4].$1;
      settlements.add(
        SettlementModel(
          id: _uuid(r),
          roomId: gid,
          amountCents: 100 + r.nextInt(50000),
          currency: 'EUR',
          fromUser: payer,
          toUser: to,
          createdAt: created,
          updatedAt: updated,
          deleted: i % 20 == 19,
          origin: _sig(r, payer),
          sig: _sig(r, editor),
        ),
      );
      continue;
    }
    final amount = 100 + r.nextInt(30000);
    final share = amount ~/ 4;
    expenses.add(
      ExpenseModel(
        id: _uuid(r),
        roomId: gid,
        description: _descriptions[r.nextInt(_descriptions.length)],
        amountCents: amount,
        currency: 'EUR',
        paidBy: payer,
        splitsJson:
            '{"${_members[0].$1}":${amount - 3 * share},'
            '"${_members[1].$1}":$share,'
            '"${_members[2].$1}":$share,'
            '"${_members[3].$1}":$share}',
        createdAt: created,
        updatedAt: updated,
        deleted: i % 20 == 18,
        origin: _sig(r, payer),
        sig: _sig(r, editor),
      ),
    );
  }
  // Two devices per member signed something.
  final deviceKeys = {
    for (final (mxid, _) in _members)
      mxid: {_b64(r, 10).toUpperCase(): _b64(r, 43), 'PHONE01': _b64(r, 43)},
  };
  return _Group(group, members, expenses, settlements, deviceKeys);
}

int _enc(Map<String, dynamic> m) => encodedPayloadBytes(m);

void main() {
  test('size table: digest / bootstrap for 100 / 1k / 5k records', () {
    final rows = <String>[];
    rows.add(
      '| records | flat digest | 1-msg bootstrap | bootstrap parts '
      '(max part) | bucketed digest summary (bits) | full-detail digest '
      'msgs (max) | max est. encrypted |',
    );
    rows.add('|---|---|---|---|---|---|---|');
    final perRecordBootstrap = <double>[];
    final perRecordDigest = <double>[];
    for (final n in [100, 1000, 5000]) {
      final g = _realisticGroup(n);
      final sw = Stopwatch()..start();
      final flat = buildDigestContent(
        g.group,
        g.members,
        g.expenses,
        g.settlements,
        reply: false,
      );
      final flatBytes = _enc(flat);
      final whole = buildBootstrapContent(
        g.group.roomId,
        g.group,
        g.members,
        g.expenses,
        g.settlements,
        deviceKeys: g.deviceKeys,
      );
      final wholeBytes = _enc(whole);
      final parts = buildBootstrapParts(
        g.group.roomId,
        g.group,
        g.members,
        g.expenses,
        g.settlements,
        deviceKeys: g.deviceKeys,
        budget: kMaxPayloadBytes,
      );
      final partSizes = parts.map(_enc).toList();
      final summary = buildDigestMessages(
        g.group,
        g.members,
        g.expenses,
        g.settlements,
        reply: false,
        budget: kMaxPayloadBytes,
        bits: null,
      );
      final summaryBucketed = summary.first.containsKey('bucket_bits');
      // Worst case: every bucket differs (a peer that holds nothing).
      final bits = summaryBucketed ? summary.first['bucket_bits'] as int : null;
      final full = bits == null
          ? summary
          : buildDigestMessages(
              g.group,
              g.members,
              g.expenses,
              g.settlements,
              reply: true,
              budget: kMaxPayloadBytes,
              bits: bits,
              detail: {for (var b = 0; b < 1 << bits; b++) b},
            );
      final fullSizes = full.map(_enc).toList();
      final elapsed = sw.elapsedMilliseconds;

      final maxMsg = [
        ...partSizes,
        ...fullSizes,
        ...summary.map(_enc),
      ].reduce(max);
      rows.add(
        '| $n | $flatBytes | $wholeBytes | ${parts.length} '
        '(${partSizes.reduce(max)}) | '
        '${summaryBucketed ? '${_enc(summary.first)} ($bits)' : 'flat'} | '
        '${full.length} (${fullSizes.reduce(max)}) | '
        '${estimateEncryptedEventBytes(maxMsg)} | (${elapsed}ms)',
      );

      // Every message fits one to-device event with headroom.
      for (final s in [...partSizes, ...fullSizes, ...summary.map(_enc)]) {
        expect(s, lessThanOrEqualTo(kMaxPayloadBytes));
        expect(estimateEncryptedEventBytes(s), lessThan(kToDeviceContentLimit));
      }
      // Parts carry every record exactly once.
      expect(
        parts.fold<int>(
          0,
          (a, p) =>
              a +
              (p['expenses'] as List).length +
              (p['settlements'] as List).length,
        ),
        g.records,
      );
      if (bits != null) {
        // The full detail lists every record exactly once.
        expect(
          full.fold<int>(
            0,
            (a, m) =>
                a +
                (m['expenses'] as Map).length +
                (m['settlements'] as Map).length,
          ),
          g.records,
        );
      }

      final header = buildBootstrapContent(
        g.group.roomId,
        g.group,
        g.members,
        const [],
        const [],
        deviceKeys: g.deviceKeys,
      );
      perRecordBootstrap.add((wholeBytes - _enc(header)) / n);
      final emptyDigest = buildDigestContent(
        g.group,
        g.members,
        const [],
        const [],
        reply: false,
      );
      perRecordDigest.add((flatBytes - _enc(emptyDigest)) / n);
    }

    final bPer = perRecordBootstrap.reduce(max);
    final dPer = perRecordDigest.reduce(max);
    // Ceilings of the *unchunked* formats (hard limit, 4 members).
    final bootstrapCeiling = (kHardMaxPayloadBytes - 3000) ~/ bPer;
    final digestCeiling = (kHardMaxPayloadBytes - 2500) ~/ dPer;
    // ignore: avoid_print
    print(
      [
        ...rows,
        '',
        'per record: bootstrap ${bPer.toStringAsFixed(0)} B, '
            'flat digest entry ${dPer.toStringAsFixed(1)} B',
        'hard payload max ≈ $kHardMaxPayloadBytes B '
            '(encrypted event ≤ $kToDeviceContentLimit B); budget '
            '$kMaxPayloadBytes B',
        'unchunked ceilings: single bootstrap ≈ $bootstrapCeiling records, '
            'flat digest ≈ $digestCeiling records',
      ].join('\n'),
    );

    // Pinned ceilings (documented in CLAUDE.md / docs/open-points.md): a
    // signed record costs ~0.75 KB in a bootstrap, a digest entry ~63 B.
    expect(bPer, inInclusiveRange(600, 900));
    expect(dPer, inInclusiveRange(55, 70));
    expect(bootstrapCeiling, lessThan(100), reason: 'why bootstraps chunk');
    expect(digestCeiling, inInclusiveRange(600, 900));
  });

  test('the encrypted-size estimate matches the hard ceiling', () {
    expect(
      estimateEncryptedEventBytes(kHardMaxPayloadBytes),
      lessThanOrEqualTo(kToDeviceContentLimit),
    );
    expect(
      estimateEncryptedEventBytes(kHardMaxPayloadBytes + 10),
      greaterThan(kToDeviceContentLimit),
    );
    expect(kMaxPayloadBytes, lessThan(kHardMaxPayloadBytes));
    expect(
      () => checkPayloadSize('t', {'x': 'y' * kHardMaxPayloadBytes}),
      throwsA(isA<PayloadTooLargeException>()),
    );
    checkPayloadSize('t', {'x': 'y' * 1000});
  });
}
