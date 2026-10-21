/// G52 step 6 end-to-end over the fake relays: the two ways a link group
/// starts — (1) a **Matrix** device creates it with *Share with an invite
/// link* (channel before the first write → unsigned meta, published, no
/// MXID on the relay, nothing over Matrix), (2) a **local-mode** group's
/// first *Invite with a link* through the real seam
/// (`linkChannelOpenerProvider` → `LinkSyncEngine.openChannel`) — and a
/// joiner holding the link receives the group in both cases.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/link/link_envelope.dart';
import 'package:money_ledger/core/link/link_keys.dart';
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/core/link/link_uri.dart';
import 'package:money_ledger/core/link/nostr/nip11.dart';
import 'package:money_ledger/core/link/nostr/nostr_event.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/fake_relay_network.dart';
import '../helpers/in_memory_database.dart';

const _r1 = 'wss://nos.lol';

/// Real time: `GroupCreator` stamps with the wall clock.
final _t0 = DateTime.now().millisecondsSinceEpoch;

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

  ({ProviderContainer c, AppDatabase db}) device({
    required String identity,
    required Future<LedgerTransport> Function() transport,
  }) {
    final db = openTestDatabase();
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerIdentityProvider.overrideWithValue(identity),
        localModeActiveProvider.overrideWithValue(identity == kLocalAccountId),
        ledgerTransportProvider.overrideWith((ref) => transport()),
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

  Future<void> join(AppDatabase db, String groupId, String secret) =>
      LinkDao(db).putChannel(
        LinkChannelModel(
          groupId: groupId,
          epoch: 1,
          secret: secret,
          nostrPriv: generateNostrPrivateKey(),
          openedAt: _t0,
        ),
      );

  Future<List<String>> relayPlaintexts(String secret) async {
    final keys = await deriveLinkKeys(decodeLinkSecret(secret));
    return [
      for (final e in net.relay(_r1).events)
        if (e.kind == kLinkEventKind)
          jsonEncode(
            await openLinkContent(
              e.content,
              keys.encKey,
              d: e.dTag,
              pubkey: e.pubkey,
            ),
          ),
    ];
  }

  test('a Matrix device creates a link group: published unsigned, no MXID '
      'on the relay, nothing over Matrix; a joiner gets it', () async {
    final matrix = FakeMatrixNetwork();
    final a = device(
      identity: '@alice:x.org',
      transport: () async => matrix.clientFor('@alice:x.org'),
    );
    await a.c.read(linkSyncEngineProvider).ready;
    final sub = a.c.listen(groupCreatorProvider, (_, _) {});
    final id = await a.c
        .read(groupCreatorProvider.notifier)
        .create('Rome', 'EUR', people: ['Ben'], viaLink: true);
    sub.close();
    expect(id, isNotNull);
    await settle();

    final channel = (await LinkDao(a.db).getChannel(id!))!;
    expect(channel.lastPublishedHash, isNotNull, reason: 'published');
    final meta = (await GroupsDao(a.db).getGroup(id))!;
    expect(meta.sig, isNull);
    expect(matrix.sent, isEmpty);
    final plain = await relayPlaintexts(channel.secret);
    expect(plain, isNotEmpty);
    for (final p in plain) {
      expect(p, isNot(contains('@alice:x.org')));
    }

    final b = device(
      identity: kLocalAccountId,
      transport: () async => LocalOnlyTransport('local'),
    );
    await b.c.read(linkSyncEngineProvider).ready;
    await join(b.db, id, channel.secret);
    await settle();
    expect((await GroupsDao(b.db).getGroup(id))!.name, 'Rome');
    final people = await MembersDao(b.db).getMembers(id);
    expect(people.map((m) => m.displayName).toSet(), {'alice', 'Ben'});
    expect(people.every((m) => m.matrixId == null), isTrue);
  });

  test('local mode: the first invite opens the channel through the link '
      'sync engine; the group is published and joinable', () async {
    const g = 'G';
    final a = device(
      identity: kLocalAccountId,
      transport: () async => LocalOnlyTransport('local'),
    );
    await a.c.read(linkSyncEngineProvider).ready;
    await GroupsDao(a.db).upsertGroupLww(
      groupCompanion(
        GroupModel(
          roomId: g,
          name: 'Trip',
          currency: 'EUR',
          updatedAt: _t0 - 5000,
          pendingSign: true,
        ),
      ),
    );
    await MembersDao(a.db).upsertMemberLww(
      memberCompanion(
        MemberModel(
          groupId: g,
          userId: 'p1',
          displayName: 'Anna',
          matrixId: kLocalAccountId,
          status: 'active',
          updatedAt: _t0 - 5000,
          pendingSign: true,
        ),
      ),
    );
    final stateSub = a.c.listen(linkInviteStateProvider(g), (_, _) {});
    expect(
      await a.c.read(linkInviteStateProvider(g).future),
      LinkInviteState.canOpen,
    );
    stateSub.close();

    final ch = await a.c.read(linkChannelOpenerProvider)(g);
    expect(ch.myParticipantId, 'p1');
    await settle();
    expect((await LinkDao(a.db).getChannel(g))!.lastPublishedHash, isNotNull);
    for (final p in await relayPlaintexts(ch.secret)) {
      expect(p, isNot(contains(kLocalAccountId)));
    }
    // Opening twice returns the same channel (same link).
    expect((await a.c.read(linkChannelOpenerProvider)(g)).secret, ch.secret);

    final b = device(
      identity: kLocalAccountId,
      transport: () async => LocalOnlyTransport('local'),
    );
    await b.c.read(linkSyncEngineProvider).ready;
    await join(b.db, g, ch.secret);
    await settle();
    expect((await GroupsDao(b.db).getGroup(g))!.name, 'Trip');
  });
}
