/// G18 second security review — end-to-end regressions over the in-memory
/// relay. Each scenario failed against the code before its fix (the Major 1
/// scenario is the reviewer's repro, `zz_g18r2_forged_local_backup_test`).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/device_prefs.dart';
import 'package:money_ledger/core/session/local_adoption.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/backup/backup_service.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const _lea = '@lea:x.test';
const _max = '@max:x.test';

void main() {
  late FakeMatrixNetwork net;
  late List<String> logs;
  final dbs = <AppDatabase>[];
  final original = debugPrint;

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

  AppDatabase newDb() {
    final db = openTestDatabase();
    dbs.add(db);
    return db;
  }

  /// A ledger: [db] with relay identity [transport]; syncing when [sync].
  ProviderContainer ledger(
    AppDatabase db,
    Object transport, {
    bool sync = true,
    List<dynamic> extra = const [],
  }) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith(
          (ref) async => transport as dynamic,
        ),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
        digestOnStartProvider.overrideWithValue(false),
        ...extra,
      ],
    );
    addTearDown(c.dispose);
    if (sync) {
      c.listen(ledgerSyncerProvider, (_, _) {});
      c.listen(syncEngineProvider, (_, _) {});
    }
    return c;
  }

  /// Max creates "Trip" with Lea and a 40 € dinner split evenly; returns
  /// (group id, Max's ledger, Lea's ledger, Max's DB, Lea's DB).
  Future<
    (String, ProviderContainer, ProviderContainer, AppDatabase, AppDatabase)
  >
  trip() async {
    final maxDb = newDb(), leaDb = newDb();
    final max = ledger(maxDb, net.clientFor(_max));
    final lea = ledger(leaDb, net.clientFor(_lea));
    await max.read(ledgerTransportProvider.future);
    await lea.read(ledgerTransportProvider.future);
    await net.settle();
    await max.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final gid =
        (await max.read(groupsDaoProvider).getAllGroups()).single.roomId;
    await max.read(memberAdderProvider.notifier).add(gid, _lea);
    await net.settle();
    final ms = await max.read(membersDaoProvider).getMembers(gid);
    final pMax = claimedBy(ms, _max)!.userId;
    final pLea = claimedBy(ms, _lea)!.userId;
    await max
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: gid,
          description: 'Dinner',
          amountCents: 4000,
          currency: 'EUR',
          paidBy: pMax,
          splits: {pMax: 2000, pLea: 2000},
        );
    await net.settle();
    return (gid, max, lea, maxDb, leaDb);
  }

  /// Lea's backup with its expense forged: signature stripped, the genuine
  /// creation statement (`origin`) kept, the content changed, a newer clock.
  Future<Map<String, dynamic>> forgedBackup(
    ProviderContainer lea, {
    String? account,
  }) async {
    final real =
        jsonDecode(
              await lea
                  .read(backupServiceProvider)
                  .exportJson(account: _lea, now: 1),
            )
            as Map<String, dynamic>;
    if (account != null) real['account'] = account;
    final g = (real['groups'] as List).single as Map<String, dynamic>;
    final e = (g['expenses'] as List).single as Map<String, dynamic>;
    final split = (e['split'] as Map).keys.toList();
    e
      ..remove('sig')
      ..['amount'] = 400000
      ..['split'] = {split[0]: 0, split[1]: 400000}
      ..['description'] = 'Forged'
      ..['updated_at'] = (e['updated_at'] as int) + 1000;
    return real;
  }

  group('Major 1: a crafted backup never makes this device sign it', () {
    test('a "local" backup of a shared group: restored as unsigned legacy, '
        'nothing signed, peers keep the real version', () async {
      final (gid, max, lea, maxDb, leaDb) = await trip();
      final crafted = await forgedBackup(lea, account: kLocalAccountId);
      final svc = lea.read(backupServiceProvider);
      final preview = await svc.preview(
        parseBackup(jsonEncode(crafted)),
        myMxid: _lea,
      );
      expect(preview.takeover, RestoreTakeover.localIntoAccount);
      await svc.restore(parseBackup(jsonEncode(crafted)));
      await lea.read(syncEngineProvider).broadcastDigests();
      await net.settle();

      final atMax = (await ExpensesDao(
        maxDb,
      ).getAllExpensesForGroup(gid)).single;
      expect(atMax.description, 'Dinner', reason: 'the forgery never syncs');
      expect(atMax.amountCents, 4000);
      final atLea = (await ExpensesDao(
        leaDb,
      ).getAllExpensesForGroup(gid)).single;
      expect(atLea.sig, isNull, reason: 'never signed by this device');
      expect(atLea.pendingSign, isFalse);
      expect(atLea.origin, isNull, reason: 'no "added by" on an unsigned row');
      // Nothing of the group waits for a signature either.
      for (final m in await MembersDao(leaDb).getMembers(gid)) {
        expect(m.pendingSign, isFalse, reason: m.displayName);
        expect(m.matrixId, isNot(kLocalAccountId));
      }
      expect((await GroupsDao(leaDb).getGroup(gid))!.pendingSign, isFalse);
    });

    test('the same file restored on a fresh device of the account: the '
        'group is new but shared — still nothing signed', () async {
      final (gid, max, lea, maxDb, _) = await trip();
      final crafted = await forgedBackup(lea, account: kLocalAccountId);
      final freshDb = newDb();
      final fresh = ledger(freshDb, net.clientFor(_lea, device: 'D2'));
      await net.settle();
      await fresh
          .read(backupServiceProvider)
          .restore(parseBackup(jsonEncode(crafted)));
      await fresh.read(syncEngineProvider).broadcastDigests();
      await net.settle();
      for (final e in await ExpensesDao(freshDb).getAllExpensesForGroup(gid)) {
        if (e.description == 'Forged') {
          expect(e.sig, isNull);
          expect(e.pendingSign, isFalse);
        }
      }
      final atMax = (await ExpensesDao(
        maxDb,
      ).getAllExpensesForGroup(gid)).single;
      expect(atMax.description, 'Dinner');
    });

    test('a normal restore strips a forged origin and signs nothing', () async {
      final (gid, _, lea, _, leaDb) = await trip();
      final crafted = await forgedBackup(lea);
      expect(crafted['account'], _lea);
      final e0 =
          ((crafted['groups'] as List).single['expenses'] as List).single
              as Map;
      expect(e0['origin'], isNotNull, reason: 'the forgery keeps the origin');
      // A fresh device: nothing stored yet, so no origin to keep either.
      final freshDb = newDb();
      final fresh = ledger(freshDb, net.clientFor(_lea, device: 'D3'));
      await fresh
          .read(backupServiceProvider)
          .restore(parseBackup(jsonEncode(crafted)));
      final e = (await ExpensesDao(freshDb).getAllExpensesForGroup(gid)).single;
      expect(e.description, 'Forged');
      expect(e.origin, isNull);
      expect(e.sig, isNull);
      expect(e.pendingSign, isFalse);
      // Even where the record is known: an unsigned row carries no origin.
      await lea
          .read(backupServiceProvider)
          .restore(parseBackup(jsonEncode(crafted)));
      final kept = (await ExpensesDao(
        leaDb,
      ).getAllExpensesForGroup(gid)).single;
      expect(kept.origin, isNull);
      expect(kept.sig, isNull);
      expect(kept.pendingSign, isFalse);
    });

    test('a Matrix backup in local mode: an unsigned claim is never taken '
        'over, legacy rows are never signed on connect', () async {
      final (gid, _, lea, _, _) = await trip();
      final crafted = await forgedBackup(lea);
      // Also forge Max's participant as claimed by Lea (unsigned, newer).
      final g = (crafted['groups'] as List).single as Map<String, dynamic>;
      final ms = (g['members'] as List).cast<Map<String, dynamic>>();
      final maxEntry = ms.firstWhere((m) => m['matrix_id'] == _max);
      final leaEntry = ms.firstWhere((m) => m['matrix_id'] == _lea);
      maxEntry
        ..remove('sig')
        ..['matrix_id'] = _lea
        ..['updated_at'] = (maxEntry['updated_at'] as int) + 1;

      final localDb = newDb();
      final local = ledger(
        localDb,
        LocalOnlyTransport('Lea', verify: net.clientFor(_lea).crypto.verify),
        sync: false,
      );
      await local
          .read(backupServiceProvider)
          .restore(parseBackup(jsonEncode(crafted)));
      final members = await MembersDao(localDb).getMembers(gid);
      final me = claimedBy(members, kLocalAccountId)!;
      expect(me.userId, leaEntry['participant_id'], reason: 'the signed one');
      final forgedClaim = members.firstWhere(
        (m) => m.userId == maxEntry['participant_id'],
      );
      expect(forgedClaim.matrixId, _lea, reason: 'stored as legacy only');
      expect(forgedClaim.pendingSign, isFalse);
      final e = (await ExpensesDao(localDb).getAllExpensesForGroup(gid)).single;
      expect(e.sig, isNull);
      expect(e.pendingSign, isFalse);

      // Connecting the account: only local mode's own claim is signed.
      final accountDb = newDb();
      await adoptLocalLedger(
        target: accountDb,
        local: localDb,
        mxid: _lea,
        crypto: net.clientFor(_lea).crypto,
      );
      final adopted = await MembersDao(accountDb).getMembers(gid);
      expect(adopted.firstWhere((m) => m.userId == me.userId).sig?.user, _lea);
      final notSigned = adopted.firstWhere(
        (m) => m.userId == maxEntry['participant_id'],
      );
      expect(notSigned.sig, isNull);
      expect(notSigned.pendingSign, isFalse);
      final ae = (await ExpensesDao(
        accountDb,
      ).getAllExpensesForGroup(gid)).single;
      expect(ae.description, 'Forged');
      expect(ae.sig, isNull, reason: 'a restored legacy row stays unsigned');
      expect(ae.pendingSign, isFalse);
    });

    test("local mode's own backup restored in local mode keeps working: its "
        'rows are local writes again and get signed on connect', () async {
      final makeDb = newDb();
      final maker = ledger(makeDb, LocalOnlyTransport('Lea'), sync: false);
      await maker.read(ledgerTransportProvider.future);
      await maker.read(groupCreatorProvider.notifier).create('Flat', 'EUR');
      final gid =
          (await maker.read(groupsDaoProvider).getAllGroups()).single.roomId;
      final me = claimedBy(
        await maker.read(membersDaoProvider).getMembers(gid),
        kLocalAccountId,
      )!;
      await maker
          .read(expenseAdderProvider.notifier)
          .addExpense(
            roomId: gid,
            description: 'Rent',
            amountCents: 1000,
            currency: 'EUR',
            paidBy: me.userId,
            splits: {me.userId: 1000},
          );
      final json = await maker
          .read(backupServiceProvider)
          .exportJson(account: kLocalAccountId, now: 1);

      final localDb = newDb();
      final local = ledger(localDb, LocalOnlyTransport('Lea'), sync: false);
      await local.read(backupServiceProvider).restore(parseBackup(json));
      final e = (await ExpensesDao(localDb).getAllExpensesForGroup(gid)).single;
      expect(e.pendingSign, isTrue, reason: "local mode's own row");
      expect(e.sig, isNull);

      final accountDb = newDb();
      final r = await adoptLocalLedger(
        target: accountDb,
        local: localDb,
        mxid: _lea,
        crypto: net.clientFor(_lea).crypto,
      );
      expect(r.allSigned, isTrue);
      final signed = (await ExpensesDao(
        accountDb,
      ).getAllExpensesForGroup(gid)).single;
      expect(signed.sig?.user, _lea);
      expect(signed.origin?.user, _lea);
    });
  });

  group('Major 3: inbound matrix ids are validated', () {
    test(
      'a member version claiming local:self (or garbage) is refused',
      () async {
        final (gid, max, _, _, leaDb) = await trip();
        final mc = net.clientFor(_max).crypto;
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final (pid, claim) in [
          ('p-planted', kLocalAccountId),
          ('p-garbage', 'not an id'),
        ]) {
          final planted = await signMember(
            mc,
            MemberModel(
              groupId: gid,
              userId: pid,
              displayName: 'Planted',
              matrixId: claim,
              status: 'active',
              updatedAt: now,
            ),
          );
          await net
              .clientFor(_max)
              .sendToUsers({_lea}, memberEventType, memberPayload(planted));
          await net.settle();
        }
        final ms = await MembersDao(leaDb).getMembers(gid);
        expect(ms.map((m) => m.userId), isNot(contains('p-planted')));
        expect(ms.map((m) => m.userId), isNot(contains('p-garbage')));
        expect(
          logs.where((l) => l.contains('invalid_record: invalid matrix id')),
          hasLength(2),
        );
        // …and a digest gossiping it is refused the same way (no loop).
        await max.read(syncEngineProvider).broadcastDigests();
        await net.settle();
        expect(
          (await MembersDao(leaDb).getMembers(gid)).map((m) => m.userId),
          isNot(contains('p-planted')),
        );
      },
    );

    test('replication targets are valid MXIDs only', () async {
      final db = newDb();
      final members = MembersDao(db);
      for (final (pid, claim) in [
        ('a', _lea),
        ('b', kLocalAccountId),
        ('c', 'garbage'),
        ('d', null),
      ]) {
        await members.upsertMemberLww(
          memberCompanion(
            MemberModel(
              groupId: 'g',
              userId: pid,
              matrixId: claim,
              status: 'active',
              updatedAt: 1,
            ),
          ),
        );
      }
      expect(await members.activeClaimedMatrixIds('g'), [_lea]);
    });

    test('a restore into an account refuses local:self claims of a '
        "non-local backup", () async {
      final (gid, _, lea, _, _) = await trip();
      final crafted =
          jsonDecode(
                await lea
                    .read(backupServiceProvider)
                    .exportJson(account: _lea, now: 1),
              )
              as Map<String, dynamic>;
      final g = (crafted['groups'] as List).single as Map<String, dynamic>;
      (g['members'] as List).add({
        'v': protocolVersion,
        'group': gid,
        'participant_id': 'p-x',
        'name': 'X',
        'matrix_id': kLocalAccountId,
        'status': 'active',
        'updated_at': 5,
      });
      final freshDb = newDb();
      final fresh = ledger(freshDb, net.clientFor(_lea, device: 'D4'));
      await fresh
          .read(backupServiceProvider)
          .restore(parseBackup(jsonEncode(crafted)));
      final ms = await MembersDao(freshDb).getMembers(gid);
      expect(ms.map((m) => m.userId), isNot(contains('p-x')));
    });
  });

  group('Minor 2: a record id of another group', () {
    test('a peer version naming another group is refused, the record stays '
        'where it is', () async {
      final (gid, max, _, _, leaDb) = await trip();
      await max.read(groupCreatorProvider.notifier).create('Flat', 'EUR');
      final flat = (await max.read(groupsDaoProvider).getAllGroups())
          .firstWhere((g) => g.name == 'Flat')
          .roomId;
      await max.read(memberAdderProvider.notifier).add(flat, _lea);
      await net.settle();
      final victim = (await ExpensesDao(
        leaDb,
      ).getAllExpensesForGroup(gid)).single;
      final pMax = claimedBy(
        await max.read(membersDaoProvider).getMembers(flat),
        _max,
      )!.userId;
      final moved = await signExpense(
        net.clientFor(_max).crypto,
        ExpenseModel(
          id: victim.id,
          roomId: flat,
          description: 'Moved',
          amountCents: 100,
          currency: 'EUR',
          paidBy: pMax,
          splitsJson: '{"$pMax":100}',
          createdAt: victim.createdAt,
          updatedAt: victim.updatedAt + 10,
        ),
        creating: true,
      );
      await net
          .clientFor(_max)
          .sendToUsers({_lea}, expenseEventType, expensePayload(moved));
      await net.settle();
      final after = await ExpensesDao(leaDb).getExpenseById(victim.id);
      expect(after!.roomId, gid);
      expect(after.description, 'Dinner');
      expect(
        logs.where((l) => l.contains('id belongs to another group')),
        isNotEmpty,
      );
    });

    test('the DAO never moves a row to another group (last guard)', () async {
      final db = newDb();
      final dao = ExpensesDao(db);
      ExpenseModel e(String group, int at) => ExpenseModel(
        id: 'e1',
        roomId: group,
        description: group,
        amountCents: 100,
        currency: 'EUR',
        paidBy: 'p',
        splitsJson: '{"p":100}',
        createdAt: 1,
        updatedAt: at,
      );
      await dao.upsertExpenseLww(expenseCompanion(e('g1', 1)));
      await dao.upsertExpenseLww(expenseCompanion(e('g2', 99)));
      expect((await dao.getExpenseById('e1'))!.roomId, 'g1');
      final s = SettlementModel(
        id: 's1',
        roomId: 'g1',
        amountCents: 100,
        currency: 'EUR',
        fromUser: 'a',
        toUser: 'b',
        createdAt: 1,
        updatedAt: 1,
      );
      await dao.upsertSettlementLww(settlementCompanion(s));
      await dao.upsertSettlementLww(
        settlementCompanion(
          SettlementModel(
            id: 's1',
            roomId: 'g2',
            amountCents: 100,
            currency: 'EUR',
            fromUser: 'a',
            toUser: 'b',
            createdAt: 1,
            updatedAt: 50,
          ),
        ),
      );
      expect((await dao.getSettlementById('s1'))!.roomId, 'g1');
    });
  });

  group('Minor 4: the engine leaves adopted rows to the adoption', () {
    test('no signing while an adoption into this account is pending', () async {
      final db = newDb();
      final store = InMemoryDevicePrefsStore({'local_adopt_into': _lea});
      final c = ledger(
        db,
        net.clientFor(_lea),
        extra: [devicePrefsStoreProvider.overrideWithValue(store)],
      );
      await c.read(devicePrefsProvider.future);
      await c.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
      final gid =
          (await c.read(groupsDaoProvider).getAllGroups()).single.roomId;
      final me = claimedBy(
        await c.read(membersDaoProvider).getMembers(gid),
        _lea,
      )!;
      // An adopted (local-mode) row, edited there: created ≠ updated.
      await ExpensesDao(db).upsertExpenseLww(
        expenseCompanion(
          ExpenseModel(
            id: 'adopted',
            roomId: gid,
            description: 'Rent',
            amountCents: 100,
            currency: 'EUR',
            paidBy: me.userId,
            splitsJson: '{"${me.userId}":100}',
            createdAt: 1000,
            updatedAt: 2000,
            pendingSign: true,
          ),
        ),
      );
      await net.settle();
      await c.read(syncEngineProvider).broadcastDigests();
      await net.settle();
      expect(
        (await ExpensesDao(db).getExpenseById('adopted'))!.pendingSign,
        isTrue,
      );

      // Adoption finished → the engine may sign again (adoption itself would
      // have signed with "added by").
      await c.read(devicePrefsProvider.notifier).finishLocalAdoption(_lea);
      await c.read(syncEngineProvider).broadcastDigests();
      await net.settle();
      final e = (await ExpensesDao(db).getExpenseById('adopted'))!;
      expect(e.pendingSign, isFalse);
      expect(e.sig?.user, _lea);
    });
  });
}
