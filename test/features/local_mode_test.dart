/// G40: fully local mode — no Matrix account. The local profile opens its own
/// ledger DB, no Matrix client / sync / background job ever starts, "me" is
/// the participant claimed by the local pseudo account, and connecting a
/// Matrix account later moves everything into that account's DB, re-claims
/// "me" for the new MXID and signs every row with the new device's key — so
/// the account's other devices receive the groups and verify them.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/background/background_scheduler.dart';
import 'package:money_ledger/core/background/background_sync_provider.dart';
import 'package:money_ledger/core/database/account_database.dart';
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
import 'package:money_ledger/core/sync/ledger_sync_host.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/backup/backup_providers.dart';
import 'package:money_ledger/features/devices/device_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/local/local_mode_ui.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_auth_gateway.dart';
import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

/// Records what the OS scheduler was asked to do.
class _RecordingScheduler implements BackgroundScheduler {
  final calls = <String>[];
  @override
  Future<void> schedule() async => calls.add('schedule');
  @override
  Future<void> cancel() async => calls.add('cancel');
  @override
  Future<void> runOnce({Duration delay = Duration.zero}) async =>
      calls.add('once');
}

const _profile = '{"name":"Lea","created_at":1}';
const _mxid = '@lea:x.test';

void main() {
  late Directory tmp;
  late FakeAuthGateway gateway;
  late FakeMatrixNetwork net;
  late InMemoryDevicePrefsStore store;
  late _RecordingScheduler scheduler;
  var matrixClientBuilt = 0;
  final dbs = <AppDatabase>[];
  final localDbs = <AppDatabase>[];
  // G41: calls of the local-DB deleter, and whether every local DB instance
  // was closed at that moment.
  final localDeletes = <bool>[];

  AppDatabase fileDb(String name) {
    final db = AppDatabase.forTesting(
      NativeDatabase(File('${tmp.path}/$name.sqlite')),
    );
    dbs.add(db);
    return db;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('local_mode_');
    gateway = FakeAuthGateway();
    net = FakeMatrixNetwork();
    scheduler = _RecordingScheduler();
    matrixClientBuilt = 0;
    dbs.clear();
    localDbs.clear();
    localDeletes.clear();
  });

  tearDown(() async {
    gateway.dispose();
    for (final db in dbs) {
      await db.close();
    }
    await tmp.delete(recursive: true);
  });

  /// The app's providers, with the platform seams faked: the Matrix client
  /// (counts builds — local mode must never build one), the auth gateway,
  /// file-backed ledger DBs (they persist across close / reopen like the
  /// real ones) and a fake relay device for the account.
  ProviderContainer makeApp({
    Map<String, String> prefs = const {
      'welcome_seen': '1',
      'local_profile': _profile,
    },
  }) {
    store = InMemoryDevicePrefsStore(prefs);
    final c = ProviderContainer(
      overrides: [
        devicePrefsStoreProvider.overrideWithValue(store),
        matrixClientProvider.overrideWith((ref) {
          matrixClientBuilt++;
          return Completer<Never>().future;
        }),
        authGatewayProvider.overrideWith((ref) async => gateway),
        // The real provider's local branch; the Matrix branch is the fake
        // relay (the real one needs a Matrix client).
        ledgerTransportProvider.overrideWith((ref) async {
          if (ref.watch(localModeActiveProvider)) {
            return LocalOnlyTransport(ref.watch(localProfileProvider)!.name);
          }
          final id = ref.watch(accountUserIdProvider);
          if (id == null) return Completer<LedgerTransport>().future;
          return net.clientFor(id);
        }),
        accountDatabaseOpenerProvider.overrideWithValue(
          (mxid) => fileDb(accountDatabaseName(mxid)),
        ),
        localDatabaseOpenerProvider.overrideWithValue(() {
          final db = fileDb(localDatabaseName);
          localDbs.add(db);
          return db;
        }),
        localDatabaseDeleterProvider.overrideWithValue(() async {
          localDeletes.add(localDbs.every((db) => db.isClosed));
          return true;
        }),
        backgroundSchedulerProvider.overrideWithValue(scheduler),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
        localAdoptionKeyWaitProvider.overrideWithValue(
          const Duration(seconds: 2),
        ),
      ],
    );
    addTearDown(c.dispose);
    // What App / LedgerSyncHost keep alive.
    c.listen(ledgerSyncActiveProvider, (_, _) {});
    c.listen(backgroundSyncSchedulingProvider, (_, _) {});
    c.listen(localLedgerAdoptionProvider, (_, _) {});
    c.listen(appSessionProvider, (_, _) {});
    return c;
  }

  Future<void> settle(ProviderContainer c) async {
    await c.read(devicePrefsProvider.future);
    await net.settle();
  }

  Future<String> createLocalGroup(ProviderContainer c) async {
    await c.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await c.read(groupsDaoProvider).getAllGroups()).single.roomId;
    await c.read(memberAdderProvider.notifier).addLocal(groupId, 'Max');
    final members = await c.read(membersDaoProvider).getMembers(groupId);
    final me = members.firstWhere((m) => m.matrixId == kLocalAccountId);
    final max = members.firstWhere((m) => m.displayName == 'Max');
    await c
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: groupId,
          description: 'Dinner',
          amountCents: 4000,
          currency: 'EUR',
          paidBy: me.userId,
          splits: {me.userId: 2000, max.userId: 2000},
        );
    await c
        .read(expenseAdderProvider.notifier)
        .addSettlement(
          roomId: groupId,
          amountCents: 1000,
          currency: 'EUR',
          fromUser: max.userId,
          toUser: me.userId,
        );
    return groupId;
  }

  group('local mode', () {
    test(
      'opens the local ledger; no Matrix client, sync or background job',
      () async {
        final c = makeApp();
        await settle(c);

        expect(c.read(appSessionProvider), AppSessionKind.local);
        expect(c.read(localModeActiveProvider), isTrue);
        expect(c.read(ledgerIdentityProvider), kLocalAccountId);
        expect(c.read(isLoggedInProvider), isFalse);
        expect(c.read(accountUserIdProvider), isNull);
        final transport = await c.read(ledgerTransportProvider.future);
        expect(transport, isA<LocalOnlyTransport>());
        expect(transport.crypto.identity, isNull);

        // The sync components may be built by pages, but never start.
        expect(c.read(ledgerSyncActiveProvider), isFalse);
        await c.read(syncEngineProvider).ready;
        await c.read(ledgerSyncerProvider).ready;
        await expectLater(
          c.read(deviceGatewayProvider.future),
          throwsA(isA<StateError>()),
        );
        await settle(c);
        expect(matrixClientBuilt, 0);
        expect(net.sent, isEmpty);
        expect(scheduler.calls, everyElement('cancel'));
        expect(scheduler.calls, isNotEmpty);
        expect(dbs, hasLength(1));
      },
    );

    test(
      '"me" is the participant claimed by the local pseudo account',
      () async {
        final c = makeApp();
        await settle(c);
        final groupId = await createLocalGroup(c);

        final members = await c.read(membersDaoProvider).getMembers(groupId);
        final me = claimedBy(members, kLocalAccountId)!;
        expect(me.displayName, 'Lea', reason: 'named by the local profile');
        expect(me.userId, isNot(kLocalAccountId), reason: 'a fresh UUID');
        expect(me.isActive, isTrue);
        c.listen(currentParticipantProvider(groupId), (_, _) {});
        expect(
          (await c.read(currentParticipantProvider(groupId).future))?.userId,
          me.userId,
        );
        expect(c.read(currentUserIdProvider), kLocalAccountId);
        expect(groupExitKind(members, kLocalAccountId), GroupExitKind.delete);

        // Nothing can be signed without a Matrix device: stored pending.
        final group = (await c.read(groupsDaoProvider).getAllGroups()).single;
        expect(group.pendingSign, isTrue);
        final expenses = c.read(expensesDaoProvider);
        expect(
          (await expenses.getAllExpensesForGroup(groupId)).single.pendingSign,
          isTrue,
        );
        expect(
          (await expenses.getAllSettlementsForGroup(
            groupId,
          )).single.pendingSign,
          isTrue,
        );
        expect(net.sent, isEmpty);
        expect(matrixClientBuilt, 0);

        // The backup nudge covers every local group (nobody else has a copy).
        c.listen(backupNudgeProvider, (_, _) {});
        c.listen(allMembersProvider, (_, _) {});
        c.listen(lastBackupAtProvider, (_, _) {});
        c.listen(backupNudgeSnoozedUntilProvider, (_, _) {});
        c.listen(ledgerGroupsProvider, (_, _) {});
        c.listen(ownDeviceProtectionProvider, (_, _) {});
        await settle(c);
        for (var i = 0; i < 20 && c.read(backupNudgeProvider) == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(c.read(backupNudgeProvider), 1);
      },
    );

    test('"Delete local data" wipes the ledger and ends local mode', () async {
      final c = makeApp();
      await settle(c);
      await createLocalGroup(c);
      final db = c.read(appDatabaseProvider);
      await deleteLocalLedger(
        db: db,
        prefs: c.read(devicePrefsProvider.notifier),
        deleteFiles: c.read(localDatabaseDeleterProvider),
        releaseDb: () => c.invalidate(appDatabaseProvider),
      );
      expect(c.read(appSessionProvider), AppSessionKind.signedOut);
      // G41: the (closed) local DB's files are deleted too.
      expect(db.isClosed, isTrue);
      expect(localDeletes, [true]);
      expect(store.values.containsKey('local_profile'), isFalse);
      expect(store.values['welcome_seen'], '1');

      // Starting local mode again: an empty ledger.
      await c.read(devicePrefsProvider.notifier).startLocalProfile('Lea');
      expect(c.read(appSessionProvider), AppSessionKind.local);
      expect(await c.read(groupsDaoProvider).getAllGroups(), isEmpty);
    });
  });

  group('connecting a Matrix account', () {
    test(
      'adopts the local ledger: claims "me", signs every row, wipes local',
      () async {
        final c = makeApp();
        await settle(c);
        final groupId = await createLocalGroup(c);
        final localMe = claimedBy(
          await c.read(membersDaoProvider).getMembers(groupId),
          kLocalAccountId,
        )!;

        // Settings → Connect a Matrix account → login page.
        await c.read(devicePrefsProvider.notifier).setConnecting(true);
        expect(c.read(connectingAccountProvider), isTrue);
        expect(c.read(appSessionProvider), AppSessionKind.local);
        net.clientFor(_mxid); // the account's device on the relay
        await c
            .read(authProvider.notifier)
            .login(
              resolvedHomeserver: 'https://x.test',
              username: 'lea',
              password: 'pw',
            );
        await settle(c);
        for (
          var i = 0;
          i < 100 && store.values.containsKey('local_adopt_into');
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await settle(c);

        expect(c.read(appSessionProvider), AppSessionKind.matrix);
        expect(c.read(ledgerIdentityProvider), _mxid);
        expect(store.values.containsKey('local_profile'), isFalse);
        expect(store.values.containsKey('local_adopt_into'), isFalse);
        expect(store.values['local_last_adopted_into'], _mxid);
        expect(c.read(localAdoptionResultProvider)?.groupIds, [groupId]);

        final db = c.read(appDatabaseProvider);
        final members = await MembersDao(db).getMembers(groupId);
        final me = claimedBy(members, _mxid)!;
        expect(
          me.userId,
          localMe.userId,
          reason: 'same participant, history kept',
        );
        expect(me.displayName, 'Lea');
        expect(me.isActive, isTrue);
        expect(members.where((m) => m.matrixId == kLocalAccountId), isEmpty);

        // Everything signed by the account's device (none left pending).
        final group = await GroupsDao(db).getGroup(groupId);
        expect(group!.sig?.user, _mxid);
        expect(group.pendingSign, isFalse);
        for (final m in members) {
          expect(m.sig, isNotNull, reason: m.displayName);
          expect(m.pendingSign, isFalse);
        }
        final expense = (await ExpensesDao(
          db,
        ).getAllExpensesForGroup(groupId)).single;
        expect(expense.sig?.user, _mxid);
        expect(expense.origin?.user, _mxid, reason: '"added by" you');
        final payment = (await ExpensesDao(
          db,
        ).getAllSettlementsForGroup(groupId)).single;
        expect(payment.sig, isNotNull);
        expect(payment.origin, isNotNull);

        // G41: its files are deleted once every local instance is closed.
        for (var i = 0; i < 100 && localDeletes.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(localDeletes, [true]);

        // The local ledger is empty now (local mode would start fresh).
        final local = fileDb(localDatabaseName);
        expect(await GroupsDao(local).getAllGroups(), isEmpty);
        expect(await MembersDao(local).getMembers(groupId), isEmpty);
      },
    );

    test(
      "the account's other device receives the adopted group and verifies it",
      () async {
        final c = makeApp();
        await settle(c);
        final groupId = await createLocalGroup(c);

        // The account's other device, already running (empty).
        final otherDb = openTestDatabase();
        addTearDown(otherDb.close);
        final other = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(otherDb),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor(_mxid, device: 'D2'),
            ),
            pokeDebounceProvider.overrideWithValue(
              const Duration(milliseconds: 1),
            ),
            syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
          ],
        );
        addTearDown(other.dispose);
        other.listen(ledgerSyncerProvider, (_, _) {});
        other.listen(syncEngineProvider, (_, _) {});
        net.clientFor(_mxid);
        await net.settle();

        await c.read(devicePrefsProvider.notifier).setConnecting(true);
        await c
            .read(authProvider.notifier)
            .login(
              resolvedHomeserver: 'https://x.test',
              username: 'lea',
              password: 'pw',
            );
        for (
          var i = 0;
          i < 100 && store.values.containsKey('local_adopt_into');
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await net.settle();
        // Next digest cycle (the adoption also poked each group).
        await c.read(syncEngineProvider).broadcastDigests();
        await net.settle();

        final groups = await GroupsDao(otherDb).getAllGroups();
        expect(groups.map((g) => g.roomId), [groupId]);
        final expense = (await ExpensesDao(
          otherDb,
        ).getAllExpensesForGroup(groupId)).single;
        expect(expense.description, 'Dinner');
        expect(expense.sig?.user, _mxid);
        expect(
          await ExpensesDao(otherDb).getAllSettlementsForGroup(groupId),
          hasLength(1),
        );
        final members = await MembersDao(otherDb).getMembers(groupId);
        expect(claimedBy(members, _mxid)?.displayName, 'Lea');
        expect(members.map((m) => m.displayName), containsAll(['Lea', 'Max']));
      },
    );

    test(
      'merges into an account that already has groups; idempotent',
      () async {
        final c = makeApp();
        await settle(c);
        final localGroup = await createLocalGroup(c);

        // The account already holds a group of its own on this device.
        final accountDb = fileDb(accountDatabaseName(_mxid));
        await GroupsDao(accountDb).upsertGroupLww(
          groupCompanion(
            const GroupModel(roomId: 'own', name: 'Flat', currency: 'EUR'),
          ),
        );
        await accountDb.close();

        await c.read(devicePrefsProvider.notifier).setConnecting(true);
        net.clientFor(_mxid);
        await c
            .read(authProvider.notifier)
            .login(
              resolvedHomeserver: 'https://x.test',
              username: 'lea',
              password: 'pw',
            );
        for (
          var i = 0;
          i < 100 && store.values.containsKey('local_adopt_into');
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await settle(c);
        final db = c.read(appDatabaseProvider);
        Future<List<String>> ids() async =>
            [for (final g in await GroupsDao(db).getAllGroups()) g.roomId]
              ..sort();
        expect(await ids(), (['own', localGroup]..sort()));

        // Re-running (e.g. after a crash before the preference was cleared)
        // merges the same rows again — nothing is duplicated.
        final again = await adoptLocalLedger(
          target: db,
          local: fileDb(localDatabaseName),
          mxid: _mxid,
          crypto: net.clientFor(_mxid).crypto,
        );
        expect(again.groupIds, isEmpty, reason: 'the local ledger was wiped');
        expect(await ids(), (['own', localGroup]..sort()));
        expect(await MembersDao(db).getMembers(localGroup), hasLength(2));
      },
    );

    test('a cancelled connect stays in local mode', () async {
      final c = makeApp();
      await settle(c);
      await c.read(devicePrefsProvider.notifier).setConnecting(true);
      expect(c.read(connectingAccountProvider), isTrue);
      await c.read(devicePrefsProvider.notifier).setConnecting(false);
      expect(c.read(connectingAccountProvider), isFalse);
      expect(c.read(appSessionProvider), AppSessionKind.local);
      expect(store.values.containsKey('local_connecting'), isFalse);
    });
  });

  group('adoptedMember (pure)', () {
    test('re-claims the local pseudo account with a newer clock', () {
      const m = MemberModel(
        groupId: 'g',
        userId: 'p1',
        displayName: 'Lea',
        matrixId: kLocalAccountId,
        status: 'active',
        updatedAt: 100,
        pendingSign: true,
      );
      final a = adoptedMember(m, _mxid);
      expect(a.matrixId, _mxid);
      expect(a.userId, 'p1');
      expect(a.updatedAt, greaterThan(100));
      expect(a.pendingSign, isTrue);
    });

    test('other participants only wait for a signature when unsigned', () {
      const m = MemberModel(
        groupId: 'g',
        userId: 'p2',
        displayName: 'Max',
        status: 'active',
        updatedAt: 100,
      );
      final a = adoptedMember(m, _mxid);
      expect(a.matrixId, isNull);
      expect(a.updatedAt, 100);
      expect(a.pendingSign, isTrue);
    });
  });
}
