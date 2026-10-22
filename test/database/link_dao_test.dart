/// G52 step 3: `LinkDao` — the device-local link channel per group and the
/// publishers seen on it — plus `purgeGroup` / `wipeAll` dropping them.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/models/link_model.dart';

import '../helpers/in_memory_database.dart';

const _secret = 'c2VjcmV0LXNlY3JldC1zZWNyZXQtc2VjcmV0LXNlY3I';
const _priv =
    '0000000000000000000000000000000000000000000000000000000000000003';

LinkChannelModel _channel(String groupId, {String? me, int epoch = 1}) =>
    LinkChannelModel(
      groupId: groupId,
      epoch: epoch,
      secret: _secret,
      nostrPriv: _priv,
      myParticipantId: me,
      openedAt: 1000,
    );

void main() {
  late AppDatabase db;
  late LinkDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = LinkDao(db);
  });
  tearDown(() => db.close());

  group('channels', () {
    test('put / get round-trips every field', () async {
      expect(await dao.getChannel('g1'), isNull);
      await dao.putChannel(
        const LinkChannelModel(
          groupId: 'g1',
          epoch: 2,
          secret: _secret,
          nostrPriv: _priv,
          myParticipantId: 'p1',
          lastPublishedHash: 'h',
          lastPublishedAt: 50,
          lastCreatedAt: 7,
          parts: 4,
          openedAt: 1000,
        ),
      );
      final c = (await dao.getChannel('g1'))!;
      expect(c.groupId, 'g1');
      expect(c.epoch, 2);
      expect(c.secret, _secret);
      expect(c.nostrPriv, _priv);
      expect(c.myParticipantId, 'p1');
      expect(c.lastPublishedHash, 'h');
      expect(c.lastPublishedAt, 50);
      expect(c.lastCreatedAt, 7);
      expect(c.parts, 4);
      expect(c.openedAt, 1000);
    });

    test('defaults for a new channel', () async {
      await dao.putChannel(_channel('g1'));
      final c = (await dao.getChannel('g1'))!;
      expect(c.myParticipantId, isNull);
      expect(c.lastPublishedHash, isNull);
      expect(c.lastPublishedAt, 0);
      expect(c.lastCreatedAt, 0);
      expect(c.parts, 1);
    });

    test('toString never contains the secrets', () {
      final text = _channel('g1', me: 'p1').toString();
      expect(text, isNot(contains(_secret)));
      expect(text, isNot(contains(_priv)));
      expect(text, contains('g1'));
    });

    test('put replaces the channel (new epoch) and keeps its peers', () async {
      await dao.putChannel(_channel('g1', me: 'p1'));
      await dao.recordPeerEvent(
        groupId: 'g1',
        pubkey: 'aa',
        part: 0,
        eventId: 'e1',
        createdAt: 10,
        seenAt: 100,
      );
      await dao.putChannel(_channel('g1', epoch: 2));
      final c = (await dao.getChannel('g1'))!;
      expect(c.epoch, 2);
      expect(c.myParticipantId, isNull);
      expect(await dao.getPeers('g1'), hasLength(1));
    });

    test('all channels, sorted by group; watch follows changes', () async {
      final seen = <List<String>>[];
      final sub = dao.watchAllChannels().listen(
        (cs) => seen.add([for (final c in cs) c.groupId]),
      );
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await dao.putChannel(_channel('g2'));
      await dao.putChannel(_channel('g1'));
      expect(
        [for (final c in await dao.getAllChannels()) c.groupId],
        ['g1', 'g2'],
      );
      await pumpEventQueue();
      expect(seen.last, ['g1', 'g2']);
      expect(seen.first, isEmpty);
    });

    test('watchChannel emits null, the channel, its updates', () async {
      final seen = <String?>[];
      final sub = dao
          .watchChannel('g1')
          .listen((c) => seen.add(c?.myParticipantId ?? '-'));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await dao.putChannel(_channel('g1'));
      await pumpEventQueue();
      await dao.setMyParticipant('g1', 'p7');
      await pumpEventQueue();
      expect(seen.first, '-');
      expect(seen.last, 'p7');
    });

    test('setMyParticipant sets and clears; no-op without channel', () async {
      await dao.setMyParticipant('nope', 'p1');
      expect(await dao.getChannel('nope'), isNull);
      await dao.putChannel(_channel('g1'));
      await dao.setMyParticipant('g1', 'p1');
      expect((await dao.getChannel('g1'))!.myParticipantId, 'p1');
      await dao.setMyParticipant('g1', null);
      expect((await dao.getChannel('g1'))!.myParticipantId, isNull);
    });

    test('nextCreatedAt is strictly increasing and stored', () async {
      expect(await dao.nextCreatedAt('g1', 100), isNull); // no channel
      await dao.putChannel(_channel('g1'));
      expect(await dao.nextCreatedAt('g1', 100), 100);
      expect(await dao.nextCreatedAt('g1', 100), 101); // same second
      expect(await dao.nextCreatedAt('g1', 90), 102); // clock went back
      expect(await dao.nextCreatedAt('g1', 200), 200);
      expect((await dao.getChannel('g1'))!.lastCreatedAt, 200);
    });

    test('bumpCreatedAt only moves forward', () async {
      await dao.putChannel(_channel('g1'));
      await dao.bumpCreatedAt('g1', 50);
      await dao.bumpCreatedAt('g1', 40);
      expect((await dao.getChannel('g1'))!.lastCreatedAt, 50);
      expect(await dao.nextCreatedAt('g1', 10), 51);
      await dao.bumpCreatedAt('nope', 5); // no channel: no-op
    });

    test('recordPublished stores hash, time and parts', () async {
      await dao.putChannel(_channel('g1'));
      await dao.recordPublished('g1', hash: 'abc', at: 123, parts: 2);
      final c = (await dao.getChannel('g1'))!;
      expect(c.lastPublishedHash, 'abc');
      expect(c.lastPublishedAt, 123);
      expect(c.parts, 2);
    });

    test('deleteChannel drops the channel and its peers only', () async {
      await dao.putChannel(_channel('g1'));
      await dao.putChannel(_channel('g2'));
      for (final g in ['g1', 'g2']) {
        await dao.recordPeerEvent(
          groupId: g,
          pubkey: 'aa',
          part: 0,
          eventId: 'e',
          createdAt: 1,
          seenAt: 1,
        );
      }
      await dao.deleteChannel('g1');
      expect(await dao.getChannel('g1'), isNull);
      expect(await dao.getPeers('g1'), isEmpty);
      expect(await dao.getChannel('g2'), isNotNull);
      expect(await dao.getPeers('g2'), hasLength(1));
    });
  });

  group('peers', () {
    test('recordPeerEvent creates a peer; isProcessed per part', () async {
      await dao.recordPeerEvent(
        groupId: 'g1',
        pubkey: 'aa',
        part: 0,
        eventId: 'e0',
        createdAt: 10,
        seenAt: 1000,
        me: 'p1',
        snapshotDigest: 'd1',
      );
      await dao.recordPeerEvent(
        groupId: 'g1',
        pubkey: 'aa',
        part: 1,
        eventId: 'e1',
        createdAt: 10,
        seenAt: 1001,
        me: 'p1',
        snapshotDigest: 'd1',
      );
      expect(await dao.isProcessed('g1', 'aa', 0, 'e0'), isTrue);
      expect(await dao.isProcessed('g1', 'aa', 1, 'e1'), isTrue);
      expect(await dao.isProcessed('g1', 'aa', 1, 'e0'), isFalse);
      expect(await dao.isProcessed('g1', 'aa', 2, 'e2'), isFalse);
      expect(await dao.isProcessed('g1', 'bb', 0, 'e0'), isFalse);
      expect(await dao.isProcessed('g2', 'aa', 0, 'e0'), isFalse);

      final p = (await dao.getPeers('g1')).single;
      expect(p.pubkey, 'aa');
      expect(p.me, 'p1');
      expect(p.eventIds, {0: 'e0', 1: 'e1'});
      expect(p.lastCreatedAt, 10);
      expect(p.lastSeenAt, 1001);
      expect(p.snapshotDigest, 'd1');
    });

    test('a newer event replaces the part id and the hints', () async {
      Future<void> rec(String id, int createdAt, String me, String? digest) =>
          dao.recordPeerEvent(
            groupId: 'g1',
            pubkey: 'aa',
            part: 0,
            eventId: id,
            createdAt: createdAt,
            seenAt: createdAt * 1000,
            me: me,
            snapshotDigest: digest,
          );
      await rec('e1', 10, 'p1', 'd1');
      await rec('e2', 20, 'p2', 'd2');
      var p = (await dao.getPeers('g1')).single;
      expect(p.eventIds, {0: 'e2'});
      expect(p.me, 'p2');
      expect(p.snapshotDigest, 'd2');
      expect(p.lastCreatedAt, 20);

      // An older event arriving late (a stale relay): its id is recorded
      // for dedup, but clocks and hints stay with the newest one.
      await rec('e0', 5, 'p0', 'd0');
      p = (await dao.getPeers('g1')).single;
      expect(p.eventIds, {0: 'e0'});
      expect(p.me, 'p2');
      expect(p.snapshotDigest, 'd2');
      expect(p.lastCreatedAt, 20);
      expect(p.lastSeenAt, 20000);
    });

    test('peers are per group, sorted by pubkey; watch follows', () async {
      final seen = <List<String>>[];
      final sub = dao
          .watchPeers('g1')
          .listen((ps) => seen.add([for (final p in ps) p.pubkey]));
      addTearDown(sub.cancel);
      for (final (g, pk) in [('g1', 'bb'), ('g1', 'aa'), ('g2', 'cc')]) {
        await dao.recordPeerEvent(
          groupId: g,
          pubkey: pk,
          part: 0,
          eventId: 'e',
          createdAt: 1,
          seenAt: 1,
        );
      }
      await pumpEventQueue();
      expect(
        [for (final p in await dao.getPeers('g1')) p.pubkey],
        ['aa', 'bb'],
      );
      expect(seen.last, ['aa', 'bb']);
    });

    test('newestPeerCreatedAt per group and overall', () async {
      expect(await dao.newestPeerCreatedAt(), 0);
      expect(await dao.newestPeerCreatedAt('g1'), 0);
      for (final (g, pk, t) in [('g1', 'aa', 30), ('g1', 'bb', 40)]) {
        await dao.recordPeerEvent(
          groupId: g,
          pubkey: pk,
          part: 0,
          eventId: 'e',
          createdAt: t,
          seenAt: 1,
        );
      }
      await dao.recordPeerEvent(
        groupId: 'g2',
        pubkey: 'aa',
        part: 0,
        eventId: 'e',
        createdAt: 90,
        seenAt: 1,
      );
      expect(await dao.newestPeerCreatedAt('g1'), 40);
      expect(await dao.newestPeerCreatedAt('g2'), 90);
      expect(await dao.newestPeerCreatedAt(), 90);
    });

    test('a malformed stored event-id map reads as empty', () async {
      await db
          .into(db.linkPeers)
          .insert(
            const LinkPeersCompanion(
              groupId: Value('g1'),
              pubkey: Value('aa'),
              eventIdsJson: Value('not json'),
            ),
          );
      expect((await dao.getPeers('g1')).single.eventIds, isEmpty);
      expect(await dao.isProcessed('g1', 'aa', 0, 'e'), isFalse);
      await dao.recordPeerEvent(
        groupId: 'g1',
        pubkey: 'aa',
        part: 0,
        eventId: 'e',
        createdAt: 1,
        seenAt: 1,
      );
      expect(await dao.isProcessed('g1', 'aa', 0, 'e'), isTrue);
    });

    test('markPeerLeft keeps the row marked left (G53 round 3, decision '
        '6); only a newer ordinary event brings it back', () async {
      await dao.recordPeerEvent(
        groupId: 'g1',
        pubkey: 'aa',
        part: 0,
        eventId: 'e1',
        createdAt: 10,
        seenAt: 1000,
        me: 'p1',
        snapshotDigest: 'D',
      );
      await dao.markPeerLeft(
        groupId: 'g1',
        pubkey: 'aa',
        part: 0,
        eventId: 'left0',
        createdAt: 20,
        seenAt: 2000,
        me: 'p1',
      );
      var p = (await dao.getPeers('g1')).single;
      expect(p.left, isTrue);
      expect(p.leftAt, 2000);
      expect(p.me, 'p1');
      expect(p.snapshotDigest, isNull);
      expect(p.lastCreatedAt, 20);
      expect(await dao.isProcessed('g1', 'aa', 0, 'left0'), isTrue);

      // The marker of another part: still the first time it was learned.
      await dao.markPeerLeft(
        groupId: 'g1',
        pubkey: 'aa',
        part: 1,
        eventId: 'left1',
        createdAt: 21,
        seenAt: 3000,
      );
      p = (await dao.getPeers('g1')).single;
      expect(p.leftAt, 2000);
      expect(p.me, 'p1');

      // An older part a stale relay still serves: recorded, still left.
      await dao.recordPeerEvent(
        groupId: 'g1',
        pubkey: 'aa',
        part: 2,
        eventId: 'old2',
        createdAt: 15,
        seenAt: 4000,
        me: 'p1',
        snapshotDigest: 'old',
      );
      p = (await dao.getPeers('g1')).single;
      expect(p.left, isTrue);
      expect(p.snapshotDigest, isNull);

      // A newer ordinary event: the publisher has the group again.
      await dao.recordPeerEvent(
        groupId: 'g1',
        pubkey: 'aa',
        part: 0,
        eventId: 'e3',
        createdAt: 30,
        seenAt: 5000,
        me: 'p1',
        snapshotDigest: 'D3',
      );
      p = (await dao.getPeers('g1')).single;
      expect(p.left, isFalse);
      expect(p.snapshotDigest, 'D3');

      // A late, older "left" marker doesn't make it left again.
      await dao.markPeerLeft(
        groupId: 'g1',
        pubkey: 'aa',
        part: 1,
        eventId: 'left1b',
        createdAt: 25,
        seenAt: 6000,
      );
      expect((await dao.getPeers('g1')).single.left, isFalse);
    });

    test('markPeerLeft for an unknown publisher creates a left row', () async {
      await dao.markPeerLeft(
        groupId: 'g1',
        pubkey: 'bb',
        part: 0,
        eventId: 'l',
        createdAt: 5,
        seenAt: 700,
        me: 'p2',
      );
      final p = (await dao.getPeers('g1')).single;
      expect((p.pubkey, p.me, p.leftAt, p.lastSeenAt), ('bb', 'p2', 700, 700));
    });
  });

  group('purge / wipe', () {
    Future<void> seed(String groupId) async {
      await dao.putChannel(_channel(groupId));
      await dao.recordPeerEvent(
        groupId: groupId,
        pubkey: 'aa',
        part: 0,
        eventId: 'e',
        createdAt: 1,
        seenAt: 1,
      );
    }

    test('purgeGroup drops the group\'s link rows only', () async {
      await seed('g1');
      await seed('g2');
      await db.purgeGroup('g1');
      expect(await dao.getChannel('g1'), isNull);
      expect(await dao.getPeers('g1'), isEmpty);
      expect(await dao.getChannel('g2'), isNotNull);
      expect(await dao.getPeers('g2'), hasLength(1));
    });

    test('wipeAll drops every link row', () async {
      await seed('g1');
      await seed('g2');
      await db.wipeAll();
      expect(await dao.getAllChannels(), isEmpty);
      expect(await dao.getPeers('g1'), isEmpty);
      expect(await dao.getPeers('g2'), isEmpty);
    });
  });
}
