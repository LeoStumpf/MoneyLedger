/// G52 step 8: the background round's **link phase** (design doc §8.3) —
/// one full fetch of every link group on every relay, merge, publish what
/// changed, close — against the fake relays and a file-backed ledger: in
/// local mode (no Matrix session is ever opened), next to the Matrix phase,
/// skipped without link groups / while connecting, and stopped mid-fetch.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/notifications/change_notices.dart';
import 'package:money_ledger/core/background/background_round.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/link/link_envelope.dart';
import 'package:money_ledger/core/link/nostr/nostr_event.dart';
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/fake_relay_network.dart';
import '../helpers/in_memory_database.dart';

const _r1 = 'wss://nos.lol';
const _r2 = 'wss://nostr.mom';
const _g = 'G';
const _t0 = 1792000000000;
const _bob = '@bob:y.org';

class _Session implements BackgroundSession {
  _Session(this.transport);

  @override
  final LedgerTransport transport;
  int fetches = 0;
  bool closed = false;

  @override
  String get userId => transport.userId;

  @override
  Future<void> fetchOnce({Duration wait = Duration.zero}) async => fetches++;

  @override
  Future<void> close() async => closed = true;
}

void main() {
  late Directory tmp;
  late FakeRelayNetwork net;
  late int now;
  final containers = <ProviderContainer>[];
  final dbs = <AppDatabase>[];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bg_link_');
    now = _t0;
    net = FakeRelayNetwork(nowSeconds: () => now ~/ 1000);
  });

  tearDown(() async {
    for (final c in containers) {
      c.dispose();
    }
    containers.clear();
    for (final d in dbs) {
      if (!d.isClosed) await d.close();
    }
    dbs.clear();
    await tmp.delete(recursive: true);
  });

  /// The round's link overrides (it turns NIP-11 fetches off itself).
  List<Override> linkOverrides() => [
    linkRelayConnectorProvider.overrideWithValue(net),
    linkClockProvider.overrideWithValue(() => now),
    linkPublishDebounceProvider.overrideWithValue(
      const Duration(milliseconds: 1),
    ),
    linkPublishMinIntervalProvider.overrideWithValue(Duration.zero),
    linkAppLifecycleProvider.overrideWithValue(false),
    linkVerifySignaturesProvider.overrideWithValue(false),
    linkAppVersionProvider.overrideWith((ref) async => 'test'),
  ];

  /// A running app with the link engine on [db].
  ProviderContainer app(AppDatabase db, {String identity = kLocalAccountId}) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerIdentityProvider.overrideWithValue(identity),
        ledgerTransportProvider.overrideWith(
          (ref) async => LocalOnlyTransport('me'),
        ),
        ...linkOverrides(),
        linkRelayInfoFetcherProvider.overrideWithValue(null),
      ],
    );
    containers.add(c);
    c.listen(linkSyncEngineProvider, (_, _) {});
    return c;
  }

  AppDatabase fileDb(String name) {
    final db = AppDatabase.forTesting(
      NativeDatabase(File('${tmp.path}/$name.sqlite')),
    );
    dbs.add(db);
    return db;
  }

  Future<void> putExpense(AppDatabase db, String id, {required int at}) =>
      ExpensesDao(db).upsertExpenseLww(
        expenseCompanion(
          ExpenseModel(
            id: id,
            roomId: _g,
            description: 'Dinner $id',
            amountCents: 1000,
            currency: 'EUR',
            paidBy: 'p1',
            splitsJson: jsonEncode({'p1': 500, 'p2': 500}),
            createdAt: at,
            updatedAt: at,
            linkAuthor: 'p1',
          ),
        ),
      );

  /// Waits until the relays are quiet and [c]'s engine is idle.
  Future<void> settle(ProviderContainer c) async {
    final sw = Stopwatch()..start();
    var quiet = 0;
    while (quiet < 3) {
      await net.settle();
      await Future<void>.delayed(const Duration(milliseconds: 3));
      if (c.read(linkSyncEngineProvider).isIdle) {
        quiet++;
      } else {
        quiet = 0;
      }
      if (sw.elapsed > const Duration(seconds: 20)) fail('never idle');
    }
  }

  /// Anna's running app (in-memory, local mode): group "Trip" (p1 = Anna
  /// via local:self, p2 = Ben) + one expense, shared by link.
  Future<(ProviderContainer, LinkChannelModel)> anna() async {
    final db = openTestDatabase();
    dbs.add(db);
    final c = app(db);
    await c.read(linkSyncEngineProvider).ready;
    await GroupsDao(db).upsertGroupLww(
      groupCompanion(
        const GroupModel(
          roomId: _g,
          name: 'Trip',
          currency: 'EUR',
          updatedAt: _t0 - 5000,
          pendingSign: true,
        ),
      ),
    );
    for (final (pid, claim) in [('p1', kLocalAccountId), ('p2', null)]) {
      await MembersDao(db).upsertMemberLww(
        memberCompanion(
          MemberModel(
            groupId: _g,
            userId: pid,
            displayName: pid == 'p1' ? 'Anna' : 'Ben',
            matrixId: claim,
            status: 'active',
            updatedAt: _t0 - 5000,
            pendingSign: true,
          ),
        ),
      );
    }
    await putExpense(db, 'e1', at: _t0 - 4000);
    final ch = await c.read(linkSyncEngineProvider).openChannel(_g);
    await settle(c);
    return (c, ch);
  }

  /// Ben joined Anna's link (as p2) on his device with ledger file [name],
  /// then closed the app.
  Future<String> benJoinedAndClosed(
    LinkChannelModel annaChannel, {
    String name = 'ben',
    String identity = kLocalAccountId,
  }) async {
    final db = fileDb(name);
    final c = app(db, identity: identity);
    await c.read(linkSyncEngineProvider).ready;
    await LinkDao(db).putChannel(
      LinkChannelModel(
        groupId: _g,
        epoch: 1,
        secret: annaChannel.secret,
        nostrPriv: generateNostrPrivateKey(),
        openedAt: now,
        myParticipantId: 'p2',
      ),
    );
    await c.read(linkSyncEngineProvider).refresh(groupId: _g);
    await settle(c);
    expect(await ExpensesDao(db).getAllExpensesForGroup(_g), hasLength(1));
    c.dispose();
    containers.remove(c);
    await db.close();
    return name;
  }

  Future<BackgroundRoundResult> round({
    required String dbName,
    BackgroundLedger ledger = BackgroundLedger.local,
    _Session? session,
    Future<void>? abort,
    void Function()? onOpenSession,
    Future<void> Function(List<ChangeNotice>)? notify,
  }) => runBackgroundRound(
    tryAcquire: () async => true,
    whichLedger: () async => ledger,
    openSession: () async {
      onOpenSession?.call();
      return session;
    },
    openDatabase: (_) => fileDb(dbName),
    openLocalDatabase: () => fileDb(dbName),
    linkOverrides: linkOverrides(),
    abort: abort,
    timeout: const Duration(seconds: 20),
    quietPeriod: const Duration(milliseconds: 100),
    pokeDebounce: const Duration(milliseconds: 1),
    followUpWait: Duration.zero,
    inFlightGrace: const Duration(milliseconds: 500),
    clock: () => now,
    notify: notify,
  );

  /// EVENT frames of kind 31847 that [pubkey] sent to [relay].
  int eventsFrom(String relay, String pubkey) => net
      .relay(relay)
      .received
      .map(jsonDecode)
      .where(
        (f) =>
            f is List &&
            f.first == 'EVENT' &&
            (f[1] as Map)['pubkey'] == pubkey &&
            (f[1] as Map)['kind'] == kLinkEventKind,
      )
      .length;

  test("G72: a link group — the peer's new expense is announced with its "
      "author's name", () async {
    final (a, annaChannel) = await anna();
    final name = await benJoinedAndClosed(annaChannel);
    now += 60000;
    await putExpense(a.read(appDatabaseProvider), 'e2', at: now);
    await settle(a);

    final posted = <ChangeNotice>[];
    final result = await round(
      dbName: name,
      notify: (n) async => posted.addAll(n),
    );
    expect(result.status, BackgroundRoundStatus.completed, reason: '$result');
    expect(result.notified, 1);
    final c = posted.single.changes.single;
    expect(posted.single.groupName, 'Trip');
    expect(c.description, 'Dinner e2');
    expect(c.author, 'Anna');
    expect(c.action, NoticeAction.added);
  });

  test('local mode: fetches + merges what the peer published while the app '
      'was closed, publishes once after the merge, closes every connection — '
      'and never opens a Matrix session', () async {
    final (a, annaChannel) = await anna();
    final name = await benJoinedAndClosed(annaChannel);
    final connectionsBefore = net.relay(_r1).connectionCount;

    now += 60000;
    await putExpense(a.read(appDatabaseProvider), 'e2', at: now);
    await settle(a);

    var sessionOpened = false;
    final result = await round(
      dbName: name,
      onOpenSession: () => sessionOpened = true,
    );
    await net.settle();

    expect(result.status, BackgroundRoundStatus.completed, reason: '$result');
    expect(result.link, isTrue);
    expect(result.linkMerged, greaterThanOrEqualTo(1));
    expect(sessionOpened, isFalse);

    final db = fileDb(name);
    final ids = {
      for (final e in await ExpensesDao(db).getAllExpensesForGroup(_g)) e.id,
    };
    expect(ids, {'e1', 'e2'});
    final ch = (await LinkDao(db).getChannel(_g))!;
    final benPub = nostrPublicKey(ch.nostrPriv);
    // Exactly one publish in the round (one part): after the merge, never a
    // stale start-up publish first.
    expect(ch.lastPublishedAt, now);
    expect(
      eventsFrom(_r1, benPub),
      2,
      reason: 'one publish when joining, one in the round',
    );
    expect(eventsFrom(_r2, benPub), 2);
    // No live subscription left behind: only Anna's app is connected.
    expect(net.relay(_r1).connectionCount, connectionsBefore);
  });

  test(
    'nothing changed → the link phase fetches but publishes nothing',
    () async {
      final (_, annaChannel) = await anna();
      final name = await benJoinedAndClosed(annaChannel);
      now += 60000;
      final result = await round(dbName: name);
      await net.settle();
      expect(result.status, BackgroundRoundStatus.completed, reason: '$result');
      expect(result.link, isTrue);
      expect(result.linkMerged, 0);
      final db = fileDb(name);
      final benPub = nostrPublicKey(
        (await LinkDao(db).getChannel(_g))!.nostrPriv,
      );
      expect(eventsFrom(_r1, benPub), 1); // only the join's publish
    },
  );

  test('a Matrix account with a link group: Matrix phase, then the link '
      'phase on the same ledger', () async {
    final (a, annaChannel) = await anna();
    final name = await benJoinedAndClosed(annaChannel, identity: _bob);
    now += 60000;
    await putExpense(a.read(appDatabaseProvider), 'e3', at: now);
    await settle(a);

    final session = _Session(FakeMatrixNetwork().clientFor(_bob));
    final result = await round(
      dbName: name,
      ledger: BackgroundLedger.matrix,
      session: session,
    );
    expect(result.status, BackgroundRoundStatus.completed, reason: '$result');
    expect(session.fetches, greaterThanOrEqualTo(1));
    expect(session.closed, isTrue);
    expect(result.link, isTrue);
    final db = fileDb(name);
    expect(
      {for (final e in await ExpensesDao(db).getAllExpensesForGroup(_g)) e.id},
      {'e1', 'e3'},
    );
  });

  test(
    'local mode without a link group → skipped, no relay contacted',
    () async {
      final db = fileDb('empty');
      await SettingsDao(db).setBackgroundSyncEnabled(true);
      await db.close();
      final result = await round(dbName: 'empty');
      expect(result.status, BackgroundRoundStatus.skippedNothingToSync);
      expect(net.relay(_r1).connectAttempts, 0);
      expect(net.relay(_r2).connectAttempts, 0);
    },
  );

  test('connecting an account (BackgroundLedger.none) → skipped before '
      'anything is opened', () async {
    var sessionOpened = false;
    var dbOpened = false;
    final result = await runBackgroundRound(
      tryAcquire: () async => true,
      whichLedger: () async => BackgroundLedger.none,
      openSession: () async {
        sessionOpened = true;
        return null;
      },
      openDatabase: (_) {
        dbOpened = true;
        return openTestDatabase();
      },
      openLocalDatabase: () {
        dbOpened = true;
        return openTestDatabase();
      },
    );
    expect(result.status, BackgroundRoundStatus.skippedSignedOut);
    expect(sessionOpened, isFalse);
    expect(dbOpened, isFalse);
  });

  test('local mode, background sync turned off → skipped', () async {
    final (_, annaChannel) = await anna();
    final name = await benJoinedAndClosed(annaChannel);
    final db = fileDb(name);
    await SettingsDao(db).setBackgroundSyncEnabled(false);
    await db.close();
    final reqsBefore = net.relay(_r1).reqs.length;
    final result = await round(dbName: name);
    expect(result.status, BackgroundRoundStatus.skippedDisabled);
    expect(net.relay(_r1).reqs.length, reqsBefore);
  });

  test('stopped while the relays never answer the fetch: the round aborts, '
      'closes its relay connections and the DB', () async {
    final (_, annaChannel) = await anna();
    final name = await benJoinedAndClosed(annaChannel);
    for (final r in [_r1, _r2]) {
      net.relay(r).silent = true;
    }
    final reqsBefore = net.relay(_r1).reqs.length;
    final connectionsBefore = net.relay(_r1).connectionCount;
    final abort = Completer<void>();
    final running = round(dbName: name, abort: abort.future);
    // Abort as soon as the round's fetch reached the relay.
    final sw = Stopwatch()..start();
    while (net.relay(_r1).reqs.length == reqsBefore) {
      if (sw.elapsed > const Duration(seconds: 10)) fail('no fetch');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    abort.complete();
    final result = await running;
    await net.settle();
    expect(result.status, BackgroundRoundStatus.aborted);
    expect(result.link, isFalse);
    expect(net.relay(_r1).connectionCount, connectionsBefore);
    // The DB file is free again (reopens and reads).
    final db = fileDb(name);
    expect(await LinkDao(db).getChannel(_g), isNotNull);
  });

  test('chooseBackgroundLedger: local profile → local (connecting → none); '
      'Matrix only when its store exists — never creates one', () {
    BackgroundLedger pick(bool local, bool connecting, bool store) =>
        chooseBackgroundLedger(
          localProfile: local,
          connecting: connecting,
          matrixStoreExists: store,
        );
    expect(pick(true, false, false), BackgroundLedger.local);
    expect(pick(true, false, true), BackgroundLedger.local);
    expect(pick(true, true, true), BackgroundLedger.none);
    expect(pick(false, false, true), BackgroundLedger.matrix);
    // No local profile (or unreadable prefs) and no Matrix store: skipped.
    expect(pick(false, false, false), BackgroundLedger.none);
  });
}
