import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/link/link_envelope.dart';
import 'package:money_ledger/core/link/nostr/nostr_event.dart';
import 'package:money_ledger/core/link/nostr/nostr_frames.dart';

final _event = signNostrEvent(
  privateKey: '${'00' * 31}03',
  kind: kLinkEventKind,
  tags: const [
    ['d', 'topic'],
    ['expiration', '1797184000'],
  ],
  content: '1:AAAA',
  createdAt: 1792000000,
  aux: List.filled(32, 0),
);

void main() {
  group('client frames', () {
    test('EVENT / REQ / CLOSE', () {
      expect(jsonDecode(encodeEventFrame(_event)), ['EVENT', _event.toJson()]);
      expect(
        encodeReqFrame('s1', const [
          NostrFilter(
            kinds: [kLinkEventKind],
            tags: {
              'd': ['a', 'b'],
            },
            since: 5,
          ),
          NostrFilter(authors: ['x'], limit: 3),
        ]),
        '["REQ","s1",{"kinds":[31847],"#d":["a","b"],"since":5},'
        '{"authors":["x"],"limit":3}]',
      );
      expect(encodeCloseFrame('s1'), '["CLOSE","s1"]');
    });
  });

  group('relay messages', () {
    test('parses every type', () {
      final ev = parseRelayMessage(jsonEncode(['EVENT', 's', _event.toJson()]));
      expect(ev, isA<RelayEventMessage>());
      expect((ev as RelayEventMessage).subscriptionId, 's');
      expect(ev.event.id, _event.id);

      final ok = parseRelayMessage('["OK","${_event.id}",false,"replaced: x"]');
      expect(ok, isA<RelayOkMessage>());
      expect((ok as RelayOkMessage).accepted, isFalse);
      expect(ok.message, 'replaced: x');
      expect(
        (parseRelayMessage('["OK","id",true]') as RelayOkMessage).message,
        '',
      );

      expect(
        (parseRelayMessage('["EOSE","s"]') as RelayEoseMessage).subscriptionId,
        's',
      );
      final closed = parseRelayMessage('["CLOSED","s","error: shutdown"]');
      expect((closed as RelayClosedMessage).message, 'error: shutdown');
      expect(
        (parseRelayMessage('["NOTICE","hi"]') as RelayNoticeMessage).message,
        'hi',
      );
    });

    test('malformed or unknown frames → null, never a throw', () {
      for (final f in [
        '',
        'not json',
        '{}',
        '[]',
        '[1]',
        '["EVENT"]',
        '["EVENT","s"]',
        '["EVENT","s",{"id":"x"}]',
        '["EVENT",1,${jsonEncode(_event.toJson())}]',
        '["OK"]',
        '["OK","id"]',
        '["OK","id","true"]',
        '["EOSE"]',
        '["EOSE",5]',
        '["CLOSED"]',
        '["AUTH","challenge"]',
        '["COUNT","s",{"count":1}]',
        '["UNKNOWN"]',
      ]) {
        expect(parseRelayMessage(f), isNull, reason: f);
      }
    });
  });

  group('classifyOk', () {
    test('NIP-01 prefixes', () {
      const cases = {
        (true, ''): NostrPublishStatus.accepted,
        (true, 'stored'): NostrPublishStatus.accepted,
        (true, 'duplicate: already have this event'):
            NostrPublishStatus.duplicate,
        (false, 'duplicate: already have this event'):
            NostrPublishStatus.duplicate,
        (false, 'replaced: have newer event'): NostrPublishStatus.replaced,
        (false, 'rate-limited: slow down'): NostrPublishStatus.rateLimited,
        (false, 'invalid: event too large: 70000'): NostrPublishStatus.invalid,
        (false, 'blocked: you are banned'): NostrPublishStatus.blocked,
        (false, 'restricted: members only'): NostrPublishStatus.restricted,
        (false, 'pow: difficulty 20'): NostrPublishStatus.pow,
        (false, 'auth-required: login'): NostrPublishStatus.authRequired,
        (false, 'error: db down'): NostrPublishStatus.error,
        (false, ''): NostrPublishStatus.error,
        (false, 'something odd'): NostrPublishStatus.error,
      };
      cases.forEach((k, v) {
        expect(classifyOk(k.$1, k.$2), v, reason: '$k');
      });
    });

    test('accepted-equivalent: accepted, duplicate, replaced', () {
      expect(NostrPublishStatus.values.where(isAcceptedEquivalent).toSet(), {
        NostrPublishStatus.accepted,
        NostrPublishStatus.duplicate,
        NostrPublishStatus.replaced,
      });
    });
  });

  group('NostrFilter', () {
    test('matches', () {
      bool m(NostrFilter f) => f.matches(_event);
      expect(m(const NostrFilter()), isTrue);
      expect(m(const NostrFilter(kinds: [1, kLinkEventKind])), isTrue);
      expect(m(const NostrFilter(kinds: [1])), isFalse);
      expect(m(NostrFilter(authors: [_event.pubkey])), isTrue);
      expect(m(const NostrFilter(authors: ['other'])), isFalse);
      expect(m(NostrFilter(ids: [_event.id])), isTrue);
      expect(
        m(
          const NostrFilter(
            tags: {
              'd': ['x', 'topic'],
            },
          ),
        ),
        isTrue,
      );
      expect(
        m(
          const NostrFilter(
            tags: {
              'd': ['x'],
            },
          ),
        ),
        isFalse,
      );
      expect(
        m(
          const NostrFilter(
            tags: {
              'p': ['topic'],
            },
          ),
        ),
        isFalse,
      );
      expect(m(const NostrFilter(since: 1792000000)), isTrue);
      expect(m(const NostrFilter(since: 1792000001)), isFalse);
      expect(m(const NostrFilter(until: 1792000000)), isTrue);
      expect(m(const NostrFilter(until: 1791999999)), isFalse);
      expect(m(const NostrFilter(limit: 0)), isTrue);
      expect(
        nostrFiltersMatch(const [
          NostrFilter(kinds: [1]),
          NostrFilter(since: 1),
        ], _event),
        isTrue,
      );
      expect(nostrFiltersMatch(const [], _event), isFalse);
    });

    test('json round trip; malformed → null', () {
      const f = NostrFilter(
        ids: ['i'],
        authors: ['a'],
        kinds: [1, 2],
        tags: {
          'd': ['t'],
        },
        since: 1,
        until: 2,
        limit: 3,
      );
      final back = NostrFilter.tryParse(jsonDecode(jsonEncode(f.toJson())));
      expect(back!.toJson(), f.toJson());
      expect(f.withSince(9).toJson()['since'], 9);
      expect(f.withSince(9).toJson()['#d'], ['t']);
      for (final bad in [
        'x',
        {'kinds': '1'},
        {
          'kinds': ['1'],
        },
        {
          '#d': [1],
        },
        {'since': 1.5},
      ]) {
        expect(NostrFilter.tryParse(bad), isNull, reason: '$bad');
      }
    });
  });
}
