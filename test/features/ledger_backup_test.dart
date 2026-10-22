/// Full backup codec (G5): build / parse / validate, file name, and the pure
/// nudge logic. No DB.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

void main() {
  const g1 = GroupModel(
    roomId: 'g1',
    name: 'Trip',
    currency: 'EUR',
    updatedAt: 1000,
  );
  const g2 = GroupModel(
    roomId: 'g2',
    name: 'Flat',
    currency: 'CHF',
    updatedAt: 2000,
  );
  MemberModel member(
    String gid,
    String pid,
    String name, {
    String? mxid,
    String status = 'active',
  }) => MemberModel(
    groupId: gid,
    userId: pid,
    displayName: name,
    matrixId: mxid,
    status: status,
    updatedAt: 10,
  );
  final snapshot = GroupSnapshot(
    group: g1,
    members: [
      member('g1', '@me:x', 'Me', mxid: '@me:x'),
      member('g1', 'local-1', 'Kim'),
      member('g1', 'gone', 'Old', status: 'removed'),
    ],
    expenses: const [
      ExpenseModel(
        id: 'e1',
        roomId: 'g1',
        description: 'Dinner',
        amountCents: 4200,
        currency: 'EUR',
        paidBy: '@me:x',
        splitsJson: '{"@me:x":2100,"local-1":2100}',
        createdAt: 100,
        updatedAt: 150,
      ),
      ExpenseModel(
        id: 'e2',
        roomId: 'g1',
        description: 'Deleted',
        amountCents: 100,
        currency: 'EUR',
        paidBy: '@me:x',
        splitsJson: '{"@me:x":100}',
        createdAt: 100,
        updatedAt: 300,
        deleted: true,
      ),
    ],
    settlements: const [
      SettlementModel(
        id: 's1',
        roomId: 'g1',
        amountCents: 2100,
        currency: 'EUR',
        fromUser: 'local-1',
        toUser: '@me:x',
        createdAt: 200,
        updatedAt: 200,
      ),
    ],
  );
  final empty = GroupSnapshot(
    group: g2,
    members: [member('g2', '@me:x', 'Me', mxid: '@me:x')],
    expenses: const [],
    settlements: const [],
  );

  String build() => buildBackupJson(
    account: '@me:x',
    exportedAt: 1760000000000,
    groups: [snapshot, empty],
  );

  group('buildBackupJson / parseBackup', () {
    test('round-trips header, groups, members, records and tombstones', () {
      final b = parseBackup(build());
      expect(b.version, backupVersion);
      expect(b.account, '@me:x');
      expect(b.exportedAt, 1760000000000);
      // Sorted by name: Flat, Trip.
      expect(b.groups.map((g) => g['group']), ['g2', 'g1']);

      final trip = b.groups[1];
      expect(trip['name'], 'Trip');
      expect(trip['currency'], 'EUR');
      expect(trip['updated_at'], 1000);
      final members = trip['members'] as List;
      expect(members, hasLength(3));
      final kim = members.firstWhere((m) => m['participant_id'] == 'local-1');
      expect(kim['matrix_id'], isNull);
      expect(kim['name'], 'Kim');
      expect(
        members.firstWhere((m) => m['participant_id'] == 'gone')['status'],
        'removed',
      );
      final expenses = trip['expenses'] as List;
      expect(expenses.map((e) => e['id']), ['e1', 'e2']);
      expect(expenses[1]['deleted'], isTrue);
      expect(expenses[0]['split'], {'@me:x': 2100, 'local-1': 2100});
      final s = (trip['settlements'] as List).single;
      expect(s['from'], 'local-1');
      expect(s['to'], '@me:x');
      expect(s['updated_at'], 200);
    });

    test('the file is self-describing JSON', () {
      final raw = jsonDecode(build()) as Map;
      expect(raw['format'], 'moneyledger-backup');
      expect(raw['version'], 1);
    });

    test('summary counts live records and active members only', () {
      final trip = parseBackup(build()).groups[1];
      final s = summarizeBackupGroup(trip);
      expect(s.groupId, 'g1');
      expect(s.name, 'Trip');
      expect(s.expenseCount, 1); // e2 is a tombstone
      expect(s.settlementCount, 1);
      expect(s.memberCount, 2); // "Old" was removed
    });

    test('an account-less backup parses with a null account', () {
      final b = parseBackup(
        buildBackupJson(account: null, exportedAt: 1, groups: const []),
      );
      expect(b.account, isNull);
      expect(b.groups, isEmpty);
    });
  });

  group('G52 step 10: link groups carry their invite key', () {
    test('only a link group gets "link"; parsed back; never in toString', () {
      final json = buildBackupJson(
        account: 'local:self',
        exportedAt: 1,
        groups: [
          GroupSnapshot(
            group: snapshot.group,
            members: snapshot.members,
            expenses: snapshot.expenses,
            settlements: snapshot.settlements,
            link: const BackupLink(epoch: 2, secret: 'c2VjcmV0'),
          ),
          empty,
        ],
      );
      final b = parseBackup(json);
      final flat = b.groups[0];
      final trip = b.groups[1];
      expect(flat.containsKey('link'), isFalse);
      expect(backupGroupLink(flat), isNull);
      final link = backupGroupLink(trip)!;
      expect(link.epoch, 2);
      expect(link.secret, 'c2VjcmV0');
      expect(link.toString(), isNot(contains('c2VjcmV0')));
      // The bootstrap content itself (meta, records) is unchanged.
      expect(trip['name'], 'Trip');
      expect((trip['expenses'] as List).map((e) => e['id']), ['e1', 'e2']);
    });

    test('a malformed "link" is ignored (the group restores without one)', () {
      for (final bad in <Object?>[
        'x',
        {'epoch': 0, 'secret': 'abc'},
        {'epoch': 1, 'secret': ''},
        {'epoch': '1', 'secret': 'abc'},
        {'secret': 'abc'},
      ]) {
        expect(
          backupGroupLink({'group': 'g', 'link': bad}),
          isNull,
          reason: '$bad',
        );
      }
    });
  });

  group('parseBackup rejects', () {
    void expectKind(String text, BackupErrorKind kind) => expect(
      () => parseBackup(text),
      throwsA(isA<BackupFormatException>().having((e) => e.kind, 'kind', kind)),
    );

    test('garbage and non-JSON (e.g. a CSV) as not a backup', () {
      expectKind('', BackupErrorKind.notABackup);
      expectKind('Date,Description\n2026,x', BackupErrorKind.notABackup);
      expectKind('\u0000ÿ binary', BackupErrorKind.notABackup);
    });

    test('JSON without the format marker as not a backup', () {
      expectKind('[1,2,3]', BackupErrorKind.notABackup);
      expectKind('{"version":1,"groups":[]}', BackupErrorKind.notABackup);
      expectKind(
        '{"format":"other-app","version":1}',
        BackupErrorKind.notABackup,
      );
    });

    test('a newer version, reporting that version', () {
      final text = jsonEncode({
        'format': backupFormat,
        'version': backupVersion + 1,
        'groups': [],
      });
      expect(
        () => parseBackup(text),
        throwsA(
          isA<BackupFormatException>()
              .having((e) => e.kind, 'kind', BackupErrorKind.newerVersion)
              .having((e) => e.version, 'version', backupVersion + 1),
        ),
      );
    });

    test('broken content as malformed', () {
      String doc(Object? groups, {Object? version = 1}) => jsonEncode({
        'format': backupFormat,
        'version': version,
        'groups': groups,
      });
      expectKind(doc([], version: 'one'), BackupErrorKind.malformed);
      expectKind(doc([], version: 0), BackupErrorKind.malformed);
      expectKind(doc('nope'), BackupErrorKind.malformed);
      expectKind(doc([42]), BackupErrorKind.malformed);
      expectKind(
        doc([
          {'name': 'no id'},
        ]),
        BackupErrorKind.malformed,
      );
      expectKind(
        doc([
          {'group': 'g1', 'expenses': 'x'},
        ]),
        BackupErrorKind.malformed,
      );
      // A record routed to another group would land in the wrong ledger.
      expectKind(
        doc([
          {
            'group': 'g1',
            'expenses': [
              {'id': 'e1', 'group': 'g2', 'updated_at': 1},
            ],
          },
        ]),
        BackupErrorKind.malformed,
      );
      expectKind(
        doc([
          {
            'group': 'g1',
            'members': [
              {'group': 'g1', 'updated_at': 1},
            ],
          },
        ]),
        BackupErrorKind.malformed,
      );
      expectKind(
        doc([
          {
            'group': 'g1',
            'settlements': [
              {'id': 's1', 'group': 'g1'},
            ],
          },
        ]),
        BackupErrorKind.malformed,
      );
    });
  });

  test('backupFileName uses the local date', () {
    expect(
      backupFileName(DateTime(2026, 3, 7, 23, 59)),
      'moneyledger-backup-2026-03-07.json',
    );
  });

  group('nudge (G5)', () {
    const solo = GroupModel(roomId: 's', name: 'Solo', currency: 'EUR');
    const shared = GroupModel(roomId: 'p', name: 'Shared', currency: 'EUR');
    const locals = GroupModel(roomId: 'l', name: 'Locals', currency: 'EUR');
    const left = GroupModel(roomId: 'r', name: 'Peer left', currency: 'EUR');
    final members = [
      member('s', '@me:x', 'Me', mxid: '@me:x'),
      member('p', '@me:x', 'Me', mxid: '@me:x'),
      member('p', '@bo:x', 'Bo', mxid: '@bo:x'),
      member('l', '@me:x', 'Me', mxid: '@me:x'),
      member('l', 'kim', 'Kim'),
      member('r', '@me:x', 'Me', mxid: '@me:x'),
      member('r', '@al:x', 'Al', mxid: '@al:x', status: 'removed'),
    ];

    test('unprotected = no other active claimed member', () {
      final u = unprotectedGroups(
        groups: [solo, shared, locals, left],
        members: members,
        myMxid: '@me:x',
      );
      expect(u.map((g) => g.roomId), ['s', 'l', 'r']);
    });

    test('link-shared = a channel and an unsigned meta, or a signed meta '
        'with an open link (Leo 2026-10-22)', () {
      const sig = RecordSignature(
        user: '@me:x',
        device: 'D',
        key: 'k',
        sig: 's',
      );
      const linkOnly = GroupModel(roomId: 'a', name: 'A', currency: 'EUR');
      const mixed = GroupModel(
        roomId: 'b',
        name: 'B',
        currency: 'EUR',
        link: GroupLink(epoch: 1, secret: 'x'),
        sig: sig,
      );
      const locked = GroupModel(
        roomId: 'c',
        name: 'C',
        currency: 'EUR',
        lockedAt: 1,
        sig: sig,
      );
      const local = GroupModel(roomId: 'd', name: 'D', currency: 'EUR');
      final l = linkSharedGroups(
        groups: [linkOnly, mixed, locked, local],
        channelGroupIds: {'a', 'b', 'c'},
      );
      expect(l.map((g) => g.roomId), ['a', 'b']);
      expect(const BackupNudgeCounts().show, isFalse);
      expect(const BackupNudgeCounts(link: 1).show, isTrue);
      expect(const BackupNudgeCounts(onlyHere: 2).show, isTrue);
    });

    const day = 24 * 60 * 60 * 1000;
    const now = 100 * day;
    test('shows without any backup, hides with no unprotected group', () {
      expect(
        shouldShowBackupNudge(
          unprotectedCount: 1,
          lastBackupAt: null,
          snoozedUntil: null,
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldShowBackupNudge(
          unprotectedCount: 0,
          lastBackupAt: null,
          snoozedUntil: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('a backup within 30 days hides it; an older one does not', () {
      bool show(int last) => shouldShowBackupNudge(
        unprotectedCount: 2,
        lastBackupAt: last,
        snoozedUntil: null,
        now: now,
      );
      expect(show(now - 29 * day), isFalse);
      expect(show(now - 30 * day), isTrue);
    });

    test('a snooze hides it until it expires', () {
      bool show(int until) => shouldShowBackupNudge(
        unprotectedCount: 1,
        lastBackupAt: null,
        snoozedUntil: until,
        now: now,
      );
      expect(show(now + 1), isFalse);
      expect(show(now), isTrue);
    });
  });

  group('G34 file names', () {
    test('a per-group backup carries the group name slug', () {
      final at = DateTime(2026, 3, 7);
      expect(
        backupFileName(at, groupName: 'Ski Trip 2026!'),
        'moneyledger-backup-ski-trip-2026-2026-03-07.json',
      );
      expect(
        backupFileName(at, groupName: 'WG Küche & Bad'),
        'moneyledger-backup-wg-küche-bad-2026-03-07.json',
      );
      expect(
        backupFileName(at, groupName: '???'),
        'moneyledger-backup-group-2026-03-07.json',
      );
      expect(fileNameSlug('a' * 60), hasLength(40));
      expect(fileNameSlug('${'a' * 39} b'), 'a' * 39);
    });

    test('the saved name is shown only when the platform reports it', () {
      const ext = 'json';
      expect(
        savedFileDisplayName(
          '/document/primary:Download/moneyledger-backup-2026-03-07 (1).json',
          ext,
        ),
        'moneyledger-backup-2026-03-07 (1).json',
      );
      expect(
        savedFileDisplayName(
          '/document/raw:/storage/emulated/0/Download/my%20backup.json',
          ext,
        ),
        'my backup.json',
      );
      // Downloads provider ids carry no name.
      expect(savedFileDisplayName('/document/msf:1000000033', ext), isNull);
      expect(savedFileDisplayName('/document/1234', ext), isNull);
      expect(savedFileDisplayName(null, ext), isNull);
      expect(savedFileDisplayName('', ext), isNull);
      expect(savedFileDisplayName('/x/.json', ext), isNull);
      expect(savedFileDisplayName('/a/Trip.csv', 'csv'), 'Trip.csv');
    });
  });

  group('G34 second own device', () {
    const day = 24 * 60 * 60 * 1000;
    const now = 100 * day;
    test('a verified other device of ours protects the solo groups', () {
      expect(
        secondOwnDeviceProtects(
          otherVerifiedOwnDevice: true,
          lastOwnDeviceInSyncAt: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('so does one recently in sync with us', () {
      expect(
        secondOwnDeviceProtects(
          otherVerifiedOwnDevice: false,
          lastOwnDeviceInSyncAt: now - 3 * day,
          now: now,
        ),
        isTrue,
      );
    });

    test('an own device last seen long ago (or never) does not', () {
      expect(
        secondOwnDeviceProtects(
          otherVerifiedOwnDevice: false,
          lastOwnDeviceInSyncAt: now - 31 * day,
          now: now,
        ),
        isFalse,
      );
      expect(
        secondOwnDeviceProtects(
          otherVerifiedOwnDevice: false,
          lastOwnDeviceInSyncAt: 0,
          now: now,
        ),
        isFalse,
      );
      expect(
        secondOwnDeviceProtects(
          otherVerifiedOwnDevice: false,
          lastOwnDeviceInSyncAt: null,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
