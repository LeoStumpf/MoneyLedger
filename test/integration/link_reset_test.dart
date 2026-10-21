/// G52 step 12 end-to-end over the fake relays (design doc §7.3, §14 Q10):
/// *Reset invite link* moves this device's copy to a new topic (the old copy
/// is unpublished, a fresh Nostr key, "me" kept); a device holding only the
/// old link no longer sees the changes; another member opening the new link
/// switches its channel (old copy unpublished, "me" kept, no picker) and
/// syncs with the resetter again.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/link/link_channel.dart';
import 'package:money_ledger/core/link/link_envelope.dart' show kLinkEventKind;
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/core/link/link_uri.dart';
import 'package:money_ledger/core/link/nostr/nip11.dart';
import 'package:money_ledger/core/link/nostr/nostr_event.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/features/link/link_join.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_relay_network.dart';
import '../helpers/in_memory_database.dart';

final _t0 = DateTime.now().millisecondsSinceEpoch;
const _g = 'G';
const _r1 = 'wss://nos.lol';
const _r2 = 'wss://nostr.mom';

class _NoInfo implements RelayInfoFetcher {
  @override
  Future<RelayInfo> fetch(String relay) async => const RelayInfo();
}

void main() {
  late FakeRelayNetwork net;
  late List<ProviderContainer> live;

  setUp(() {
    net = FakeRelayNetwork(nowSeconds: () => _t0 ~/ 1000);
    live = [];
  });

  List<Override> linkOverrides() => [
    linkRelayConnectorProvider.overrideWithValue(net),
    linkRelayInfoFetcherProvider.overrideWithValue(_NoInfo()),
    linkClockProvider.overrideWithValue(
      () => DateTime.now().millisecondsSinceEpoch,
    ),
    linkPublishDebounceProvider.overrideWithValue(
      const Duration(milliseconds: 1),
    ),
    linkPublishMinIntervalProvider.overrideWithValue(Duration.zero),
    linkAppLifecycleProvider.overrideWithValue(false),
    linkVerifySignaturesProvider.overrideWithValue(false),
    linkAppVersionProvider.overrideWith((ref) async => 'test'),
    linkJoinFetchTimeoutProvider.overrideWithValue(const Duration(seconds: 2)),
  ];

  ({ProviderContainer c, AppDatabase db}) device() {
    final db = openTestDatabase();
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerIdentityProvider.overrideWithValue(kLocalAccountId),
        localModeActiveProvider.overrideWithValue(true),
        ledgerTransportProvider.overrideWith(
          (ref) async => LocalOnlyTransport('local'),
        ),
        ...linkOverrides(),
      ],
    );
    live.add(c);
    addTearDown(() async {
      live.remove(c);
      c.dispose();
      await db.close();
    });
    c.listen(linkSyncEngineProvider, (_, _) {});
    return (c: c, db: db);
  }

  Future<void> settle() async {
    final sw = Stopwatch()..start();
    var quiet = 0;
    while (quiet < 3) {
      await net.settle();
      await Future<void>.delayed(const Duration(milliseconds: 3));
      if (live.every((c) => c.read(linkSyncEngineProvider).isIdle)) {
        quiet++;
      } else {
        quiet = 0;
      }
      if (sw.elapsed > const Duration(seconds: 20)) fail('never idle');
    }
  }

  List<NostrEvent> linkEvents(String relay, String pubkey) => [
    for (final e in net.relay(relay).events)
      if (e.kind == kLinkEventKind && e.pubkey == pubkey) e,
  ];

  /// A (Anna, local mode) shares "Trip" with Ben by link, with one expense;
  /// B joins as Ben, C joins as Carla (someone new).
  Future<
    ({
      ProviderContainer a,
      AppDatabase aDb,
      ProviderContainer b,
      AppDatabase bDb,
      ProviderContainer c,
      AppDatabase cDb,
      LinkInvite invite,
    })
  >
  sharedGroup() async {
    final a = device();
    await a.c.read(linkSyncEngineProvider).ready;
    await GroupsDao(a.db).upsertGroupLww(
      groupCompanion(
        GroupModel(
          roomId: _g,
          name: 'Trip',
          currency: 'EUR',
          updatedAt: _t0 - 5000,
          pendingSign: true,
        ),
      ),
    );
    for (final (id, name, claim) in [
      ('p1', 'Anna', kLocalAccountId),
      ('p2', 'Ben', null),
    ]) {
      await MembersDao(a.db).upsertMemberLww(
        memberCompanion(
          MemberModel(
            groupId: _g,
            userId: id,
            displayName: name,
            matrixId: claim,
            status: 'active',
            updatedAt: _t0 - 5000,
            pendingSign: true,
          ),
        ),
      );
    }
    await ExpensesDao(a.db).upsertExpenseLww(
      expenseCompanion(
        ExpenseModel(
          id: 'e1',
          roomId: _g,
          description: 'Dinner',
          amountCents: 4000,
          currency: 'EUR',
          paidBy: 'p1',
          splitsJson: '{"p1":2000,"p2":2000}',
          createdAt: _t0 - 4000,
          updatedAt: _t0 - 4000,
          pendingSign: true,
        ),
      ),
    );
    final ch = await a.c.read(linkChannelOpenerProvider)(_g);
    await settle();
    final invite = parseLinkUri(
      buildLinkUri(decodeLinkSecret(ch.secret), name: 'Trip'),
    );
    final b = device();
    await b.c.read(linkSyncEngineProvider).ready;
    await joinLinkGroup(
      b.c,
      LinkJoinRequest(
        invite: invite,
        groupId: _g,
        participantId: 'p2',
        name: 'Ben',
      ),
    );
    await settle();
    final c = device();
    await c.c.read(linkSyncEngineProvider).ready;
    await joinLinkGroup(
      c.c,
      LinkJoinRequest(
        invite: invite,
        groupId: _g,
        participantId: null,
        name: 'Carla',
      ),
    );
    await settle();
    return (
      a: a.c,
      aDb: a.db,
      b: b.c,
      bDb: b.db,
      c: c.c,
      cDb: c.db,
      invite: invite,
    );
  }

  Future<void> addExpense(AppDatabase db, String id) =>
      ExpensesDao(db).upsertExpenseLww(
        expenseCompanion(
          ExpenseModel(
            id: id,
            roomId: _g,
            description: id,
            amountCents: 1000,
            currency: 'EUR',
            paidBy: 'p1',
            splitsJson: '{"p1":500,"p2":500}',
            createdAt: DateTime.now().millisecondsSinceEpoch,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );

  Future<Set<String>> expenseIds(AppDatabase db) async => {
    for (final e in await ExpensesDao(db).getAllExpensesForGroup(_g)) e.id,
  };

  test('reset: old copy unpublished, new topic + key, "me" kept; the old '
      'link holder is cut off; a member switches with the new link and '
      'syncs again', () async {
    final s = await sharedGroup();
    expect(await expenseIds(s.cDb), {'e1'});
    final old = (await LinkDao(s.aDb).getChannel(_g))!;
    final oldPub = nostrPublicKey(old.nostrPriv);
    expect(await LinkDao(s.aDb).getPeers(_g), isNotEmpty);

    final fresh = await s.a.read(linkSyncEngineProvider).resetLink(_g);
    await settle();
    expect(fresh.secret, isNot(old.secret));
    expect(fresh.epoch, old.epoch + 1);
    expect(fresh.nostrPriv, isNot(old.nostrPriv));
    expect(fresh.myParticipantId, 'p1');
    expect((await LinkDao(s.aDb).getChannel(_g))!.secret, fresh.secret);
    final newPub = nostrPublicKey(fresh.nostrPriv);
    for (final r in [_r1, _r2]) {
      expect(linkEvents(r, oldPub), isEmpty, reason: '$r: old copy gone');
      expect(linkEvents(r, newPub), isNotEmpty, reason: '$r: new topic');
    }
    // The old link's publishers are forgotten (they come back once they
    // switched, with their new keys).
    expect(await LinkDao(s.aDb).getPeers(_g), isEmpty);

    // A's new expense never reaches C, who only has the old link.
    await addExpense(s.aDb, 'e2');
    await settle();
    await s.c.read(linkSyncEngineProvider).refresh(groupId: _g);
    await settle();
    expect(await expenseIds(s.cDb), {'e1'});
    // …and C's change on the old link doesn't reach A.
    await addExpense(s.cDb, 'c1');
    await settle();
    await s.a.read(linkSyncEngineProvider).refresh(groupId: _g);
    await settle();
    expect(await expenseIds(s.aDb), {'e1', 'e2'});

    // B opens the new link: the look-up offers the switch (other link).
    final newInvite = parseLinkUri(
      buildLinkUri(decodeLinkSecret(fresh.secret), name: 'Trip'),
    );
    final found = (await lookUpLinkGroup(s.b, newInvite))!;
    expect(found.blocker, LinkJoinError.otherLink);
    expect(found.preview.groupId, _g);
    final bOld = (await LinkDao(s.bDb).getChannel(_g))!;
    expect(await switchLinkGroup(s.b, newInvite, _g), _g);
    await settle();
    final bNew = (await LinkDao(s.bDb).getChannel(_g))!;
    expect(bNew.secret, fresh.secret);
    expect(bNew.epoch, bOld.epoch + 1);
    expect(bNew.myParticipantId, 'p2');
    expect(bNew.nostrPriv, isNot(bOld.nostrPriv));
    expect(await expenseIds(s.bDb), containsAll(['e1', 'e2']));
    // C's change from before B switched came along: B merged it while it
    // was still on the old link (the old link only stops working once
    // everyone switched — the reset dialog says so).
    expect(await expenseIds(s.bDb), contains('c1'));
    final bOldPub = nostrPublicKey(bOld.nostrPriv);
    final bNewPub = nostrPublicKey(bNew.nostrPriv);
    for (final r in [_r1, _r2]) {
      expect(linkEvents(r, bOldPub), isEmpty, reason: r);
      expect(linkEvents(r, bNewPub), isNotEmpty, reason: r);
    }

    // B and A sync on the new link; A sees B as Ben again.
    await addExpense(s.bDb, 'b1');
    await settle();
    expect(await expenseIds(s.aDb), containsAll(['e1', 'e2', 'b1']));
    final peers = await LinkDao(s.aDb).getPeers(_g);
    expect(peers.map((p) => (p.pubkey, p.me)), [(bNewPub, 'p2')]);
    // C, still on the old link, sees none of it — and its later changes
    // reach nobody who switched.
    await s.c.read(linkSyncEngineProvider).refresh(groupId: _g);
    await settle();
    expect(await expenseIds(s.cDb), {'e1', 'c1'});
    await addExpense(s.cDb, 'c2');
    await settle();
    await s.a.read(linkSyncEngineProvider).refresh(groupId: _g);
    await s.b.read(linkSyncEngineProvider).refresh(groupId: _g);
    await settle();
    expect(await expenseIds(s.aDb), isNot(contains('c2')));
    expect(await expenseIds(s.bDb), isNot(contains('c2')));

    // Opening the new link again on B: already joined, nothing changes.
    final again = (await lookUpLinkGroup(s.b, newInvite))!;
    expect(again.blocker, isNull);
    expect(again.joinedAs, 'p2');
  });

  test(
    'a reset offline still replaces the link (the old copy expires)',
    () async {
      final s = await sharedGroup();
      final old = (await LinkDao(s.aDb).getChannel(_g))!;
      for (final r in [_r1, _r2]) {
        net.relay(r)
          ..offline = true
          ..dropConnections();
      }
      final fresh = await s.a.read(linkSyncEngineProvider).resetLink(_g);
      expect(fresh.secret, isNot(old.secret));
      expect((await LinkDao(s.aDb).getChannel(_g))!.secret, fresh.secret);
    },
  );

  test('switching to the link the device already has changes nothing; '
      'no channel → refused', () async {
    final s = await sharedGroup();
    final engine = s.b.read(linkSyncEngineProvider);
    final before = (await LinkDao(s.bDb).getChannel(_g))!;
    await engine.switchLink(_g, before.secret);
    final after = (await LinkDao(s.bDb).getChannel(_g))!;
    expect(after.nostrPriv, before.nostrPriv);
    expect(after.epoch, before.epoch);
    await expectLater(
      engine.resetLink('unknown'),
      throwsA(
        isA<LinkChannelException>().having(
          (e) => e.kind,
          'kind',
          LinkChannelError.noChannel,
        ),
      ),
    );
  });
}
