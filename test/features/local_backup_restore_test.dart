/// G41: backups across the local-mode / Matrix-account boundary.
///
/// * A backup made in **local mode** (account `local:self`, every row
///   unsigned, "me" claimed by the local pseudo account) restored into a
///   Matrix account is adopted exactly like "Connect a Matrix account": "me"
///   is re-claimed by the MXID, every row is signed by this device (incl.
///   "added by"), and the account's other device receives and verifies it.
/// * A Matrix account's backup restored **in local mode** verifies (local
///   mode can check Ed25519 signatures without a Matrix client), and the user
///   takes the backup account's place; connecting that account later adopts
///   it back.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/local_adoption.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/backup/backup_service.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const _mxid = '@lea:x.test';
const _peer = '@max:x.test';

void main() {
  late FakeMatrixNetwork net;
  late List<String> logs;
  final dbs = <AppDatabase>[];
  final original = debugPrint;

  AppDatabase newDb() {
    final db = openTestDatabase();
    dbs.add(db);
    return db;
  }

  setUp(() {
    net = FakeMatrixNetwork();
    logs = [];
    dbs.clear();
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  });

  tearDown(() async {
    debugPrint = original;
    for (final db in dbs) {
      await db.close();
    }
  });

  /// A ledger container: [db] with the given relay identity.
  ProviderContainer ledger(AppDatabase db, Object transport) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith(
          (ref) async => transport as dynamic,
        ),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// A group with "me", a local person and one expense + payment, written by
  /// [c]'s identity; returns its id.
  Future<String> seedGroup(ProviderContainer c, String me) async {
    await c.read(ledgerTransportProvider.future);
    await c.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await c.read(groupsDaoProvider).getAllGroups()).single.roomId;
    await c.read(memberAdderProvider.notifier).addLocal(groupId, 'Kim');
    final members = await c.read(membersDaoProvider).getMembers(groupId);
    final mine = claimedBy(members, me)!;
    final kim = members.firstWhere((m) => m.displayName == 'Kim');
    await c
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: groupId,
          description: 'Dinner',
          amountCents: 4000,
          currency: 'EUR',
          paidBy: mine.userId,
          splits: {mine.userId: 2000, kim.userId: 2000},
        );
    await c
        .read(expenseAdderProvider.notifier)
        .addSettlement(
          roomId: groupId,
          amountCents: 1000,
          currency: 'EUR',
          fromUser: kim.userId,
          toUser: mine.userId,
        );
    return groupId;
  }

  /// A backup JSON made in local mode (account `local:self`).
  Future<(String, String)> localBackup() async {
    final c = ledger(newDb(), LocalOnlyTransport('Lea'));
    final groupId = await seedGroup(c, kLocalAccountId);
    final json = await c
        .read(backupServiceProvider)
        .exportJson(account: kLocalAccountId, now: 5000);
    return (json, groupId);
  }

  group('restoreTakeover (pure)', () {
    test('which direction a restore takes over', () {
      expect(
        restoreTakeover(kLocalAccountId, _mxid),
        RestoreTakeover.localIntoAccount,
      );
      expect(
        restoreTakeover(_mxid, kLocalAccountId),
        RestoreTakeover.accountIntoLocal,
      );
      expect(
        restoreTakeover(kLocalAccountId, kLocalAccountId),
        RestoreTakeover.none,
        reason: 'a local backup in local mode stays as is',
      );
      expect(restoreTakeover(_mxid, _mxid), RestoreTakeover.none);
      expect(restoreTakeover(_peer, _mxid), RestoreTakeover.none);
      expect(restoreTakeover(null, _mxid), RestoreTakeover.none);
      expect(restoreTakeover(null, kLocalAccountId), RestoreTakeover.none);
      expect(restoreTakeover(kLocalAccountId, ''), RestoreTakeover.none);
    });
  });

  group('local backup → Matrix account', () {
    test(
      'preview says the groups are taken over (no "other account")',
      () async {
        final (json, _) = await localBackup();
        final c = ledger(newDb(), net.clientFor(_mxid));
        final preview = await c
            .read(backupServiceProvider)
            .preview(parseBackup(json), myMxid: _mxid);
        expect(preview.takeover, RestoreTakeover.localIntoAccount);
        expect(preview.myAccount, _mxid);
        expect(preview.otherAccount, isFalse);
        expect(preview.newGroups, 1);
        expect(preview.groups.single.removed, isFalse);
      },
    );

    test(
      're-claims "me" for the MXID and signs every row (incl. added by)',
      () async {
        final (json, groupId) = await localBackup();
        final db = newDb();
        final c = ledger(db, net.clientFor(_mxid));
        final restored = await c
            .read(backupServiceProvider)
            .restore(parseBackup(json));
        expect(restored, [groupId]);

        final members = await MembersDao(db).getMembers(groupId);
        final me = claimedBy(members, _mxid)!;
        expect(me.displayName, 'Lea');
        expect(me.isActive, isTrue);
        expect(members.where((m) => isLocalAccountId(m.matrixId)), isEmpty);
        for (final m in members) {
          expect(m.sig?.user, _mxid, reason: m.displayName);
          expect(m.pendingSign, isFalse);
        }
        final group = await GroupsDao(db).getGroup(groupId);
        expect(group!.sig?.user, _mxid);
        expect(group.pendingSign, isFalse);
        final expense = (await ExpensesDao(
          db,
        ).getAllExpensesForGroup(groupId)).single;
        expect(expense.sig?.user, _mxid);
        expect(expense.origin?.user, _mxid, reason: '"added by" you');
        expect(expense.pendingSign, isFalse);
        expect(expense.paidBy, me.userId, reason: 'history unchanged');
        final payment = (await ExpensesDao(
          db,
        ).getAllSettlementsForGroup(groupId)).single;
        expect(payment.sig?.user, _mxid);
        expect(payment.origin?.user, _mxid);
        expect(payment.toUser, me.userId);

        // Restoring the same file again changes nothing (the old local
        // claim loses LWW against the adopted one), no duplicates.
        final clock = me.updatedAt;
        await c.read(backupServiceProvider).restore(parseBackup(json));
        final again = await MembersDao(db).getMembers(groupId);
        expect(again, hasLength(2));
        expect(claimedBy(again, _mxid)!.updatedAt, clock);
        expect(again.where((m) => isLocalAccountId(m.matrixId)), isEmpty);
      },
    );

    test(
      "the account's other device receives it and refuses nothing",
      () async {
        final (json, groupId) = await localBackup();
        final db = newDb();
        final c = ledger(db, net.clientFor(_mxid));
        c.listen(ledgerSyncerProvider, (_, _) {});
        c.listen(syncEngineProvider, (_, _) {});
        final otherDb = newDb();
        final other = ledger(otherDb, net.clientFor(_mxid, device: 'D2'));
        other.listen(ledgerSyncerProvider, (_, _) {});
        other.listen(syncEngineProvider, (_, _) {});
        await net.settle();

        await c.read(backupServiceProvider).restore(parseBackup(json));
        await c.read(syncEngineProvider).broadcastDigests();
        await net.settle();

        final expense = (await ExpensesDao(
          otherDb,
        ).getAllExpensesForGroup(groupId)).single;
        expect(expense.description, 'Dinner');
        expect(expense.origin?.user, _mxid);
        expect(
          await ExpensesDao(otherDb).getAllSettlementsForGroup(groupId),
          hasLength(1),
        );
        final members = await MembersDao(otherDb).getMembers(groupId);
        expect(claimedBy(members, _mxid)?.displayName, 'Lea');
        expect(logs.where((l) => l.contains('refused')), isEmpty);
      },
    );

    test(
      'signing key not ready: rows wait (pendingSign), the claim moves',
      () async {
        final (json, groupId) = await localBackup();
        final db = newDb();
        final t = net.clientFor(_mxid);
        t.crypto.ready = false;
        final c = ledger(db, t);
        await c.read(backupServiceProvider).restore(parseBackup(json));
        final members = await MembersDao(db).getMembers(groupId);
        expect(claimedBy(members, _mxid)?.pendingSign, isTrue);
        final expense = (await ExpensesDao(
          db,
        ).getAllExpensesForGroup(groupId)).single;
        expect(expense.pendingSign, isTrue);
        expect(expense.sig, isNull);
      },
    );

    test('a local backup restored in local mode stays as is', () async {
      final (json, groupId) = await localBackup();
      final db = newDb();
      final c = ledger(db, LocalOnlyTransport('Lea'));
      final preview = await c
          .read(backupServiceProvider)
          .preview(parseBackup(json), myMxid: kLocalAccountId);
      expect(preview.takeover, RestoreTakeover.none);
      expect(preview.otherAccount, isFalse);
      await c.read(backupServiceProvider).restore(parseBackup(json));
      final members = await MembersDao(db).getMembers(groupId);
      expect(claimedBy(members, kLocalAccountId)?.displayName, 'Lea');
      expect(members.every((m) => m.sig == null), isTrue);
    });
  });

  group('Matrix backup → local mode', () {
    test('verifies, makes the user "me", and adopts back on connect', () async {
      // The account's ledger, signed by its device.
      final source = ledger(newDb(), net.clientFor(_mxid));
      final groupId = await seedGroup(source, _mxid);
      final json = await source
          .read(backupServiceProvider)
          .exportJson(account: _mxid, now: 5000);
      final sourceMe = claimedBy(
        await source.read(membersDaoProvider).getMembers(groupId),
        _mxid,
      )!;

      // Local mode: signatures are checked (here with the fake keys).
      final localDb = newDb();
      final local = ledger(
        localDb,
        LocalOnlyTransport('Lea', verify: net.clientFor(_mxid).crypto.verify),
      );
      final svc = local.read(backupServiceProvider);
      final preview = await svc.preview(
        parseBackup(json),
        myMxid: kLocalAccountId,
      );
      expect(preview.takeover, RestoreTakeover.accountIntoLocal);
      expect(preview.otherAccount, isFalse);
      expect(await svc.restore(parseBackup(json)), [groupId]);
      expect(logs.where((l) => l.contains('refused')), isEmpty);

      final members = await MembersDao(localDb).getMembers(groupId);
      final me = claimedBy(members, kLocalAccountId)!;
      expect(me.userId, sourceMe.userId, reason: 'same participant');
      expect(me.pendingSign, isTrue);
      expect(claimedBy(members, _mxid), isNull);
      final expense = (await ExpensesDao(
        localDb,
      ).getAllExpensesForGroup(groupId)).single;
      expect(expense.sig?.user, _mxid, reason: 'kept as signed');
      local.listen(currentParticipantProvider(groupId), (_, _) {});
      expect(
        (await local.read(currentParticipantProvider(groupId).future))?.userId,
        me.userId,
      );

      // Connecting the same account later moves "me" back to it.
      final accountDb = newDb();
      final r = await adoptLocalLedger(
        target: accountDb,
        local: localDb,
        mxid: _mxid,
        crypto: net.clientFor(_mxid).crypto,
      );
      expect(r.groupIds, [groupId]);
      expect(r.allSigned, isTrue);
      final adopted = await MembersDao(accountDb).getMembers(groupId);
      expect(claimedBy(adopted, _mxid)?.userId, sourceMe.userId);
      expect(claimedBy(adopted, _mxid)?.sig?.user, _mxid);
      expect(adopted.where((m) => isLocalAccountId(m.matrixId)), isEmpty);
    });

    test('without the means to verify, nothing crashes', () async {
      final source = ledger(newDb(), net.clientFor(_mxid));
      await seedGroup(source, _mxid);
      final json = await source
          .read(backupServiceProvider)
          .exportJson(account: _mxid, now: 5000);
      final local = ledger(
        newDb(),
        LocalOnlyTransport('Lea', verify: (_, _, _) => false),
      );
      // Forged-looking versions are refused, the restore itself completes.
      expect(
        await local.read(backupServiceProvider).restore(parseBackup(json)),
        isEmpty,
      );
    });

    test('a participant of the local user already there is kept', () async {
      // reclaimGroupInPlace never creates a second "me".
      final db = newDb();
      final members = MembersDao(db);
      for (final (id, mxid) in [('p1', _mxid), ('p2', kLocalAccountId)]) {
        await members.upsertMemberLww(
          memberCompanion(
            MemberModel(
              groupId: 'g',
              userId: id,
              displayName: id,
              matrixId: mxid,
              status: 'active',
              updatedAt: 10,
            ),
          ),
        );
      }
      final reclaimed = await reclaimGroupInPlace(
        groups: GroupsDao(db),
        members: members,
        expenses: ExpensesDao(db),
        groupId: 'g',
        from: _mxid,
        to: kLocalAccountId,
        signLater: false,
      );
      expect(reclaimed, isFalse);
      final after = await members.getMembers('g');
      expect(after.firstWhere((m) => m.userId == 'p1').matrixId, _mxid);
    });
  });
}
