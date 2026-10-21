/// G52 step 5: the link sync engine end-to-end over the fake relays (design
/// doc §4, §5, §13 step 5): 2–3 devices in local mode sharing a link group —
/// publish / join / merge, concurrent edits + tombstones, an offline device
/// catching up, a stale publisher, sharding up and down (NIP-11 budget),
/// relays rejecting / rate-limiting / offline, `replaced:`, refresh after
/// 10 days, junk events, NIP-09 unpublish, and a G19 teardown mid-publish.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/link/link_envelope.dart';
import 'package:money_ledger/core/link/link_keys.dart';
import 'package:money_ledger/core/link/link_relay_policy.dart';
import 'package:money_ledger/core/link/link_snapshot.dart';
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/core/link/link_uri.dart';
import 'package:money_ledger/core/link/nostr/nip11.dart';
import 'package:money_ledger/core/link/nostr/nostr_event.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/eventually.dart';
import '../helpers/fake_relay_network.dart';
import '../helpers/in_memory_database.dart';

const _r1 = 'wss://nos.lol';
const _r2 = 'wss://nostr.mom';
const _g = 'G';
const _t0 = 1792000000000;

class _Clock {
  int ms = _t0;
  int call() => ms;
}

class _Fetcher implements RelayInfoFetcher {
  RelayInfo info = const RelayInfo();
  int calls = 0;
  @override
  Future<RelayInfo> fetch(String relay) async {
    calls++;
    return info;
  }
}

class _Device {
  final ProviderContainer c;
  final AppDatabase db;
  _Device(this.c, this.db);

  LinkSyncEngine get engine => c.read(linkSyncEngineProvider);
  LinkDao get link => LinkDao(db);
  ExpensesDao get expenses => ExpensesDao(db);
  MembersDao get members => MembersDao(db);
  LinkChannelModel? channel;

  Future<Map<String, ExpenseModel>> expenseMap() async => {
    for (final e in await expenses.getAllExpensesForGroup(_g)) e.id: e,
  };
}

