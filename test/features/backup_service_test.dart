/// Full backup against a real (in-memory) Drift DB (G5): export → preview →
/// restore, idempotence, LWW in both directions, tombstones, left groups and
/// backups of another account.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/sync/left_groups.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_verifier.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/features/backup/backup_service.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const me = '@me:x';

BackupService serviceFor(AppDatabase db) => BackupService(
  db: db,
  groups: GroupsDao(db),
  members: MembersDao(db),
  expenses: ExpensesDao(db),
  settings: SettingsDao(db),
  signing: SigningDao(db),
  transport: Future.value(FakeMatrixNetwork().clientFor(me)),
);

Future<void> seed(AppDatabase db) async {
  final groups = GroupsDao(db);
  final members = MembersDao(db);
  final expenses = ExpensesDao(db);
  await groups.upsertGroupLww(
    const GroupsCompanion(
      roomId: Value('g1'),
      name: Value('Solo trip'),
      currency: Value('EUR'),
      updatedAt: Value(1000),
    ),
  );
  for (final (pid, name, mxid) in [(me, 'Me', me), ('kim', 'Kim', null)]) {
    await members.upsertMemberLww(
      MembersCompanion(
        groupId: const Value('g1'),
        userId: Value(pid),
        displayName: Value(name),
        matrixId: Value(mxid),
        status: const Value('active'),
        updatedAt: const Value(10),
      ),
    );
  }
  await expenses.upsertExpenseLww(
    ExpensesCompanion(
      id: const Value('e1'),
      roomId: const Value('g1'),
      description: const Value('Dinner'),
      amountCents: const Value(4200),
      currency: const Value('EUR'),
      paidBy: const Value(me),
      splitsJson: Value(jsonEncode({me: 2100, 'kim': 2100})),
      createdAt: const Value(100),
      updatedAt: const Value(150),
    ),
  );
  await expenses.upsertExpenseLww(
    const ExpensesCompanion(
      id: Value('e2'),
      roomId: Value('g1'),
      description: Value('Mistake'),
      amountCents: Value(999),
      currency: Value('EUR'),
      paidBy: Value(me),
      splitsJson: Value('{"@me:x":999}'),
      createdAt: Value(100),
      updatedAt: Value(300),
      deleted: Value(true),
    ),
  );
  await expenses.upsertSettlementLww(
    const SettlementsCompanion(
      id: Value('s1'),
      roomId: Value('g1'),
      amountCents: Value(2100),
      currency: Value('EUR'),
      fromUser: Value('kim'),
      toUser: Value(me),
      createdAt: Value(200),
      updatedAt: Value(200),
    ),
  );
}

