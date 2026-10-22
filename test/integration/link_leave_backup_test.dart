/// G52 step 10 end-to-end over the fake relays (design doc §7.2, §7.3):
/// deleting a link group first removes this device's copy from the relays
/// (header-only parts + NIP-09) while the others keep theirs; the full
/// backup carries the invite key; restoring it re-opens the channel (fresh
/// Nostr key, no "me" → nothing published) and the group syncs again once
/// "who am I" is chosen.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/link/group_policy.dart';
import 'package:money_ledger/core/link/link_envelope.dart' show kLinkEventKind;
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/core/link/link_uri.dart';
import 'package:money_ledger/core/link/nostr/nip11.dart';
import 'package:money_ledger/core/link/nostr/nostr_event.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/features/backup/backup_service.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/features/link/link_join.dart';
import 'package:money_ledger/features/sync/peer_sync_rows.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
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
  /// B joins as Ben.
  Future<
    ({
      ProviderContainer a,
      AppDatabase aDb,
      ProviderContainer b,
      AppDatabase bDb,
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
    return (a: a.c, aDb: a.db, b: b.c, bDb: b.db);
  }

  test(
    'delete → unpublished (peers keep theirs) → the backup carries the '
    'key → restore re-opens the channel → "me" chosen → syncs again',
    () async {
      final s = await sharedGroup();
      final oldChannel = (await LinkDao(s.aDb).getChannel(_g))!;
      final aPub = nostrPublicKey(oldChannel.nostrPriv);
      final bPub = nostrPublicKey(
        (await LinkDao(s.bDb).getChannel(_g))!.nostrPriv,
      );
      for (final r in [_r1, _r2]) {
        expect(linkEvents(r, aPub), isNotEmpty, reason: r);
      }

      // The full backup (before deleting) carries the invite key.
      final keepBackup = s.a.listen(backupServiceProvider, (_, _) {});
      final json = await keepBackup.read().exportJson(
        account: kLocalAccountId,
        now: _t0,
      );
      keepBackup.close();
      final backup = parseBackup(json);
      final link = backupGroupLink(backup.groups.single)!;
      expect(link.secret, oldChannel.secret);
      expect(link.epoch, oldChannel.epoch);
      // Never the device's Nostr key or "who am I".
      expect(json, isNot(contains(oldChannel.nostrPriv)));
      expect((jsonDecode(json) as Map)['groups'][0]['link'], {
        'epoch': 1,
        'secret': oldChannel.secret,
      });

      // Delete on A: unpublished first, then purged (channel incl. key gone).
      final keepExiter = s.a.listen(groupExiterProvider, (_, _) {});
      await s.a.read(groupExiterProvider.notifier).delete(_g);
      expect(s.a.read(groupExiterProvider).error, isNull);
      keepExiter.close();
      await settle();
      expect(await GroupsDao(s.aDb).getGroup(_g), isNull);
      expect(await LinkDao(s.aDb).getChannel(_g), isNull);
      for (final r in [_r1, _r2]) {
        expect(linkEvents(r, aPub), isEmpty, reason: r);
        expect(net.relay(r).deleted, isNotEmpty, reason: r);
        expect(linkEvents(r, bPub), isNotEmpty, reason: r); // B keeps its copy
      }
      expect(await GroupsDao(s.bDb).getGroup(_g), isNotNull);
      expect(
        (await ExpensesDao(s.bDb).getAllExpensesForGroup(_g)).single.id,
        'e1',
      );
      // DEV-J + G53 round 3 (decision 6): B saw A's "left" header parts —
      // A isn't a peer that "updated just now", it stays in B's sync sheet
      // as "Deleted the group" (stored: A's events are gone from the
      // relays).
      final leftPeer = (await LinkDao(
        s.bDb,
      ).getPeers(_g)).singleWhere((p) => p.pubkey == aPub);
      expect(leftPeer.left, isTrue);
      expect(leftPeer.me, 'p1');
      expect(leftPeer.snapshotDigest, isNull);
      List<PeerSyncRow> bRows(List<LinkPeerModel> peers, List<MemberModel> m) =>
          linkPeerRows(
            peers: peers,
            members: m,
            myParticipantId: 'p2',
            ourDigest: null,
            ourParts: 1,
          );
      final bMembers = await MembersDao(s.bDb).getMembers(_g);
      final deletedRow = bRows(
        await LinkDao(s.bDb).getPeers(_g),
        bMembers,
      ).singleWhere((r) => r.participantId == 'p1');
      expect(deletedRow.kind, PeerSyncKind.deletedGroup);
      expect(deletedRow.at, leftPeer.leftAt);
      // A later fetch (the relays no longer serve A's events) keeps it.
      await s.b.read(linkSyncEngineProvider).syncNow(_g);
      await settle();
      expect(
        (await LinkDao(
          s.bDb,
        ).getPeers(_g)).singleWhere((p) => p.pubkey == aPub).left,
        isTrue,
      );

      // Restore on A: the preview counts the link group; the channel comes
      // back with the same key, a fresh Nostr key and no "me".
      final keepRestore = s.a.listen(backupServiceProvider, (_, _) {});
      final service = keepRestore.read();
      final preview = await service.preview(backup, myMxid: kLocalAccountId);
      expect(preview.linkGroups, 1);
      expect(await service.restore(backup), [_g]);
      keepRestore.close();
      final reopened = (await LinkDao(s.aDb).getChannel(_g))!;
      expect(reopened.secret, oldChannel.secret);
      expect(reopened.nostrPriv, isNot(oldChannel.nostrPriv));
      expect(reopened.myParticipantId, isNull);
      expect((await LinkDao(s.aDb).policyOf(_g)).policy, GroupPolicy.linkOnly);
      // Restored as link versions: nothing signed / waiting to be signed.
      final members = await MembersDao(s.aDb).getMembers(_g);
      expect(members.map((m) => m.matrixId), everyElement(isNull));
      expect(members.map((m) => m.pendingSign), everyElement(isFalse));
      await settle();
      final newPub = nostrPublicKey(reopened.nostrPriv);
      for (final r in [_r1, _r2]) {
        expect(linkEvents(r, newPub), isEmpty, reason: '$r: no "me" yet');
      }

      // "Who am I" → published; B sees the new device as Anna.
      await chooseLinkParticipant(
        s.aDb,
        _g,
        participantId: 'p1',
        newName: '',
        clock: () => DateTime.now().millisecondsSinceEpoch,
      );
      await settle();
      for (final r in [_r1, _r2]) {
        expect(linkEvents(r, newPub), isNotEmpty, reason: r);
      }
      final peers = await LinkDao(s.bDb).getPeers(_g);
      expect(peers.where((p) => p.pubkey == newPub).map((p) => p.me), ['p1']);
      // Anna is back with a new device: her row is an ordinary one again
      // (the deleted copy no longer counts — G53 round 3).
      final annaRow = bRows(
        peers,
        await MembersDao(s.bDb).getMembers(_g),
      ).singleWhere((r) => r.participantId == 'p1');
      expect(annaRow.kind, isNot(PeerSyncKind.deletedGroup));
      expect(annaRow.devices, 1);
    },
  );

  test('restore keeps an existing channel and never turns a group held '
      'here without one into a link group', () async {
    final s = await sharedGroup();
    final keep = s.a.listen(backupServiceProvider, (_, _) {});
    final backup = parseBackup(
      await keep.read().exportJson(account: kLocalAccountId, now: _t0),
    );
    keep.close();

    // Same device, channel still there: unchanged — and the preview
    // doesn't warn about the invite key (DEV-J: nothing comes back).
    final before = (await LinkDao(s.aDb).getChannel(_g))!;
    final again = s.a.listen(backupServiceProvider, (_, _) {});
    final preview = await again.read().preview(backup, myMxid: kLocalAccountId);
    expect(preview.linkGroups, 0);
    await again.read().restore(backup);
    again.close();
    final after = (await LinkDao(s.aDb).getChannel(_g))!;
    expect(after.nostrPriv, before.nostrPriv);
    expect(after.myParticipantId, 'p1');

    // Another device that holds the group without a channel: no channel.
    final c = device();
    await GroupsDao(c.db).upsertGroupLww(
      groupCompanion(
        GroupModel(
          roomId: _g,
          name: 'Mine',
          currency: 'EUR',
          updatedAt: _t0 - 9000,
          pendingSign: true,
        ),
      ),
    );
    final other = c.c.listen(backupServiceProvider, (_, _) {});
    await other.read().restore(backup);
    other.close();
    expect(await LinkDao(c.db).getChannel(_g), isNull);
  });
}
