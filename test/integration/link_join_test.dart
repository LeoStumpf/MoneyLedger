/// G52 step 7 end-to-end over the fake relays: the join's look-up (no DB,
/// nothing stored), joining as an existing person / as someone new (channel
/// stored before the merge, "me" set, published, the inviter sees the
/// joiner), the refusals (group held as a non-link group / with another
/// link), "already joined", nothing found, and a **fresh install** opened
/// from a link (no account, no local profile → local mode named like the
/// picked person).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/link/link_channel.dart';
import 'package:money_ledger/core/link/link_keys.dart';
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/core/link/link_uri.dart';
import 'package:money_ledger/core/link/nostr/nip11.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/device_prefs.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/features/link/link_join.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_relay_network.dart';
import '../helpers/in_memory_database.dart';

final _t0 = DateTime.now().millisecondsSinceEpoch;
const _g = 'G';

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

  /// A local-mode device with its own in-memory ledger.
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
      if (live.every(
        (c) =>
            c.read(ledgerIdentityProvider) == null ||
            c.read(linkSyncEngineProvider).isIdle,
      )) {
        quiet++;
      } else {
        quiet = 0;
      }
      if (sw.elapsed > const Duration(seconds: 20)) fail('never idle');
    }
  }

  /// Device A: local mode, group "Trip" with Anna (me) + Ben, shared by
  /// link. Returns A and the invite.
  Future<({ProviderContainer c, AppDatabase db, LinkInvite invite})>
  inviter() async {
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
    final ch = await a.c.read(linkChannelOpenerProvider)(_g);
    await settle();
    final invite = parseLinkUri(
      buildLinkUri(decodeLinkSecret(ch.secret), name: 'Trip'),
    );
    return (c: a.c, db: a.db, invite: invite);
  }

  test('look-up: name, people with "used on another phone", nothing '
      'stored or published by the joiner', () async {
    final a = await inviter();
    final b = device();
    await b.c.read(linkSyncEngineProvider).ready;
    final events = net.relay('wss://nos.lol').events.length;

    final found = await lookUpLinkGroup(b.c, a.invite);
    expect(found, isNotNull);
    expect(found!.preview.groupId, _g);
    expect(found.preview.name, 'Trip');
    expect(found.blocker, isNull);
    expect(found.joinedAs, isNull);
    expect(
      [for (final p in found.preview.people) (p.name, p.usedElsewhere)],
      [('Anna', true), ('Ben', false)],
    );

    await settle();
    expect(await LinkDao(b.db).getChannel(_g), isNull);
    expect(await GroupsDao(b.db).getGroup(_g), isNull);
    expect(net.relay('wss://nos.lol').events.length, events);
  });

  test('join as an existing person: channel first, merged, "me" set, '
      'published; the inviter sees who joined', () async {
    final a = await inviter();
    final b = device();
    await b.c.read(linkSyncEngineProvider).ready;
    final found = (await lookUpLinkGroup(b.c, a.invite))!;

    final id = await joinLinkGroup(
      b.c,
      LinkJoinRequest(
        invite: a.invite,
        groupId: found.preview.groupId,
        participantId: 'p2',
        name: 'Ben',
      ),
    );
    expect(id, _g);
    final ch = (await LinkDao(b.db).getChannel(_g))!;
    expect(ch.myParticipantId, 'p2');
    expect(ch.secret, encodeLinkSecret(a.invite.secret));
    expect((await GroupsDao(b.db).getGroup(_g))!.name, 'Trip');
    expect((await LinkDao(b.db).policyOf(_g)).policy.name, 'linkOnly');
    final meSub = b.c.listen(currentParticipantProvider(_g), (_, _) {});
    expect(
      (await b.c.read(currentParticipantProvider(_g).future))?.userId,
      'p2',
    );
    meSub.close();

    await settle();
    expect((await LinkDao(b.db).getChannel(_g))!.lastPublishedHash, isNotNull);
    final peers = await LinkDao(a.db).getPeers(_g);
    expect(peers.map((p) => p.me), contains('p2'));
    // The same link again: already joined.
    final again = (await lookUpLinkGroup(b.c, a.invite))!;
    expect(again.joinedAs, 'p2');
  });

  test('join as someone new: a new unsigned participant by itself, seen by '
      'the inviter', () async {
    final a = await inviter();
    final b = device();
    await b.c.read(linkSyncEngineProvider).ready;
    await joinLinkGroup(
      b.c,
      LinkJoinRequest(
        invite: a.invite,
        groupId: _g,
        participantId: null,
        name: ' Cleo ',
      ),
    );
    final me = (await LinkDao(b.db).getChannel(_g))!.myParticipantId!;
    final cleo = (await MembersDao(
      b.db,
    ).getMembers(_g)).where((m) => m.userId == me).single;
    expect(cleo.displayName, 'Cleo');
    expect(cleo.matrixId, isNull);
    expect(cleo.sig, isNull);
    expect(cleo.pendingSign, isFalse);
    expect(cleo.linkAuthor, me);

    await settle();
    final atA = await MembersDao(a.db).getMembers(_g);
    expect(atA.map((m) => m.displayName), contains('Cleo'));
  });

  test('refused: the group is held here as a non-link group', () async {
    final a = await inviter();
    final b = device();
    await b.c.read(linkSyncEngineProvider).ready;
    await GroupsDao(b.db).upsertGroupLww(
      groupCompanion(
        GroupModel(
          roomId: _g,
          name: 'Mine',
          currency: 'EUR',
          updatedAt: _t0,
          pendingSign: true,
        ),
      ),
    );
    final found = (await lookUpLinkGroup(b.c, a.invite))!;
    expect(found.blocker, LinkJoinError.notALinkGroup);
    await expectLater(
      joinLinkGroup(
        b.c,
        LinkJoinRequest(
          invite: a.invite,
          groupId: _g,
          participantId: 'p2',
          name: 'Ben',
        ),
      ),
      throwsA(
        isA<LinkJoinException>().having(
          (e) => e.kind,
          'kind',
          LinkJoinError.notALinkGroup,
        ),
      ),
    );
    expect(await LinkDao(b.db).getChannel(_g), isNull);
    expect((await GroupsDao(b.db).getGroup(_g))!.name, 'Mine');
  });

  test('refused: the group is shared here with another link', () async {
    final a = await inviter();
    final b = device();
    await b.c.read(linkSyncEngineProvider).ready;
    final other = newLinkChannel(_g, myParticipantId: null, openedAt: _t0);
    await LinkDao(b.db).putChannel(other);
    expect(
      (await lookUpLinkGroup(b.c, a.invite))!.blocker,
      LinkJoinError.otherLink,
    );
    await expectLater(
      joinLinkChannel(b.db, _g, secret: encodeLinkSecret(a.invite.secret)),
      throwsA(isA<LinkJoinException>()),
    );
    expect((await LinkDao(b.db).getChannel(_g))!.secret, other.secret);
  });

  test('nothing on the relays → no preview', () async {
    final b = device();
    await b.c.read(linkSyncEngineProvider).ready;
    final invite = parseLinkUri(buildLinkUri(generateLinkSecret()));
    expect(await lookUpLinkGroup(b.c, invite), isNull);
  });

  test('fresh install (no account, no local profile): the join starts '
      'local mode named like the picked person', () async {
    final a = await inviter();
    final store = InMemoryDevicePrefsStore({});
    final dbs = <AppDatabase>[];
    final c = ProviderContainer(
      overrides: [
        devicePrefsStoreProvider.overrideWithValue(store),
        matrixStoreExistsProvider.overrideWith((ref) async => false),
        localDatabaseOpenerProvider.overrideWithValue(() {
          final db = openTestDatabase();
          dbs.add(db);
          return db;
        }),
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
      for (final db in dbs) {
        await db.close();
      }
    });
    c.listen(appSessionProvider, (_, _) {});
    await c.read(devicePrefsProvider.future);
    c.listen(matrixStoreExistsProvider, (_, _) {});
    await c.read(matrixStoreExistsProvider.future);
    expect(c.read(appSessionProvider), AppSessionKind.signedOut);

    final found = (await lookUpLinkGroup(c, a.invite))!;
    expect(found.preview.groupId, _g);
    expect(dbs, isEmpty, reason: 'the look-up needs no ledger');

    await joinLinkGroup(
      c,
      LinkJoinRequest(
        invite: a.invite,
        groupId: _g,
        participantId: 'p2',
        name: 'Ben',
      ),
    );
    expect(c.read(appSessionProvider), AppSessionKind.local);
    final prefs = c.read(devicePrefsProvider).value!;
    expect(prefs.localProfile?.name, 'Ben');
    expect(prefs.welcomeSeen, isTrue);
    final db = c.read(appDatabaseProvider);
    expect((await LinkDao(db).getChannel(_g))!.myParticipantId, 'p2');
    expect((await GroupsDao(db).getGroup(_g))!.name, 'Trip');
  });
}