void main() {
  late AppDatabase source;
  late AppDatabase target;
  late String json;

  setUp(() async {
    source = openTestDatabase();
    target = openTestDatabase();
    await seed(source);
    json = await serviceFor(source).exportJson(account: me, now: 5000);
  });
  tearDown(() async {
    await source.close();
    await target.close();
  });

  test(
    'restore into an empty DB recreates everything, incl. tombstones',
    () async {
      final svc = serviceFor(target);
      final backup = parseBackup(json);
      final preview = await svc.preview(backup, myMxid: me);
      expect(preview.newGroups, 1);
      expect(preview.otherAccount, isFalse);
      expect(preview.expenses, 1);
      expect(preview.settlements, 1);
      // meta + 2 members + 2 expenses + 1 settlement
      expect(preview.changes, 6);

      expect(await svc.restore(backup), ['g1']);

      final g = await GroupsDao(target).getGroup('g1');
      expect(g!.name, 'Solo trip');
      expect(g.updatedAt, 1000);
      final members = await MembersDao(target).getMembers('g1');
      expect(members.map((m) => m.userId), unorderedEquals([me, 'kim']));
      expect(members.firstWhere((m) => m.userId == 'kim').matrixId, isNull);
      final all = await ExpensesDao(target).getAllExpensesForGroup('g1');
      expect(all, hasLength(2));
      expect(all.firstWhere((e) => e.id == 'e2').deleted, isTrue);
      final live = await ExpensesDao(target).getExpensesForRoom('g1');
      expect(live.single.id, 'e1');
      final s = await ExpensesDao(target).getAllSettlementsForGroup('g1');
      expect(s.single.fromUser, 'kim');
    },
  );

  test(
    'restoring the same backup twice is a no-op (preview: 0 changes)',
    () async {
      final svc = serviceFor(target);
      await svc.restore(parseBackup(json));
      final again = await svc.preview(parseBackup(json), myMxid: me);
      expect(again.newGroups, 0);
      expect(again.changes, 0);
      expect(again.groups.single.isNew, isFalse);

      await svc.restore(parseBackup(json));
      expect(await GroupsDao(target).getAllGroups(), hasLength(1));
      expect(await MembersDao(target).getMembers('g1'), hasLength(2));
      expect(
        await ExpensesDao(target).getAllExpensesForGroup('g1'),
        hasLength(2),
      );
      expect(
        await ExpensesDao(target).getAllSettlementsForGroup('g1'),
        hasLength(1),
      );
    },
  );

  test('restoring onto the exporting device itself changes nothing', () async {
    final preview = await serviceFor(
      source,
    ).preview(parseBackup(json), myMxid: me);
    expect(preview.changes, 0);
    expect(preview.newGroups, 0);
  });

  test('LWW: a newer local edit survives, an older one is replaced', () async {
    final svc = serviceFor(target);
    await svc.restore(parseBackup(json));
    final dao = ExpensesDao(target);
    // e1 edited locally after the backup (newer) …
    await dao.upsertExpenseLww(
      ExpensesCompanion(
        id: const Value('e1'),
        roomId: const Value('g1'),
        description: const Value('Dinner (edited)'),
        amountCents: const Value(5000),
        currency: const Value('EUR'),
        paidBy: const Value(me),
        splitsJson: Value(jsonEncode({me: 5000})),
        createdAt: const Value(100),
        updatedAt: const Value(900),
      ),
    );
    // … and the settlement is older locally than in the backup.
    await target.customStatement(
      "UPDATE settlements SET amount_cents = 1, updated_at = 50 WHERE id = 's1'",
    );

    final preview = await svc.preview(parseBackup(json), myMxid: me);
    expect(preview.changes, 1); // only s1
    expect(preview.groups.single.changes, 1);
    await svc.restore(parseBackup(json));

    expect((await dao.getExpenseById('e1'))!.amountCents, 5000);
    expect((await dao.getSettlementById('s1'))!.amountCents, 2100);
  });

  test('a newer tombstone in the backup deletes the local record', () async {
    final svc = serviceFor(target);
    await svc.restore(parseBackup(json));
    // Delete e1 on the source after the first backup, back up again.
    final src = ExpensesDao(source);
    final e1 = (await src.getExpenseById('e1'))!;
    await src.upsertExpenseLww(
      ExpensesCompanion(
        id: Value(e1.id),
        roomId: Value(e1.roomId),
        description: Value(e1.description),
        amountCents: Value(e1.amountCents),
        currency: Value(e1.currency),
        paidBy: Value(e1.paidBy),
        splitsJson: Value(e1.splitsJson),
        createdAt: Value(e1.createdAt),
        updatedAt: const Value(2000),
        deleted: const Value(true),
      ),
    );
    final newer = await serviceFor(source).exportJson(account: me, now: 6000);
    await svc.restore(parseBackup(newer));
    expect(await ExpensesDao(target).getExpensesForRoom('g1'), isEmpty);

    // …and an older live copy can't resurrect it.
    await svc.restore(parseBackup(json));
    expect(await ExpensesDao(target).getExpensesForRoom('g1'), isEmpty);
  });

  test(
    'a group left on this device comes back and its tombstone is cleared',
    () async {
      final settings = SettingsDao(target);
      final svc = serviceFor(target);
      await svc.restore(parseBackup(json));
      await settings.purgeGroupAsLeft(
        'g1',
        const LeftGroupTombstone(leftAt: 7000),
      );
      expect(await GroupsDao(target).getGroup('g1'), isNull);

      final preview = await svc.preview(parseBackup(json), myMxid: me);
      expect(preview.groups.single.wasLeft, isTrue);
      expect(preview.groups.single.isNew, isTrue);

      await svc.restore(parseBackup(json));
      expect(await GroupsDao(target).getGroup('g1'), isNotNull);
      expect(await settings.leftGroup('g1'), isNull);
      expect(await ExpensesDao(target).getExpensesForRoom('g1'), hasLength(1));
    },
  );

  test('a backup of another account is flagged but restorable', () async {
    final svc = serviceFor(target);
    final preview = await svc.preview(parseBackup(json), myMxid: '@other:y');
    expect(preview.otherAccount, isTrue);
    await svc.restore(parseBackup(json));
    expect(await GroupsDao(target).getAllGroups(), hasLength(1));
    // Unknown own MXID (e.g. still loading) never flags.
    expect(
      (await svc.preview(parseBackup(json), myMxid: '')).otherAccount,
      isFalse,
    );
  });

  test('records the last backup time', () async {
    final settings = SettingsDao(target);
    expect(await settings.watchLastBackupAt().first, isNull);
    await serviceFor(target).markBackedUp(1234);
    expect(await settings.watchLastBackupAt().first, 1234);
  });

  test('a closed DB (account switched) stops the restore silently', () async {
    final svc = serviceFor(target);
    await target.close();
    expect(await svc.restore(parseBackup(json)), isEmpty);
    target = openTestDatabase(); // for tearDown
  });

  group('G6 signed backups', () {
    Future<(String, FakeMatrixNetwork)> signedExport(AppDatabase db) async {
      final net = FakeMatrixNetwork();
      final crypto = net.clientFor(me).crypto;
      await GroupsDao(db).upsertGroupLww(
        groupCompanion(
          await signGroupMeta(
            crypto,
            const GroupModel(
              roomId: 'g2',
              name: 'Signed',
              currency: 'EUR',
              updatedAt: 10,
            ),
          ),
        ),
      );
      for (final id in ['a', 'b']) {
        await ExpensesDao(db).upsertExpenseLww(
          expenseCompanion(
            await signExpense(
              crypto,
              ExpenseModel(
                id: id,
                roomId: 'g2',
                description: 'Expense $id',
                amountCents: 100,
                currency: 'EUR',
                paidBy: me,
                splitsJson: '{"$me":100}',
                createdAt: 20,
                updatedAt: 20,
              ),
              creating: true,
            ),
          ),
        );
      }
      await SigningDao(db).pinServerKeys({
        me: {'D1': crypto.identity!.key},
      });
      final svc = BackupService(
        db: db,
        groups: GroupsDao(db),
        members: MembersDao(db),
        expenses: ExpensesDao(db),
        settings: SettingsDao(db),
        signing: SigningDao(db),
        transport: Future.value(net.clientFor(me)),
      );
      return (await svc.exportJson(account: me, now: 1), net);
    }

    BackupService restorer(AppDatabase db, FakeMatrixNetwork net) =>
        BackupService(
          db: db,
          groups: GroupsDao(db),
          members: MembersDao(db),
          expenses: ExpensesDao(db),
          settings: SettingsDao(db),
          signing: SigningDao(db),
          transport: Future.value(net.clientFor(me, device: 'D2')),
        );

    test('the file carries signatures + key attestations; a restore on a '
        'new device (old one signed out) verifies them as vouched', () async {
      final fresh = openTestDatabase();
      addTearDown(fresh.close);
      final (json, net) = await signedExport(openTestDatabase());
      expect(json, contains('"device_keys"'));
      net.removeDevice(me); // the exporting device is gone

      expect(await restorer(fresh, net).restore(parseBackup(json)), ['g2']);
      final e = await ExpensesDao(fresh).getExpenseById('a');
      expect(e!.sig!.user, me);
      final keys = await SigningDao(fresh).allKeys();
      // Our own backup vouches for our own (signed-out) device — scoped to
      // the restored group (G18 review).
      expect(
        signatureStatus(e.sig, keys, group: 'g2').status,
        SigStatus.vouched,
      );
      expect(signatureStatus(e.sig, keys).status, SigStatus.unverified);
    });

    // G18 review (finding 9).
    test('a group whose meta is refused is not restored and keeps its '
        'left-group tombstone', () async {
      final fresh = openTestDatabase();
      addTearDown(fresh.close);
      final (json, net) = await signedExport(openTestDatabase());
      final tampered = jsonDecode(json) as Map<String, dynamic>;
      ((tampered['groups'] as List).single as Map)['meta']['name'] = 'Evil';
      await SettingsDao(
        fresh,
      ).purgeGroupAsLeft('g2', const LeftGroupTombstone(leftAt: 5));

      final restored = await restorer(
        fresh,
        net,
      ).restore(parseBackup(jsonEncode(tampered)));
      expect(restored, isEmpty);
      expect(await GroupsDao(fresh).getGroup('g2'), isNull);
      expect(await SettingsDao(fresh).leftGroup('g2'), isNotNull);
      expect(await ExpensesDao(fresh).getAllExpensesForGroup('g2'), isEmpty);
    });

    test(
      'a tampered record in the file is refused, the rest restores',
      () async {
        final fresh = openTestDatabase();
        addTearDown(fresh.close);
        final (json, net) = await signedExport(openTestDatabase());
        final tampered = json.replaceFirst('"Expense a"', '"Expense A!"');
        await restorer(fresh, net).restore(parseBackup(tampered));
        expect(await ExpensesDao(fresh).getExpenseById('a'), isNull);
        expect(await ExpensesDao(fresh).getExpenseById('b'), isNotNull);
      },
    );
  });

  group('G34 per-group backup', () {
    test('onlyGroup exports just that group, in the same format', () async {
      await GroupsDao(source).upsertGroupLww(
        const GroupsCompanion(
          roomId: Value('g9'),
          name: Value('Other'),
          currency: Value('EUR'),
          updatedAt: Value(1),
        ),
      );
      final full = parseBackup(
        await serviceFor(source).exportJson(account: me, now: 1),
      );
      expect(full.groups, hasLength(2));
      final one = parseBackup(
        await serviceFor(
          source,
        ).exportJson(account: me, now: 1, onlyGroup: 'g1'),
      );
      expect(one.groups.single['group'], 'g1');
      expect(one.groups.single['expenses'], hasLength(2));
      // …and restores like any backup.
      expect(await serviceFor(target).restore(one), ['g1']);
    });
  });

  group('G35 restore is all-or-nothing per group', () {
    BackupService failing(AppDatabase db) => BackupService(
      db: db,
      groups: GroupsDao(db),
      members: MembersDao(db),
      expenses: _FailingSettlementsDao(db),
      settings: SettingsDao(db),
      signing: SigningDao(db),
      transport: Future.value(FakeMatrixNetwork().clientFor(me)),
    );

    test('a failure mid-group rolls the whole group back (incl. the cleared '
        'left-group tombstone); other groups still restore', () async {
      // A second group without settlements — it restores fine.
      await GroupsDao(source).upsertGroupLww(
        const GroupsCompanion(
          roomId: Value('g9'),
          name: Value('Other'),
          currency: Value('EUR'),
          updatedAt: Value(1),
        ),
      );
      final backup = parseBackup(
        await serviceFor(source).exportJson(account: me, now: 1),
      );
      await SettingsDao(
        target,
      ).purgeGroupAsLeft('g1', const LeftGroupTombstone(leftAt: 5));

      await expectLater(
        failing(target).restore(backup),
        throwsA(
          isA<RestoreIncompleteException>()
              .having((e) => e.restored, 'restored', ['g9'])
              .having((e) => e.failed.keys, 'failed', ['g1']),
        ),
      );
      // g1: nothing at all — not the meta, members or expenses written
      // before the settlement failed.
      expect(await GroupsDao(target).getGroup('g1'), isNull);
      expect(await MembersDao(target).getMembers('g1'), isEmpty);
      expect(await ExpensesDao(target).getAllExpensesForGroup('g1'), isEmpty);
      expect(await SettingsDao(target).leftGroup('g1'), isNotNull);
      expect(await GroupsDao(target).getGroup('g9'), isNotNull);

      // A later good restore brings it back completely.
      expect(
        await serviceFor(target).restore(backup),
        unorderedEquals(['g1', 'g9']),
      );
      expect(
        await ExpensesDao(target).getAllSettlementsForGroup('g1'),
        hasLength(1),
      );
    });

    test('signer users of a payload (for the prefetch)', () {
      expect(
        payloadSignerUsers({
          'meta': {
            'sig': {'user': '@a:x'},
          },
          'members': [
            {
              'sig': {'user': '@b:x'},
            },
          ],
          'expenses': [
            {
              'sig': {'user': '@c:x'},
              'origin': {'user': '@d:x'},
            },
            {'no': 'sig'},
          ],
        }),
        {'@a:x', '@b:x', '@c:x', '@d:x'},
      );
    });
  });

  group('G34 preview: removed from the group', () {
    Map<String, dynamic> groupWith(String status, int at) => {
      'group': 'g1',
      'members': [
        {
          'group': 'g1',
          'participant_id': 'p-me',
          'name': 'Me',
          'matrix_id': me,
          'status': status,
          'updated_at': at,
        },
      ],
    };
    MemberModel local(String status, int at) => MemberModel(
      groupId: 'g1',
      userId: 'p-me',
      displayName: 'Me',
      matrixId: me,
      status: status,
      updatedAt: at,
    );

    test('removed in the backup', () {
      expect(
        backupShowsMeRemoved(
          groupWith('removed', 10),
          myMxid: me,
          local: const [],
        ),
        isTrue,
      );
      expect(
        backupShowsMeRemoved(groupWith('active', 10), myMxid: me, local: []),
        isFalse,
      );
    });

    test('the newer of backup and local copy decides', () {
      expect(
        backupShowsMeRemoved(
          groupWith('active', 10),
          myMxid: me,
          local: [local('removed', 20)],
        ),
        isTrue,
      );
      expect(
        backupShowsMeRemoved(
          groupWith('removed', 10),
          myMxid: me,
          local: [local('active', 20)],
        ),
        isFalse,
      );
    });

    test('not a participant at all → not "removed"', () {
      expect(
        backupShowsMeRemoved(
          groupWith('removed', 10),
          myMxid: '@other:y',
          local: const [],
        ),
        isFalse,
      );
    });

    test('preview flags it', () async {
      await MembersDao(source).upsertMemberLww(
        const MembersCompanion(
          groupId: Value('g1'),
          userId: Value(me),
          displayName: Value('Me'),
          matrixId: Value(me),
          status: Value('removed'),
          updatedAt: Value(99),
        ),
      );
      final backup = parseBackup(
        await serviceFor(source).exportJson(account: me, now: 1),
      );
      final preview = await serviceFor(target).preview(backup, myMxid: me);
      expect(preview.groups.single.removed, isTrue);
    });
  });
}

class _FailingSettlementsDao extends ExpensesDao {
  _FailingSettlementsDao(super.db);

  @override
  Future<void> upsertSettlementLww(SettlementsCompanion settlement) =>
      Future.error(StateError('disk full'));
}
