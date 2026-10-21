/// G68 (U24) + G52 step 9: the pure rows of the group sync sheet, and the
/// pure relay-settings helpers (address parsing, status line, terms link).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/link/link_relay_policy.dart';
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/core/link/nostr/nip11.dart';
import 'package:money_ledger/core/sync/sync_health.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/features/link/relay_settings.dart';
import 'package:money_ledger/features/sync/peer_sync_rows.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';

MemberModel _m(
  String id,
  String name, {
  String? mxid,
  String status = 'active',
}) => MemberModel(
  groupId: 'g',
  userId: id,
  displayName: name,
  matrixId: mxid,
  status: status,
  updatedAt: 1,
);

void main() {
  group('matrixPeerRows', () {
    final members = [
      _m('@me:x.org', 'Me', mxid: '@me:x.org'),
      _m('@ben:x.org', 'Ben', mxid: '@ben:x.org'),
      _m('@cleo:x.org', 'Cleo', mxid: '@cleo:x.org'),
      _m('@dora:x.org', 'Dora', mxid: '@dora:x.org'),
      _m('@eve:x.org', 'Eve', mxid: '@eve:x.org'),
      _m('@gone:x.org', 'Gone', mxid: '@gone:x.org', status: 'removed'),
      _m('p-local', 'Fritz'),
    ];

    test('one row per active Matrix peer: has everything / waiting / no '
        'device / no verified device; our other devices last', () {
      final rows = matrixPeerRows(
        selfMxid: '@me:x.org',
        members: members,
        peerInSyncAt: {'@ben:x.org': 500, '@cleo:x.org': 100, '@me:x.org': 400},
        maxRecordUpdatedAt: 500,
        health: const SyncHealthState(
          unreachablePeers: {'@dora:x.org'},
          unverifiedPeers: {'@eve:x.org'},
        ),
      );
      expect(
        [for (final r in rows) (r.name, r.kind, r.at, r.isSelf)],
        [
          ('Ben', PeerSyncKind.upToDate, 500, false),
          ('Cleo', PeerSyncKind.waiting, 100, false),
          ('Dora', PeerSyncKind.noDevice, null, false),
          ('Eve', PeerSyncKind.unverified, null, false),
          ('Me', PeerSyncKind.waiting, 400, true),
        ],
      );
      expect(localOnlyPeople(members), 1);
    });

    test('no other device of ours ever proved it → no self row; never in '
        'sync → waiting without a time', () {
      final rows = matrixPeerRows(
        selfMxid: '@me:x.org',
        members: members.take(2).toList(),
        peerInSyncAt: const {},
        maxRecordUpdatedAt: 10,
        health: const SyncHealthState(),
      );
      expect(rows.single.kind, PeerSyncKind.waiting);
      expect(rows.single.at, isNull);
    });

    test('computeSyncStatus carries the per-peer times for the sheet', () {
      final s = computeSyncStatus(
        selfId: '@me:x.org',
        members: members,
        peerInSyncAt: const {'@ben:x.org': 7, '@me:x.org': 3},
        maxRecordUpdatedAt: 9,
      );
      expect(s.peerInSyncAt, {'@ben:x.org': 7, '@me:x.org': 3});
      expect(s.maxRecordUpdatedAt, 9);
    });
  });

  group('linkPeerRows', () {
    final members = [_m('p1', 'Anna'), _m('p2', 'Ben'), _m('p3', 'Cleo')];
    LinkPeerModel peer(
      String pub,
      String? me, {
      int at = 100,
      String? digest,
      Map<int, String> parts = const {0: 'e'},
    }) => LinkPeerModel(
      groupId: 'g',
      pubkey: pub,
      me: me,
      lastCreatedAt: at,
      snapshotDigest: digest,
      eventIds: parts,
    );

    test('grouped by participant (newest publish, device count); same '
        'digest = has everything; unknown + our other devices last', () {
      final rows = linkPeerRows(
        peers: [
          peer('a', 'p2', at: 100, digest: 'D'),
          peer('b', 'p2', at: 300, digest: 'old'),
          peer('c', 'p3', at: 200, digest: 'old'),
          peer('d', 'zz', at: 50),
          peer('e', 'p1', at: 400, digest: 'D'),
        ],
        members: members,
        myParticipantId: 'p1',
        ourDigest: 'D',
        ourParts: 1,
      );
      expect(
        [for (final r in rows) (r.name, r.kind, r.at, r.devices, r.isSelf)],
        [
          ('Ben', PeerSyncKind.upToDate, 300000, 2, false),
          ('Cleo', PeerSyncKind.published, 200000, 1, false),
          (null, PeerSyncKind.published, 50000, 1, false),
          ('Anna', PeerSyncKind.upToDate, 400000, 1, true),
        ],
      );
    });

    test('never "has everything" while ours is not on the relays, or for '
        'multi-part snapshots', () {
      expect(
        linkPeerRows(
          peers: [peer('a', 'p2', digest: 'D')],
          members: members,
          myParticipantId: 'p1',
          ourDigest: null,
          ourParts: 1,
        ).single.kind,
        PeerSyncKind.published,
      );
      expect(
        linkPeerRows(
          peers: [
            peer('a', 'p2', digest: 'D', parts: {0: 'x', 1: 'y'}),
          ],
          members: members,
          myParticipantId: 'p1',
          ourDigest: 'D',
          ourParts: 1,
        ).single.kind,
        PeerSyncKind.published,
      );
      expect(
        linkPeerRows(
          peers: [peer('a', 'p2', digest: 'D')],
          members: members,
          myParticipantId: 'p1',
          ourDigest: 'D',
          ourParts: 2,
        ).single.kind,
        PeerSyncKind.published,
      );
    });
  });

  group('relay settings (G52 step 9)', () {
    test('parseRelayInput: wss:// added, lower-cased host, ws:// / junk / '
        'duplicates refused', () {
      expect(
        parseRelayInput('relay.example.org', const []).url,
        'wss://relay.example.org',
      );
      expect(
        parseRelayInput(' WSS://Relay.Example.org/ ', const []).url,
        'wss://relay.example.org',
      );
      expect(
        parseRelayInput('wss://r.example.org:4443/nostr', const []).url,
        'wss://r.example.org:4443/nostr',
      );
      expect(
        parseRelayInput('ws://r.example.org', const []).problem,
        RelayInputProblem.notSecure,
      );
      for (final bad in [
        '',
        'nope',
        'https://r.example.org',
        'wss://a b.org',
        'wss://u@r.example.org',
        'wss://r.example.org?x=1',
      ]) {
        expect(
          parseRelayInput(bad, const []).problem,
          RelayInputProblem.invalid,
          reason: bad,
        );
      }
      expect(
        parseRelayInput('nos.lol', const ['wss://nos.lol']).problem,
        RelayInputProblem.duplicate,
      );
    });

    test('labels, default list, terms link', () {
      expect(relayLabel('wss://nos.lol'), 'nos.lol');
      expect(relayLabel('wss://r.example.org:4443/x'), 'r.example.org:4443/x');
      expect(
        isDefaultRelayList(const ['wss://nostr.mom', 'wss://nos.lol']),
        isTrue,
      );
      expect(isDefaultRelayList(const ['wss://nos.lol']), isFalse);
      expect(
        relayTermsUrl(const LinkRelayView(url: 'wss://nos.lol')),
        'https://wikifreedia.xyz/nos.lol/',
      );
      expect(relayTermsUrl(const LinkRelayView(url: 'wss://x.org')), isNull);
      expect(
        relayTermsUrl(
          const LinkRelayView(
            url: 'wss://x.org',
            state: LinkRelayState(
              info: RelayInfo(termsOfService: 'https://x.org/tos'),
            ),
          ),
        ),
        'https://x.org/tos',
      );
    });

    test('NIP-11 terms_of_service: only http(s) URLs are kept', () {
      expect(
        RelayInfo.fromJson({
          'terms_of_service': 'https://a.org/t',
        }).termsOfService,
        'https://a.org/t',
      );
      expect(
        RelayInfo.fromJson({
          'terms_of_service': 'javascript:alert(1)',
        }).termsOfService,
        isNull,
      );
      expect(
        RelayInfo.fromJson({'terms_of_service': 5}).termsOfService,
        isNull,
      );
      final round = RelayInfo.fromJson(
        const RelayInfo(termsOfService: 'https://a.org/t').toJson(),
      );
      expect(round.termsOfService, 'https://a.org/t');
    });

    test('relayStatusOf: refusing > rate-limited > unsuitable > last '
        'refused > ok > unused', () {
      expect(
        relayStatusOf(const LinkRelayView(url: 'u')).kind,
        RelayStatusKind.unused,
      );
      expect(
        relayStatusOf(
          const LinkRelayView(url: 'u', state: LinkRelayState(lastOkAt: 5)),
        ).kind,
        RelayStatusKind.ok,
      );
      final refused = relayStatusOf(
        const LinkRelayView(
          url: 'u',
          state: LinkRelayState(
            lastOkAt: 5,
            lastRejectionAt: 9,
            lastRejection: 'rejects',
            lastRejectionMessage: 'blocked: x',
          ),
        ),
      );
      expect(refused.kind, RelayStatusKind.lastRefused);
      expect(refused.message, 'blocked: x');
      expect(refused.isProblem, isTrue);
      // An old rate limit is no refusal.
      expect(
        relayStatusOf(
          const LinkRelayView(
            url: 'u',
            state: LinkRelayState(
              lastOkAt: 5,
              lastRejectionAt: 9,
              lastRejection: 'rateLimited',
            ),
          ),
        ).kind,
        RelayStatusKind.ok,
      );
      expect(
        relayStatusOf(
          const LinkRelayView(
            url: 'u',
            state: LinkRelayState(info: RelayInfo(authRequired: true)),
          ),
        ).problem,
        RelayInfoProblem.needsAccount,
      );
      expect(
        relayStatusOf(const LinkRelayView(url: 'u', rateLimitedUntil: 99)).kind,
        RelayStatusKind.rateLimited,
      );
      expect(
        relayStatusOf(
          const LinkRelayView(
            url: 'u',
            rejectingMessage: 'blocked: y',
            rateLimitedUntil: 99,
          ),
        ).kind,
        RelayStatusKind.rejects,
      );
    });
  });
}
