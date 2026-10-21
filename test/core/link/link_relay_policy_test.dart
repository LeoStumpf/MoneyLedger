/// G52 step 5: per-relay back-off / block policy (§4.4), the persisted relay
/// state, the relay list setting, NIP-11 (§4.6) and NIP-09 (§7.3) helpers.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money_ledger/core/link/link_envelope.dart';
import 'package:money_ledger/core/link/link_relay_policy.dart';
import 'package:money_ledger/core/link/link_snapshot.dart';
import 'package:money_ledger/core/link/nostr/nip09.dart';
import 'package:money_ledger/core/link/nostr/nip11.dart';
import 'package:money_ledger/core/link/nostr/nostr_event.dart';
import 'package:money_ledger/core/link/nostr/nostr_frames.dart';
import 'package:money_ledger/core/link/nostr/nostr_relay_pool.dart';

import '../../helpers/fake_relay_network.dart';

const _a = 'wss://a.example';
const _b = 'wss://b.example';

NostrPublishResult _r(String relay, bool accepted, String message) =>
    NostrPublishResult(relay, classifyOk(accepted, message), message);

void main() {
  group('classifyRelayAnswer', () {
    test('maps every NIP-01 prefix', () {
      expect(classifyRelayAnswer(_r(_a, true, '')), RelayAnswer.ok);
      expect(
        classifyRelayAnswer(_r(_a, true, 'duplicate: have it')),
        RelayAnswer.ok,
      );
      expect(
        classifyRelayAnswer(_r(_a, false, 'replaced: have newer event')),
        RelayAnswer.replaced,
      );
      expect(
        classifyRelayAnswer(_r(_a, false, 'rate-limited: slow down')),
        RelayAnswer.rateLimited,
      );
      for (final m in [
        'blocked: no',
        'restricted: members only',
        'invalid: kind not allowed',
        'pow: difficulty 20',
        'auth-required: login',
      ]) {
        expect(
          classifyRelayAnswer(_r(_a, false, m)),
          RelayAnswer.rejects,
          reason: m,
        );
      }
      expect(
        classifyRelayAnswer(_r(_a, false, 'invalid: event too large: 70000')),
        RelayAnswer.tooLarge,
      );
      expect(
        classifyRelayAnswer(
          const NostrPublishResult(_a, NostrPublishStatus.tooLarge, 'x'),
        ),
        RelayAnswer.tooLarge,
      );
      expect(
        classifyRelayAnswer(_r(_a, false, 'error: db down')),
        RelayAnswer.transient,
      );
      expect(
        classifyRelayAnswer(
          const NostrPublishResult(_a, NostrPublishStatus.timeout, 'no OK'),
        ),
        RelayAnswer.transient,
      );
    });
  });

  group('LinkRelayPolicy', () {
    late int now;
    late LinkRelayPolicy policy;
    setUp(() {
      now = 1000000;
      policy = LinkRelayPolicy(clock: () => now);
    });

    test('rate-limited: 1 min doubling to 1 h, reset by a success', () {
      expect(policy.canPublish(_a), isTrue);
      final waits = <int>[];
      for (var i = 0; i < 8; i++) {
        policy.onResult(_r(_a, false, 'rate-limited: x'));
        waits.add(policy.rateLimitedUntil(_a)! - now);
      }
      expect(waits, [
        for (final m in [1, 2, 4, 8, 16, 32, 60, 60]) m * 60000,
      ]);
      expect(policy.canPublish(_a), isFalse);
      expect(policy.canPublish(_b), isTrue);
      now += 3600000;
      expect(policy.canPublish(_a), isTrue);
      policy.onResult(_r(_a, true, ''));
      policy.onResult(_r(_a, false, 'rate-limited: x'));
      expect(policy.rateLimitedUntil(_a)! - now, 60000);
    });

    test('blocked / restricted: skipped for the rest of the run; '
        'too large and transient never block', () {
      policy.onResult(_r(_a, false, 'blocked: spam'));
      expect(policy.rejects(_a), isTrue);
      expect(policy.canPublish(_a), isFalse);
      expect(policy.rejecting, {_a: 'blocked: spam'});
      now += 100 * 3600000;
      expect(policy.canPublish(_a), isFalse);
      policy.onResult(_r(_b, false, 'invalid: event too large: 70000'));
      policy.onResult(_r(_b, false, 'error: x'));
      expect(policy.canPublish(_b), isTrue);
    });

    test('nextAvailableIn: now, the earliest back-off, or null', () {
      expect(policy.nextAvailableIn([_a, _b]), Duration.zero);
      policy.onResult(_r(_a, false, 'rate-limited: x'));
      expect(policy.nextAvailableIn([_a, _b]), Duration.zero);
      policy.onResult(_r(_b, false, 'rate-limited: x'));
      policy.onResult(_r(_b, false, 'rate-limited: x'));
      expect(policy.nextAvailableIn([_a, _b]), const Duration(minutes: 1));
      policy.onResult(_r(_a, false, 'restricted: x'));
      expect(policy.nextAvailableIn([_a, _b]), const Duration(minutes: 2));
      policy.onResult(_r(_b, false, 'blocked: x'));
      expect(policy.nextAvailableIn([_a, _b]), isNull);
    });
  });

  group('LinkRelayState', () {
    test('round-trips, tolerates garbage, knows when NIP-11 is stale', () {
      const info = RelayInfo(
        name: 'r',
        supportedNips: [1, 40],
        maxMessageLength: 131072,
        maxSubscriptions: 20,
      );
      final s = const LinkRelayState().copyWith(
        info: info,
        infoFetchedAt: 1000,
        lastOkAt: 2000,
        lastRejectionAt: 3000,
        lastRejection: 'rejects',
        lastRejectionMessage: 'blocked: x',
      );
      final back = LinkRelayState.decode(s.encode());
      expect(back.info!.maxMessageLength, 131072);
      expect(back.info!.supportedNips, [1, 40]);
      expect(back.infoFetchedAt, 1000);
      expect(back.lastOkAt, 2000);
      expect(back.lastRejectionMessage, 'blocked: x');
      expect(back.infoStale(1000 + kRelayInfoMaxAge.inMilliseconds), isFalse);
      expect(back.infoStale(1001 + kRelayInfoMaxAge.inMilliseconds), isTrue);
      expect(const LinkRelayState().infoStale(0), isTrue);
      expect(LinkRelayState.decode('{nope').lastOkAt, isNull);
      expect(LinkRelayState.decode('[1]').lastOkAt, isNull);
      expect(LinkRelayState.decode(null).info, isNull);
    });

    test('parseLinkRelays: defaults unless a valid, non-empty list', () {
      const d = ['wss://d.example'];
      expect(parseLinkRelays(null, d), d);
      expect(parseLinkRelays('garbage', d), d);
      expect(parseLinkRelays('[]', d), d);
      expect(parseLinkRelays('["https://x", 3]', d), d);
      expect(parseLinkRelays(jsonEncode([_a, _b, _a, 'nope']), d), [_a, _b]);
    });
  });

  group('NIP-11', () {
    test('parses the limitation fields, wrong types read as absent', () {
      final info = RelayInfo.fromJson({
        'name': 'nos.lol',
        'software': 'git+https://github.com/hoytech/strfry.git',
        'supported_nips': [1, 9, 11, 40, 'x'],
        'limitation': {
          'max_message_length': 131072,
          'max_content_length': 'big',
          'max_subscriptions': 20,
          'auth_required': false,
          'payment_required': true,
        },
      });
      expect(info.name, 'nos.lol');
      expect(info.supportedNips, [1, 9, 11, 40]);
      expect(info.maxMessageLength, 131072);
      expect(info.maxContentLength, isNull);
      expect(info.maxSubscriptions, 20);
      expect(info.paymentRequired, isTrue);
      expect(RelayInfo.fromJson({'limitation': 5}).maxMessageLength, isNull);
      final back = RelayInfo.fromJson(info.toJson());
      expect(back.maxSubscriptions, 20);
      expect(back.paymentRequired, isTrue);
    });

    test('budget: never above kLinkContentBudget, lowered by a smaller '
        'advertised limit', () {
      expect(relayContentBudget(null), kLinkContentBudget);
      expect(
        relayContentBudget(const RelayInfo(maxMessageLength: 131072)),
        kLinkContentBudget,
      );
      expect(
        relayContentBudget(const RelayInfo(maxContentLength: 20000)),
        20000,
      );
      expect(
        relayContentBudget(const RelayInfo(maxMessageLength: 32768)),
        32768 - kLinkEventOverheadBytes,
      );
    });

    test('usability check for custom relays', () {
      expect(relayInfoProblem(const RelayInfo()), isNull);
      expect(
        relayInfoProblem(const RelayInfo(supportedNips: [1, 11, 40])),
        isNull,
      );
      expect(
        relayInfoProblem(const RelayInfo(authRequired: true)),
        RelayInfoProblem.needsAccount,
      );
      expect(
        relayInfoProblem(const RelayInfo(paymentRequired: true)),
        RelayInfoProblem.needsAccount,
      );
      expect(
        relayInfoProblem(const RelayInfo(supportedNips: [1, 11])),
        RelayInfoProblem.noExpiration,
      );
    });

    test('relayInfoUrl: wss → https, ws → http, else null', () {
      expect(relayInfoUrl('wss://nos.lol').toString(), 'https://nos.lol');
      expect(
        relayInfoUrl('ws://localhost:7777/x').toString(),
        'http://localhost:7777/x',
      );
      expect(relayInfoUrl('https://nos.lol'), isNull);
      expect(relayInfoUrl('nope'), isNull);
    });

    test('HttpRelayInfoFetcher sends the NIP-11 Accept header', () async {
      late http.Request seen;
      final fetcher = HttpRelayInfoFetcher(
        client: () => MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode({
              'supported_nips': [40],
              'limitation': {'max_message_length': 5000},
            }),
            200,
          );
        }),
      );
      final info = await fetcher.fetch('wss://relay.example');
      expect(seen.url.toString(), 'https://relay.example');
      expect(seen.headers['Accept'], 'application/nostr+json');
      expect(info.maxMessageLength, 5000);

      final failing = HttpRelayInfoFetcher(
        client: () => MockClient((_) async => http.Response('no', 404)),
      );
      await expectLater(failing.fetch('wss://relay.example'), throwsStateError);
      final notJson = HttpRelayInfoFetcher(
        client: () => MockClient((_) async => http.Response('[1]', 200)),
      );
      await expectLater(
        notJson.fetch('wss://relay.example'),
        throwsFormatException,
      );
    });
  });

  group('NIP-09', () {
    const key =
        '0000000000000000000000000000000000000000000000000000000000000003';

    test('a deletion names every part address + the kind', () {
      final pub = nostrPublicKey(key);
      final del = buildNostrDeletion(
        privateKey: key,
        kind: kLinkEventKind,
        dTags: ['t', 't.1'],
        createdAt: 100,
      );
      expect(del.kind, kNostrDeletionKind);
      expect(del.pubkey, pub);
      expect(del.content, '');
      expect(del.tags, [
        ['a', '$kLinkEventKind:$pub:t'],
        ['a', '$kLinkEventKind:$pub:t.1'],
        ['k', '$kLinkEventKind'],
      ]);
      expect(verifyNostrEvent(del), isTrue);
    });

    test('the fake relay deletes our addresses up to the request clock, '
        'never another pubkey\'s', () async {
      const other =
          '0000000000000000000000000000000000000000000000000000000000000005';
      final net = FakeRelayNetwork(nowSeconds: () => 1000);
      final pool = NostrRelayPool(
        relays: [_a],
        connector: net,
        verifySignatures: false,
        nowSeconds: () => 1000,
      );
      addTearDown(pool.close);
      NostrEvent ev(String k, String d, int at) => signNostrEvent(
        privateKey: k,
        kind: kLinkEventKind,
        tags: [
          ['d', d],
        ],
        content: '1:AAAA',
        createdAt: at,
      );
      await pool.publish(ev(key, 't', 100));
      await pool.publish(ev(key, linkPartTopic('t', 1), 300));
      await pool.publish(ev(other, 't', 100));
      final del = buildNostrDeletion(
        privateKey: key,
        kind: kLinkEventKind,
        dTags: ['t', linkPartTopic('t', 1)],
        createdAt: 200,
      );
      final r = await pool.publish(del);
      expect(r.single.acceptedEquivalent, isTrue);
      final left = net.relay(_a).events;
      // Ours at `t` is gone; `t.1` is newer than the request; the other
      // pubkey's event at `t` stays.
      expect(
        left.where((e) => e.kind == kLinkEventKind).map((e) => e.createdAt),
        unorderedEquals([300, 100]),
      );
      expect(
        left
            .where((e) => e.kind == kLinkEventKind && e.createdAt == 100)
            .single
            .pubkey,
        nostrPublicKey(other),
      );
      expect(net.relay(_a).deleted, hasLength(1));
    });
  });
}