void main() {
  late FakeRelayNetwork net;
  late _Clock clock;
  late _Fetcher fetcher;
  late List<_Device> live;

  setUp(() {
    clock = _Clock();
    net = FakeRelayNetwork(nowSeconds: () => clock.ms ~/ 1000);
    fetcher = _Fetcher();
    live = [];
  });

  _Device device({
    Duration retry = const Duration(hours: 1),
    Duration rateLimit = const Duration(hours: 1),
    Duration pauseGrace = const Duration(seconds: 30),
  }) {
    final db = openTestDatabase();
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerIdentityProvider.overrideWithValue(kLocalAccountId),
        ledgerTransportProvider.overrideWith(
          (ref) async => LocalOnlyTransport('me'),
        ),
        linkRelayConnectorProvider.overrideWithValue(net),
        linkRelayInfoFetcherProvider.overrideWithValue(fetcher),
        linkClockProvider.overrideWithValue(clock.call),
        linkPublishDebounceProvider.overrideWithValue(
          const Duration(milliseconds: 1),
        ),
        linkPublishMinIntervalProvider.overrideWithValue(Duration.zero),
        linkRetryBackoffProvider.overrideWithValue((min: retry, max: retry)),
        linkRateLimitBackoffProvider.overrideWithValue((
          min: rateLimit,
          max: rateLimit,
        )),
        linkAppLifecycleProvider.overrideWithValue(false),
        linkPauseGraceProvider.overrideWithValue(pauseGrace),
        linkVerifySignaturesProvider.overrideWithValue(false),
        linkAppVersionProvider.overrideWith((ref) async => 'test'),
      ],
    );
    final d = _Device(c, db);
    live.add(d);
    addTearDown(() async {
      live.remove(d);
      c.dispose();
      await db.close();
    });
    c.listen(linkSyncEngineProvider, (_, _) {});
    return d;
  }

  /// Waits until the relays are quiet and every live engine is idle.
  Future<void> settle() async {
    final sw = Stopwatch()..start();
    var quiet = 0;
    while (quiet < 3) {
      await net.settle();
      await Future<void>.delayed(const Duration(milliseconds: 3));
      if (live.every((d) => d.engine.isIdle)) {
        quiet++;
      } else {
        quiet = 0;
      }
      if (sw.elapsed > const Duration(seconds: 20)) {
        fail('link engines never went idle');
      }
    }
  }

  Future<void> putExpense(
    _Device d,
    String id, {
    int amount = 1000,
    required int at,
    String by = 'p1',
    bool deleted = false,
    String description = 'Dinner',
  }) => d.expenses.upsertExpenseLww(
    expenseCompanion(
      ExpenseModel(
        id: id,
        roomId: _g,
        description: description,
        amountCents: amount,
        currency: 'EUR',
        paidBy: 'p1',
        splitsJson: jsonEncode({'p1': amount - amount ~/ 2, 'p2': amount ~/ 2}),
        createdAt: _t0 - 1000,
        updatedAt: at,
        deleted: deleted,
        linkAuthor: by,
      ),
    ),
  );

  /// Device A: a local-mode group (p1 = me via local:self, p2) + one
  /// expense, then its link channel.
  Future<_Device> creator() async {
    final a = device();
    await a.c.read(linkSyncEngineProvider).ready;
    await GroupsDao(a.db).upsertGroupLww(
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
      await a.members.upsertMemberLww(
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
    await putExpense(a, 'e1', at: _t0 - 4000);
    a.channel = await a.engine.openChannel(_g);
    return a;
  }

  /// A device that holds [secret] (as the join flow will, step 7) with
  /// "me" = [me] (null = not picked yet).
  Future<_Device> joiner(String secret, {String? me}) async {
    final d = device();
    await d.engine.ready;
    final ch = LinkChannelModel(
      groupId: _g,
      epoch: 1,
      secret: secret,
      nostrPriv: generateNostrPrivateKey(),
      openedAt: clock.ms,
      myParticipantId: me,
    );
    await d.link.putChannel(ch);
    d.channel = ch;
    return d;
  }

  List<NostrEvent> linkEvents(String relay, String pubkey) => [
    for (final e in net.relay(relay).events)
      if (e.kind == kLinkEventKind && e.pubkey == pubkey) e,
  ];

  Future<Map<String, dynamic>> decrypt(String secret, NostrEvent e) async {
    final keys = await deriveLinkKeys(decodeLinkSecret(secret));
    return openLinkContent(e.content, keys.encKey, d: e.dTag, pubkey: e.pubkey);
  }

  test('no link channel → no relay connection, no NIP-11 request', () async {
    final d = device();
    await d.engine.ready;
    await GroupsDao(d.db).upsertGroupLww(
      groupCompanion(
        const GroupModel(roomId: 'M', name: 'Matrix', currency: 'EUR'),
      ),
    );
    await settle();
    expect(net.relay(_r1).connectAttempts, 0);
    expect(net.relay(_r2).connectAttempts, 0);
    expect(fetcher.calls, 0);
  });

  test('creator publishes; a joiner merges, picks "me" and publishes; edits '
      'flow both ways with their `by` hint; no local:self leaves the '
      'device', () async {
    final a = await creator();
    await settle();
    final aPub = nostrPublicKey(a.channel!.nostrPriv);
    for (final r in [_r1, _r2]) {
      final evs = linkEvents(r, aPub);
      expect(evs, hasLength(1), reason: r);
      final e = evs.single;
      expect(
        e.dTag,
        (await deriveLinkKeys(decodeLinkSecret(a.channel!.secret))).topic,
      );
      expect(e.tag('alt'), kLinkAltText);
      expect(e.expiration, clock.ms ~/ 1000 + kLinkExpiry.inSeconds);
      final snap = await decrypt(a.channel!.secret, e);
      expect(snap['me'], 'p1');
      expect(snap['app'], 'test');
      expect(jsonEncode(snap), isNot(contains(kLocalAccountId)));
    }
    expect(fetcher.calls, 2, reason: 'NIP-11 once per relay');
    expect(a.engine.statusOf(_g)!.phase, LinkSyncPhase.synced);
    final statusSub = a.c.listen(linkGroupSyncStatusProvider(_g), (_, _) {});
    expect(
      (await a.c.read(linkGroupSyncStatusProvider(_g).future)).phase,
      LinkSyncPhase.synced,
    );
    statusSub.close();
    final aCh = (await a.link.getChannel(_g))!;
    expect(aCh.lastPublishedHash, isNotNull);
    expect(aCh.parts, 1);
    expect(
      LinkRelayState.decode(
        await SettingsDao(a.db).linkRelayStateRaw(_r1),
      ).lastOkAt,
      clock.ms,
    );

    // B holds the link but hasn't picked "me": merges, publishes nothing.
    final b = await joiner(a.channel!.secret);
    await settle();
    expect((await GroupsDao(b.db).getGroup(_g))!.name, 'Trip');
    final bMembers = {
      for (final m in await b.members.getMembers(_g)) m.userId: m,
    };
    expect(bMembers.keys, {'p1', 'p2'});
    expect(bMembers['p1']!.matrixId, isNull);
    expect(bMembers['p1']!.linkAuthor, 'p1');
    final e1 = (await b.expenseMap())['e1']!;
    expect(e1.linkAuthor, 'p1');
    expect(e1.sig, isNull);
    expect(e1.origin, isNull);
    expect(await b.link.isLinkOnly(_g), isTrue);
    final bPub = nostrPublicKey(b.channel!.nostrPriv);
    expect(linkEvents(_r1, bPub), isEmpty);
    expect(b.engine.statusOf(_g)!.problem, LinkSyncProblem.noParticipant);
    final peersOfB = await b.link.getPeers(_g);
    expect(peersOfB.single.pubkey, aPub);
    expect(peersOfB.single.me, 'p1');
    expect(peersOfB.single.snapshotDigest, aCh.lastPublishedHash);

    // B is Ben → publishes; B edits e1 → A merges it (by = p2).
    await b.link.setMyParticipant(_g, 'p2');
    await settle();
    expect(linkEvents(_r1, bPub), hasLength(1));
    await putExpense(b, 'e1', amount: 2000, at: _t0, by: 'p2');
    await settle();
    final onA = (await a.expenseMap())['e1']!;
    expect(onA.amountCents, 2000);
    expect(onA.linkAuthor, 'p2');
    // A republished the merged state: both snapshots now agree.
    final aAfter = (await a.link.getChannel(_g))!;
    final bAfter = (await b.link.getChannel(_g))!;
    expect(aAfter.lastPublishedHash, bAfter.lastPublishedHash);
    expect(
      (await a.link.getPeers(_g)).single.snapshotDigest,
      aAfter.lastPublishedHash,
    );
    expect(b.engine.statusOf(_g)!.phase, LinkSyncPhase.synced);
  });

  test(
    'concurrent edits converge by LWW / G27; tombstones win when newer',
    () async {
      final a = await creator();
      await putExpense(a, 'e2', at: _t0 - 3000, description: 'Taxi');
      await settle();
      final b = await joiner(a.channel!.secret, me: 'p2');
      await settle();
      expect((await b.expenseMap()).keys, {'e1', 'e2'});

      // Both edit e1 at once (B's clock wins); B deletes e2; A adds e3.
      await putExpense(a, 'e1', amount: 1100, at: _t0 + 10);
      await putExpense(b, 'e1', amount: 1200, at: _t0 + 20, by: 'p2');
      await putExpense(b, 'e2', at: _t0 + 30, by: 'p2', deleted: true);
      await putExpense(a, 'e3', at: _t0 + 40, description: 'Museum');
      // Same clock on both sides: the higher G27 hash wins everywhere.
      await putExpense(a, 'e3', amount: 3000, at: _t0 + 50);
      await putExpense(b, 'e3', amount: 4000, at: _t0 + 50, by: 'p2');
      await settle();

      final onA = await a.expenseMap();
      final onB = await b.expenseMap();
      expect(onA.keys, {'e1', 'e2', 'e3'});
      for (final id in onA.keys) {
        expect(onA[id]!.updatedAt, onB[id]!.updatedAt, reason: id);
        expect(onA[id]!.amountCents, onB[id]!.amountCents, reason: id);
        expect(onA[id]!.deleted, onB[id]!.deleted, reason: id);
      }
      expect(onA['e1']!.amountCents, 1200);
      expect(onA['e2']!.deleted, isTrue);
      expect([3000, 4000], contains(onA['e3']!.amountCents));
      expect(
        (await a.link.getChannel(_g))!.lastPublishedHash,
        (await b.link.getChannel(_g))!.lastPublishedHash,
      );
    },
  );

  test('an offline device catches up from the relays; a stale publisher '
      'can\'t revert newer versions', () async {
    final a = await creator();
    await settle();
    final b = await joiner(a.channel!.secret, me: 'p2');
    await settle();
    // B goes away for good — its event (e1 v1) stays on the relays.
    final bPub = nostrPublicKey(b.channel!.nostrPriv);
    b.c.dispose();
    live.remove(b);
    await putExpense(a, 'e1', amount: 5000, at: _t0 + 100);
    await putExpense(a, 'e9', at: _t0 + 110, description: 'Later');
    await settle();
    expect(linkEvents(_r1, bPub), hasLength(1));

    // C opens the link later: gets A's newest state, B's old copy loses.
    final c = await joiner(a.channel!.secret, me: 'p2');
    await settle();
    final onC = await c.expenseMap();
    expect(onC['e1']!.amountCents, 5000);
    expect(onC.keys, containsAll(['e1', 'e9']));
    expect(
      {for (final p in await c.link.getPeers(_g)) p.pubkey},
      {nostrPublicKey(a.channel!.nostrPriv), bPub},
    );
    // A full fetch (pull to refresh) finds nothing new to merge.
    final r = await c.engine.refresh(groupId: _g);
    expect(r.complete, isTrue);
    expect(r.events, 3);
    expect(r.merged, 0);
  });

  test('sharding: grows past the NIP-11 budget, shrinks with retired '
      'header-only parts', () async {
    fetcher.info = const RelayInfo(maxContentLength: 1200);
    final a = await creator();
    await settle();
    await a.engine.refreshRelayInfo(force: true);
    for (var i = 0; i < 30; i++) {
      await putExpense(
        a,
        'x$i',
        at: _t0 - 3000 + i,
        // Random hex: compresses badly, so the snapshot really grows.
        description: generateNostrPrivateKey().substring(0, 40),
      );
    }
    await settle();
    final aPub = nostrPublicKey(a.channel!.nostrPriv);
    final parts = (await a.link.getChannel(_g))!.parts;
    expect(parts, greaterThan(1));
    expect(linkEvents(_r1, aPub), hasLength(parts));
    for (final e in linkEvents(_r1, aPub)) {
      expect(e.content.length, lessThanOrEqualTo(1200));
    }

    final b = await joiner(a.channel!.secret, me: 'p2');
    await settle();
    expect((await b.expenseMap()).length, 31);

    // A bigger budget: the next change publishes one part and retires the
    // rest (header-only, expiring after a day).
    fetcher.info = const RelayInfo();
    await a.engine.refreshRelayInfo(force: true);
    await putExpense(a, 'last', at: _t0 + 1);
    await settle();
    expect((await a.link.getChannel(_g))!.parts, 1);
    final topic = (await deriveLinkKeys(
      decodeLinkSecret(a.channel!.secret),
    )).topic;
    for (final e in linkEvents(_r1, aPub)) {
      final snap = await decrypt(a.channel!.secret, e);
      final header = parseLinkSnapshotHeader(snap);
      if (e.dTag == topic) {
        expect(header.parts, 1);
        expect((snap['expenses'] as List), hasLength(32));
        expect(e.expiration, clock.ms ~/ 1000 + kLinkExpiry.inSeconds);
      } else {
        expect(header.retired, isTrue);
        expect(snap['expenses'], isEmpty);
        expect((snap['members'] as List), hasLength(2));
        expect(e.expiration, clock.ms ~/ 1000 + kLinkRetiredExpiry.inSeconds);
      }
    }
    expect((await b.expenseMap()).length, 32);
  });

  test('one relay blocks us, the other rate-limits: back-off, retry, '
      'recovery; the blocked relay is skipped until restart', () async {
    net.relay(_r1).rejectWith = 'blocked: not welcome';
    final a = device(
      retry: const Duration(milliseconds: 30),
      rateLimit: const Duration(milliseconds: 60),
    );
    await a.engine.ready;
    await GroupsDao(a.db).upsertGroupLww(
      groupCompanion(
        const GroupModel(roomId: _g, name: 'Trip', currency: 'EUR'),
      ),
    );
    await a.members.upsertMemberLww(
      memberCompanion(
        const MemberModel(
          groupId: _g,
          userId: 'p1',
          matrixId: kLocalAccountId,
          status: 'active',
          updatedAt: 1,
        ),
      ),
    );
    final ch = await a.engine.openChannel(_g);
    await settle();
    final aPub = nostrPublicKey(ch.nostrPriv);
    // Delivered via r2 alone.
    expect(a.engine.statusOf(_g)!.phase, LinkSyncPhase.synced);
    expect(linkEvents(_r2, aPub), hasLength(1));
    expect(a.engine.relayPolicy.rejects(_r1), isTrue);
    final r1State = LinkRelayState.decode(
      await SettingsDao(a.db).linkRelayStateRaw(_r1),
    );
    expect(r1State.lastRejection, RelayAnswer.rejects.name);
    expect(r1State.lastRejectionMessage, 'blocked: not welcome');
    final r1Frames = net.relay(_r1).eventFrames.length;

    // r2 rate-limits now: nothing delivered → retried after the back-off.
    net.relay(_r2).rejectWith = 'rate-limited: slow down';
    await putExpense(a, 'e1', at: _t0);
    await settle();
    expect(a.engine.statusOf(_g)!.phase, isNot(LinkSyncPhase.synced));
    expect(a.engine.relayPolicy.rateLimitedUntil(_r2), isNotNull);
    net.relay(_r2).rejectWith = null;
    // The back-off runs on the engine clock.
    clock.ms += const Duration(minutes: 5).inMilliseconds;
    await eventually(
      () => a.engine.statusOf(_g)!.phase == LinkSyncPhase.synced,
    );
    await settle();
    expect(net.relay(_r1).eventFrames, hasLength(r1Frames));
    expect(
      (await decrypt(ch.secret, linkEvents(_r2, aPub).single))['expenses'],
      hasLength(1),
    );
  });

  test(
    'every relay rejects us → failing (relaysReject), no retry loop',
    () async {
      net.relay(_r1).rejectWith = 'blocked: no';
      net.relay(_r2).rejectWith = 'restricted: members only';
      final a = await creator();
      await settle();
      final s = a.engine.statusOf(_g)!;
      expect(s.phase, LinkSyncPhase.failing);
      expect(s.problem, LinkSyncProblem.relaysReject);
      final frames = net.relay(_r1).eventFrames.length;
      await putExpense(a, 'e2', at: _t0);
      await settle();
      expect(net.relay(_r1).eventFrames, hasLength(frames));
    },
  );

  test(
    'relays offline: failing after two attempts, synced once back',
    () async {
      net.relay(_r1).offline = true;
      net.relay(_r2).offline = true;
      final a = device(retry: const Duration(milliseconds: 20));
      await a.engine.ready;
      await GroupsDao(a.db).upsertGroupLww(
        groupCompanion(
          const GroupModel(roomId: _g, name: 'Trip', currency: 'EUR'),
        ),
      );
      await a.members.upsertMemberLww(
        memberCompanion(
          const MemberModel(
            groupId: _g,
            userId: 'p1',
            matrixId: kLocalAccountId,
            status: 'active',
            updatedAt: 1,
          ),
        ),
      );
      await a.engine.openChannel(_g);
      await eventually(
        () => a.engine.statusOf(_g)?.phase == LinkSyncPhase.failing,
      );
      final s = a.engine.statusOf(_g)!;
      expect(s.problem, LinkSyncProblem.notDelivered);
      expect(s.consecutiveFailures, greaterThanOrEqualTo(2));
      expect((await a.link.getChannel(_g))!.lastPublishedHash, isNull);
      net.relay(_r1).offline = false;
      net.relay(_r2).offline = false;
      await eventually(
        () => a.engine.statusOf(_g)?.phase == LinkSyncPhase.synced,
      );
      expect((await a.link.getChannel(_g))!.lastPublishedHash, isNotNull);
    },
  );

  test('`replaced:` → created_at moves past the relay\'s newer event of '
      'ours and the event is republished once', () async {
    final a = device();
    await a.engine.ready;
    await GroupsDao(a.db).upsertGroupLww(
      groupCompanion(
        const GroupModel(roomId: _g, name: 'Trip', currency: 'EUR'),
      ),
    );
    await a.members.upsertMemberLww(
      memberCompanion(
        const MemberModel(
          groupId: _g,
          userId: 'p1',
          status: 'active',
          updatedAt: 1,
        ),
      ),
    );
    // A channel whose key already has a newer event on both relays (e.g.
    // a clock that ran ahead before).
    final priv = generateNostrPrivateKey();
    final secret = encodeLinkSecret(generateLinkSecret());
    final topic = (await deriveLinkKeys(decodeLinkSecret(secret))).topic;
    final future = clock.ms ~/ 1000 + 500;
    final stale = signNostrEvent(
      privateKey: priv,
      kind: kLinkEventKind,
      tags: [
        ['d', topic],
      ],
      content: '1:AAAA',
      createdAt: future,
    );
    net.relay(_r1).store(stale);
    net.relay(_r2).store(stale);
    await a.link.putChannel(
      LinkChannelModel(
        groupId: _g,
        epoch: 1,
        secret: secret,
        nostrPriv: priv,
        openedAt: clock.ms,
        myParticipantId: 'p1',
      ),
    );
    await settle();
    for (final r in [_r1, _r2]) {
      final held = linkEvents(r, nostrPublicKey(priv)).single;
      expect(held.createdAt, greaterThan(future), reason: r);
      expect((await decrypt(secret, held))['me'], 'p1');
    }
    expect((await a.link.getChannel(_g))!.lastCreatedAt, greaterThan(future));
    expect(a.engine.statusOf(_g)!.phase, LinkSyncPhase.synced);
  });

  test('monotonic created_at; an unchanged snapshot is republished only '
      'after 10 days (expiration moves)', () async {
    final a = await creator();
    await settle();
    final aPub = nostrPublicKey(a.channel!.nostrPriv);
    final first = linkEvents(_r1, aPub).single;
    final frames = net.relay(_r1).eventFrames.length;

    await a.engine.publishAll();
    await settle();
    expect(net.relay(_r1).eventFrames, hasLength(frames));

    clock.ms += const Duration(days: 9).inMilliseconds;
    await a.engine.publishAll();
    await settle();
    expect(net.relay(_r1).eventFrames, hasLength(frames));

    clock.ms += const Duration(days: 2).inMilliseconds;
    await a.engine.publishAll();
    await settle();
    final second = linkEvents(_r1, aPub).single;
    expect(second.id, isNot(first.id));
    expect(second.createdAt, greaterThan(first.createdAt));
    expect(second.expiration, clock.ms ~/ 1000 + kLinkExpiry.inSeconds);
    expect(
      (await decrypt(a.channel!.secret, second))['expenses'],
      (await decrypt(a.channel!.secret, first))['expenses'],
    );
  });

  test('events that don\'t decrypt, name another group or another part '
      'are ignored and never recorded', () async {
    final a = await creator();
    await settle();
    final b = await joiner(a.channel!.secret, me: 'p2');
    await settle();
    final keys = await deriveLinkKeys(decodeLinkSecret(a.channel!.secret));
    final mallory = generateNostrPrivateKey();
    final mPub = nostrPublicKey(mallory);
    Future<NostrEvent> sealed(Map<String, dynamic> snap, String d) async =>
        signNostrEvent(
          privateKey: mallory,
          kind: kLinkEventKind,
          tags: [
            ['d', d],
          ],
          content: await sealLinkContent(
            packLinkSnapshot(snap),
            keys.encKey,
            d: d,
            pubkey: mPub,
          ),
          createdAt: clock.ms ~/ 1000,
        );
    final evil = {
      'format': kLinkSnapshotFormat,
      'v': 1,
      'group': 'OTHER',
      'me': 'x',
      'part': 0,
      'parts': 1,
      'meta': {'group': 'OTHER', 'name': 'x', 'currency': 'EUR'},
      'members': const [],
      'expenses': const [],
      'settlements': const [],
    };
    net
        .relay(_r1)
        .store(
          signNostrEvent(
            privateKey: mallory,
            kind: kLinkEventKind,
            tags: [
              ['d', linkPartTopic(keys.topic, 2)],
            ],
            content: '1:${base64.encode(List.filled(64, 7))}',
            createdAt: clock.ms ~/ 1000,
          ),
        );
    net.relay(_r1).store(await sealed(evil, linkPartTopic(keys.topic, 3)));
    net
        .relay(_r1)
        .store(
          await sealed({
            ...evil,
            'group': _g,
            'part': 1,
            'parts': 2,
          }, linkPartTopic(keys.topic, 4)),
        );
    await settle();
    for (final d in [a, b]) {
      expect(
        (await d.link.getPeers(_g)).map((p) => p.pubkey),
        isNot(contains(mPub)),
      );
      expect(await GroupsDao(d.db).getGroup('OTHER'), isNull);
    }
  });

  test('unpublish: header-only parts, then a NIP-09 deletion removes them '
      '(other publishers stay)', () async {
    final a = await creator();
    await settle();
    final b = await joiner(a.channel!.secret, me: 'p2');
    await settle();
    final aPub = nostrPublicKey(a.channel!.nostrPriv);
    final bPub = nostrPublicKey(b.channel!.nostrPriv);
    expect(await a.engine.unpublish(_g), isTrue);
    await settle();
    for (final r in [_r1, _r2]) {
      expect(linkEvents(r, aPub), isEmpty, reason: r);
      expect(linkEvents(r, bPub), hasLength(1), reason: r);
      expect(net.relay(r).deleted, isNotEmpty);
      expect(
        net.relay(r).events.where((e) => e.kind == 5 && e.pubkey == aPub),
        hasLength(1),
      );
    }
    // B keeps everything it merged.
    expect((await b.expenseMap()).keys, {'e1'});
  });

  test('G19: tearing the engine down mid-publish neither throws nor '
      'touches the closed DB', () async {
    net.relay(_r1).silent = true;
    net.relay(_r2).silent = true;
    final a = await creator();
    await eventually(() => net.relay(_r1).eventFrames.isNotEmpty);
    // Account switch: the provider is disposed and the old DB closed while
    // the publish waits for its OK.
    a.c.dispose();
    live.remove(a);
    await a.db.close();
    await net.settle();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(a.db.isClosed, isTrue);
  });

  test('pause closes the live subscription after the grace period; resume '
      'reopens it and catches up', () async {
    final a = await creator();
    await settle();
    final b = device(pauseGrace: const Duration(milliseconds: 10));
    await b.engine.ready;
    await b.link.putChannel(
      LinkChannelModel(
        groupId: _g,
        epoch: 1,
        secret: a.channel!.secret,
        nostrPriv: generateNostrPrivateKey(),
        openedAt: clock.ms,
        myParticipantId: 'p2',
      ),
    );
    await settle();
    expect(net.relay(_r1).openSubscriptions, hasLength(2));

    b.engine.onAppPaused();
    await eventually(() => net.relay(_r1).openSubscriptions.length == 1);
    await putExpense(a, 'e5', at: _t0 + 5);
    await settle();
    expect((await b.expenseMap()).keys, {'e1'});

    final reqs = net.relay(_r1).reqs.length;
    b.engine.onAppResumed();
    await settle();
    expect((await b.expenseMap()).keys, {'e1', 'e5'});
    final req = net.relay(_r1).reqs.sublist(reqs).single;
    expect((req[2] as Map)['since'], isA<int>());
  });

  test('releaseIdleConnections (step 8 review): a fetch + publish in a '
      'paused app reopens the relays; afterwards they are closed again — '
      'never in the foreground', () async {
    final a = await creator();
    await settle();
    final b = device(pauseGrace: const Duration(milliseconds: 10));
    await b.engine.ready;
    await b.link.putChannel(
      LinkChannelModel(
        groupId: _g,
        epoch: 1,
        secret: a.channel!.secret,
        nostrPriv: generateNostrPrivateKey(),
        openedAt: clock.ms,
        myParticipantId: 'p2',
      ),
    );
    await settle();
    final withB = net.relay(_r1).connectionCount;

    // Foreground: nothing is closed.
    await b.engine.releaseIdleConnections();
    await settle();
    expect(net.relay(_r1).connectionCount, withB);

    b.engine.onAppPaused();
    await eventually(() => net.relay(_r1).connectionCount == withB - 1);

    // A delegated background round: full fetch + publish.
    await b.engine.refresh();
    await b.engine.publishAll();
    await settle();
    expect(net.relay(_r1).connectionCount, withB);

    await b.engine.releaseIdleConnections();
    await eventually(() => net.relay(_r1).connectionCount == withB - 1);

    // Resume still reopens the live subscription.
    b.engine.onAppResumed();
    await settle();
    expect(net.relay(_r1).connectionCount, withB);
  });
}
