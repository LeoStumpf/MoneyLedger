import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/link/link_envelope.dart';
import 'package:money_ledger/core/link/nostr/nostr_event.dart';
import 'package:money_ledger/core/link/nostr/nostr_frames.dart';
import 'package:money_ledger/core/link/nostr/nostr_relay_pool.dart';
import 'package:money_ledger/core/link/nostr/relay_connection.dart';

import '../../helpers/fake_relay_network.dart';
import '../../helpers/manual_timers.dart';

const _a = 'wss://a.example';
const _b = 'wss://b.example';
const _now = 1792000000;

final _keyA = '${'00' * 31}03';
final _keyB = '${'00' * 31}05';
final _keyC = '${'00' * 31}07';

const _topic = 'topic-1';

// Distinct timeouts, so a test fires exactly the timer it means.
const _connectT = Duration(seconds: 3);
const _okT = Duration(seconds: 7);
const _fetchT = Duration(seconds: 11);

NostrEvent _ev(
  String key, {
  int at = _now,
  String d = _topic,
  String content = '1:AAAA',
  int? expiration,
}) => signNostrEvent(
  privateKey: key,
  kind: kLinkEventKind,
  tags: [
    ['d', d],
    ['expiration', '${expiration ?? _now + 30 * 86400}'],
  ],
  content: content,
  createdAt: at,
);

const _filter = [
  NostrFilter(
    kinds: [kLinkEventKind],
    tags: {
      'd': [_topic],
    },
  ),
];

/// A [Random] without jitter (backoff delays become exact).
class _NoJitter implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}

void main() {
  late FakeRelayNetwork net;
  late List<NostrRelayPool> pools;

  NostrRelayPool pool({
    List<String> relays = const [_a, _b],
    ManualTimers? timers,
    RelayConnector? connector,
    bool verifySignatures = true,
    int maxEventBytes = kNostrMaxEventBytes,
  }) {
    final p = NostrRelayPool(
      relays: relays,
      connector: connector ?? net,
      timers: timers?.call ?? Timer.new,
      verifySignatures: verifySignatures,
      maxEventBytes: maxEventBytes,
      connectTimeout: _connectT,
      okTimeout: _okT,
      fetchTimeout: _fetchT,
      random: _NoJitter(),
      nowSeconds: () => _now,
    );
    pools.add(p);
    return p;
  }

  setUp(() {
    net = FakeRelayNetwork(nowSeconds: () => _now);
    pools = [];
  });

  tearDown(() async {
    for (final p in pools) {
      await p.close();
    }
  });

  List<NostrPublishStatus> statuses(List<NostrPublishResult> r) => [
    for (final x in r) x.status,
  ];

  group('publish', () {
    test('every relay answers OK true', () async {
      final p = pool();
      final e = _ev(_keyA);
      final r = await p.publish(e);
      expect(r.map((x) => x.relay), [_a, _b]);
      expect(statuses(r), [
        NostrPublishStatus.accepted,
        NostrPublishStatus.accepted,
      ]);
      expect(r.every((x) => x.acceptedEquivalent), isTrue);
      expect(net.relay(_a).events.single.id, e.id);
      expect(net.relay(_b).events.single.id, e.id);
      expect(net.relay(_a).connectAttempts, 1);
      // A second publish reuses the connection.
      await p.publish(_ev(_keyA, at: _now + 1));
      expect(net.relay(_a).connectAttempts, 1);
    });

    test('duplicate and replaced are accepted-equivalent', () async {
      final p = pool(relays: [_a]);
      final v2 = _ev(_keyA, at: _now + 1, content: '1:v2');
      final v1 = _ev(_keyA, content: '1:v1');
      expect(statuses(await p.publish(v2)), [NostrPublishStatus.accepted]);
      final dup = await p.publish(v2);
      expect(statuses(dup), [NostrPublishStatus.duplicate]);
      final old = await p.publish(v1);
      expect(statuses(old), [NostrPublishStatus.replaced]);
      expect(old.single.message, 'replaced: have newer event');
      expect(old.single.acceptedEquivalent, isTrue);
      expect(net.relay(_a).events.single.id, v2.id);
    });

    test('same second: the lowest id wins (NIP-01)', () async {
      final p = pool(relays: [_a]);
      final x = _ev(_keyA, content: '1:x');
      final y = _ev(_keyA, content: '1:y');
      final (low, high) = x.id.compareTo(y.id) < 0 ? (x, y) : (y, x);
      await p.publish(high);
      expect(statuses(await p.publish(low)), [NostrPublishStatus.accepted]);
      expect(statuses(await p.publish(high)), [NostrPublishStatus.replaced]);
      expect(net.relay(_a).events.single.id, low.id);
    });

    test('other authors / topics don\'t replace each other', () async {
      final p = pool(relays: [_a]);
      await p.publish(_ev(_keyA));
      await p.publish(_ev(_keyB));
      await p.publish(_ev(_keyA, d: 'other'));
      expect(net.relay(_a).events, hasLength(3));
    });

    test('typed failures per relay', () async {
      net.relay(_a).rejectWith = 'rate-limited: slow down';
      net.relay(_b).rejectWith = 'blocked: not welcome';
      final r = await pool().publish(_ev(_keyA));
      expect(statuses(r), [
        NostrPublishStatus.rateLimited,
        NostrPublishStatus.blocked,
      ]);
      expect(r.first.message, 'rate-limited: slow down');
      expect(r.any((x) => x.acceptedEquivalent), isFalse);
    });

    test('relay size cap → invalid: event too large', () async {
      net.relay(_a).maxEventBytes = 500;
      final r = await pool().publish(_ev(_keyA, content: '1:${'A' * 600}'));
      expect(statuses(r), [
        NostrPublishStatus.invalid,
        NostrPublishStatus.accepted,
      ]);
      expect(r.first.message, startsWith('invalid: event too large: '));
    });

    test('an event over the cap is never sent', () async {
      final p = pool();
      final big = _ev(_keyA, content: '1:${'A' * kNostrMaxEventBytes}');
      final r = await p.publish(big);
      expect(statuses(r), [
        NostrPublishStatus.tooLarge,
        NostrPublishStatus.tooLarge,
      ]);
      expect(net.relay(_a).received, isEmpty);
      expect(net.relay(_a).connectAttempts, 0);

      // Exactly at the cap is fine.
      final base = _ev(_keyA, content: '1:').jsonBytes;
      final fit = _ev(
        _keyA,
        at: _now + 1,
        content: '1:${'A' * (kNostrMaxEventBytes - base)}',
      );
      expect(fit.jsonBytes, kNostrMaxEventBytes);
      expect(statuses(await p.publish(fit)), [
        NostrPublishStatus.accepted,
        NostrPublishStatus.accepted,
      ]);
    });

    test('a smaller pool cap applies too', () async {
      final r = await pool(maxEventBytes: 300).publish(_ev(_keyA));
      expect(statuses(r).toSet(), {NostrPublishStatus.tooLarge});
    });

    test('expired and forged events are refused by the relay', () async {
      net.relay(_a).verifySignatures = true;
      final p = pool(relays: [_a]);
      expect(statuses(await p.publish(_ev(_keyA, expiration: _now))), [
        NostrPublishStatus.invalid,
      ]);
      final e = _ev(_keyA);
      final forged = NostrEvent(
        id: e.id,
        pubkey: e.pubkey,
        createdAt: e.createdAt,
        kind: e.kind,
        tags: e.tags,
        content: e.content,
        sig: '00' * 64,
      );
      final r = await p.publish(forged);
      expect(r.single.message, 'invalid: bad signature');
    });

    test('offline relay → offline; the other still accepts', () async {
      net.relay(_a).offline = true;
      final r = await pool().publish(_ev(_keyA));
      expect(statuses(r), [
        NostrPublishStatus.offline,
        NostrPublishStatus.accepted,
      ]);
    });

    test('no OK → timeout (manual timer)', () async {
      net.relay(_a).silent = true;
      final timers = ManualTimers();
      final p = pool(relays: [_a], timers: timers);
      final f = p.publish(_ev(_keyA));
      await net.settle();
      expect(net.relay(_a).eventFrames, hasLength(1));
      expect(timers.fireWhere(_okT), 1);
      final r = await f;
      expect(statuses(r), [NostrPublishStatus.timeout]);
    });

    test('connect timeout → offline', () async {
      final timers = ManualTimers();
      final p = pool(relays: [_a], timers: timers, connector: _NeverConnects());
      final f = p.publish(_ev(_keyA));
      await pumpEventQueue();
      expect(timers.fireWhere(_connectT), 1);
      final r = await f;
      expect(statuses(r), [NostrPublishStatus.offline]);
    });

    test('connection dropped before the OK → offline', () async {
      net.relay(_a).dropOnNextEvent = true;
      final r = await pool(relays: [_a]).publish(_ev(_keyA));
      expect(statuses(r), [NostrPublishStatus.offline]);
      expect(r.single.message, 'connection lost');
    });

    test('a closed pool publishes nothing', () async {
      final p = pool();
      await p.close();
      final r = await p.publish(_ev(_keyA));
      expect(statuses(r).toSet(), {NostrPublishStatus.offline});
      expect(net.relay(_a).connectAttempts, 0);
    });
  });

  group('fetchOnce', () {
    test('dedups across relays; all authors of a topic', () async {
      final writer = pool();
      final ea = _ev(_keyA);
      final eb = _ev(_keyB);
      await writer.publish(ea);
      await writer.publish(eb);
      net.relay(_b).store(_ev(_keyC));
      net.relay(_a).store(_ev(_keyA, d: 'unrelated'));

      final reader = pool();
      final r = await reader.fetchOnce(_filter);
      expect(r.complete, isTrue);
      expect(r.events.map((e) => e.pubkey).toSet(), {
        nostrPublicKey(_keyA),
        nostrPublicKey(_keyB),
        nostrPublicKey(_keyC),
      });
      expect(r.events, hasLength(3));
      expect(r.seenOn[ea.id], {_a, _b});
      expect(r.seenOn[eb.id], {_a, _b});
      // The REQ was closed again after EOSE.
      expect(net.relay(_a).closes, hasLength(1));
      expect(net.relay(_a).openSubscriptions, isEmpty);
    });

    test('keeps the newest per address when relays disagree', () async {
      final old = _ev(_keyA, content: '1:old');
      final newer = _ev(_keyA, at: _now + 5, content: '1:new');
      net.relay(_a).store(old);
      net.relay(_b).store(newer);
      final r = await pool().fetchOnce(_filter);
      expect(r.events.single.id, newer.id);
      expect(r.seenOn[old.id], {_a});
      expect(r.seenOn[newer.id], {_b});
    });

    test('drops expired, wrong-id and (natively) forged events', () async {
      final good = _ev(_keyA);
      final expired = _ev(_keyB, expiration: _now - 1);
      final e = _ev(_keyC);
      NostrEvent copy({String? id, String? sig}) => NostrEvent(
        id: id ?? e.id,
        pubkey: e.pubkey,
        createdAt: e.createdAt,
        kind: e.kind,
        tags: e.tags,
        content: e.content,
        sig: sig ?? e.sig,
      );
      final forged = copy(sig: '00' * 64);
      final wrongId = copy(id: 'ab' * 32);
      final relay = net.relay(_a);
      relay.store(good);
      relay.store(forged);
      var r = await pool(relays: [_a]).fetchOnce(_filter);
      expect(r.events.map((e) => e.id), [good.id]);

      // Web policy: the signature isn't checked, the id still is.
      r = await pool(relays: [_a], verifySignatures: false).fetchOnce(_filter);
      expect(r.events.map((e) => e.id).toSet(), {good.id, forged.id});

      // On the wire (a relay ignoring NIP-40 / sending junk): an expired
      // event, a wrong id, one outside the filter — all dropped.
      final timers = ManualTimers();
      final p = pool(relays: [_a], timers: timers, verifySignatures: false);
      relay.silent = true;
      final f = p.fetchOnce(_filter);
      await net.settle();
      final sub = relay.reqs.last[1] as String;
      for (final x in [expired, wrongId, _ev(_keyA, d: 'elsewhere')]) {
        relay.sendRaw(jsonEncode(['EVENT', sub, x.toJson()]));
      }
      await net.settle();
      expect(timers.fireWhere(_fetchT), 1);
      r = await f;
      expect(r.relays[_a], NostrFetchRelayStatus.timeout);
      expect(r.events.map((e) => e.id).toSet(), {good.id, forged.id});
    });

    test(
      'a forged copy on one relay doesn\'t shadow the genuine event',
      () async {
        final e = _ev(_keyA);
        final forged = NostrEvent(
          id: e.id,
          pubkey: e.pubkey,
          createdAt: e.createdAt,
          kind: e.kind,
          tags: e.tags,
          content: e.content,
          sig: '11' * 64,
        );
        net.relay(_a).store(forged);
        net.relay(_b).store(e);
        final p = pool();
        final r = await p.fetchOnce(_filter);
        expect(r.events.single.sig, e.sig);
        expect(r.seenOn[e.id], {_b});

        final sub = p.subscribe(_filter);
        final got = <NostrReceivedEvent>[];
        sub.events.listen(got.add);
        await net.settle();
        expect(got.single.relay, _b);
        expect(got.single.event.sig, e.sig);
      },
    );

    test('per-relay outcomes: offline, CLOSED, timeout', () async {
      net.relay(_a).offline = true;
      final ev = _ev(_keyA);
      net.relay(_b).store(ev);
      var r = await pool().fetchOnce(_filter);
      expect(r.relays, {
        _a: NostrFetchRelayStatus.offline,
        _b: NostrFetchRelayStatus.eose,
      });
      expect(r.complete, isFalse);
      expect(r.anyComplete, isTrue);
      expect(r.events.single.id, ev.id);

      net.relay(_a).offline = false;
      net.relay(_a).closeSubscriptionsWith = 'error: shutting down';
      r = await pool().fetchOnce(_filter);
      expect(r.relays[_a], NostrFetchRelayStatus.closed);

      net.relay(_a).closeSubscriptionsWith = null;
      net.relay(_a).silent = true;
      final timers = ManualTimers();
      final p = pool(timers: timers);
      final f = p.fetchOnce(_filter);
      await net.settle();
      expect(timers.fireWhere(_fetchT), 1); // b is already done
      r = await f;
      expect(r.relays[_a], NostrFetchRelayStatus.timeout);
      expect(r.relays[_b], NostrFetchRelayStatus.eose);
      await net.settle();
      expect(net.relay(_a).closes, hasLength(1));
      expect(net.relay(_a).openSubscriptions, isEmpty);
    });

    test('limit and since are honoured by the fake', () async {
      for (var i = 0; i < 4; i++) {
        net.relay(_a).store(_ev(_keyA, d: 'd$i', at: _now - i));
      }
      final p = pool(relays: [_a]);
      var r = await p.fetchOnce(const [
        NostrFilter(kinds: [kLinkEventKind], limit: 2),
      ]);
      expect(r.events.map((e) => e.dTag), ['d0', 'd1']);
      r = await p.fetchOnce(const [
        NostrFilter(kinds: [kLinkEventKind], since: _now - 2, until: _now - 1),
      ]);
      expect(r.events.map((e) => e.dTag), ['d1', 'd2']);
    });

    test('a stored event expires on the relay', () async {
      var now = _now;
      net.nowSeconds = () => now;
      net.relay(_a).store(_ev(_keyA, expiration: _now + 600));
      expect(net.relay(_a).events, hasLength(1));
      now = _now + 600;
      expect(net.relay(_a).events, isEmpty);
    });
  });

  group('subscribe', () {
    test('live events, deduped across relays', () async {
      final reader = pool();
      final sub = reader.subscribe(_filter);
      final got = <NostrReceivedEvent>[];
      sub.events.listen(got.add);
      await net.settle();
      expect(net.relay(_a).openSubscriptions, [sub.id]);

      final writer = pool();
      final e = _ev(_keyB);
      await writer.publish(e);
      await writer.publish(_ev(_keyB, d: 'not-mine'));
      await net.settle();
      expect(got.map((x) => x.event.id), [e.id]);

      await sub.close();
      await net.settle();
      expect(net.relay(_a).openSubscriptions, isEmpty);
      expect(net.relay(_b).closes.single[1], sub.id);
    });

    test('stored events first, buffered until listened', () async {
      final stored = _ev(_keyA);
      net.relay(_a).store(stored);
      final sub = pool().subscribe(_filter);
      await net.settle();
      expect((await sub.events.first).event.id, stored.id);
    });

    test('update re-issues the REQ under the same id', () async {
      final p = pool(relays: [_a]);
      final sub = p.subscribe(_filter);
      final got = <String>[];
      sub.events.listen((x) => got.add(x.event.dTag));
      await net.settle();
      sub.update(const [
        NostrFilter(
          kinds: [kLinkEventKind],
          tags: {
            'd': [_topic, 'topic-2'],
          },
        ),
      ]);
      await net.settle();
      expect(net.relay(_a).reqs, hasLength(2));
      expect(net.relay(_a).reqs.last[1], sub.id);
      await pool(relays: [_a]).publish(_ev(_keyB, d: 'topic-2'));
      await net.settle();
      expect(got, ['topic-2']);
    });

    test('malformed frames are ignored, the subscription survives', () async {
      final p = pool(relays: [_a]);
      final sub = p.subscribe(_filter);
      final got = <String>[];
      sub.events.listen((x) => got.add(x.event.id));
      await net.settle();
      final relay = net.relay(_a);
      for (final f in [
        'garbage',
        '[]',
        '["EVENT","${sub.id}",{"id":"nope"}]',
        '["AUTH","challenge"]',
        '["OK","unknown-id",true,""]',
        '["EOSE","unknown-sub"]',
        '["CLOSED","unknown-sub","x"]',
        '["NOTICE","hello"]',
        '{"not":"a list"}',
      ]) {
        relay.sendRaw(f);
      }
      await net.settle();
      final e = _ev(_keyB);
      await pool(relays: [_a]).publish(e);
      await net.settle();
      expect(got, [e.id]);
      expect(p.isConnected(_a), isTrue);
    });

    test('reconnects with backoff and re-subscribes with since', () async {
      final timers = ManualTimers();
      final p = pool(relays: [_a], timers: timers);
      final relay = net.relay(_a);
      relay.store(_ev(_keyA, at: _now - 1000));
      final sub = p.subscribe(_filter);
      final got = <String>[];
      sub.events.listen((x) => got.add(x.event.pubkey));
      await net.settle();
      expect(got, hasLength(1));

      relay.offline = true;
      relay.dropConnections();
      await net.settle();
      expect(p.isConnected(_a), isFalse);
      // 2 s → 4 s → 8 s while the relay stays offline.
      for (final s in [2, 4, 8]) {
        expect(timers.fireWhere(Duration(seconds: s)), 1, reason: '$s s');
        await net.settle();
      }
      expect(timers.pendingWith(const Duration(seconds: 16)), hasLength(1));

      // Something arrives while we're away.
      relay.offline = false;
      final missed = _ev(_keyB);
      relay.store(missed);
      expect(timers.fireWhere(const Duration(seconds: 16)), 1);
      await net.settle();
      expect(p.isConnected(_a), isTrue);
      expect(got, hasLength(2));
      final req = relay.reqs.last;
      expect(req[1], sub.id);
      expect((req[2] as Map)['since'], _now - 1000 - kLiveResubscribeOverlap);

      // The streak was reset by the new connection's first frame.
      relay.dropConnections();
      await net.settle();
      expect(timers.pendingWith(const Duration(seconds: 2)), hasLength(1));
    });

    test('backoff caps at 5 minutes', () async {
      final timers = ManualTimers();
      final p = pool(relays: [_a], timers: timers);
      net.relay(_a).offline = true;
      p.subscribe(_filter);
      await net.settle();
      final delays = <int>[];
      for (var i = 0; i < 10; i++) {
        final t = timers.pending.single;
        delays.add(t.duration.inSeconds);
        t.fire();
        await net.settle();
      }
      expect(delays, [2, 4, 8, 16, 32, 64, 128, 256, 300, 300]);
    });

    test('offline + connectionChanges + reconnectNow (DEV-J)', () async {
      final timers = ManualTimers();
      final p = pool(timers: timers);
      var changes = 0;
      p.connectionChanges.listen((_) => changes++);
      expect(p.offline, isFalse, reason: 'nothing tried yet');
      p.subscribe(_filter);
      await net.settle();
      expect(p.offline, isFalse);
      // One relay drops: not offline while the other is connected.
      net.relay(_a).offline = true;
      net.relay(_a).dropConnections();
      await net.settle();
      expect(p.offline, isFalse);
      net.relay(_b).offline = true;
      net.relay(_b).dropConnections();
      await net.settle();
      expect(p.offline, isTrue);
      expect(changes, greaterThanOrEqualTo(2));
      // Back: reconnectNow doesn't wait for the backoff timers.
      net.relay(_a).offline = false;
      net.relay(_b).offline = false;
      final pendingBefore = timers.pending.length;
      expect(pendingBefore, greaterThan(0));
      p.reconnectNow();
      await net.settle();
      expect(p.isConnected(_a), isTrue);
      expect(p.isConnected(_b), isTrue);
      expect(p.offline, isFalse);
    });

    test('no reconnect without live subscriptions', () async {
      final timers = ManualTimers();
      final p = pool(relays: [_a], timers: timers);
      final sub = p.subscribe(_filter);
      await net.settle();
      await sub.close();
      net.relay(_a).dropConnections();
      await net.settle();
      expect(timers.pending, isEmpty);
      // A publish connects on demand.
      final r = await p.publish(_ev(_keyA));
      expect(statuses(r), [NostrPublishStatus.accepted]);
    });

    test('close stops everything', () async {
      final timers = ManualTimers();
      final p = pool(relays: [_a], timers: timers);
      final sub = p.subscribe(_filter);
      final done = Completer<void>();
      sub.events.listen(null, onDone: done.complete);
      await net.settle();
      net.relay(_a).offline = true;
      net.relay(_a).dropConnections();
      await net.settle();
      expect(timers.pending, hasLength(1));
      await p.close();
      await done.future;
      expect(sub.isClosed, isTrue);
      expect(timers.pending, isEmpty);
      expect(p.subscribe(_filter).isClosed, isTrue);
    });
  });

  test('newestPerAddress keeps regular events and the newest version', () {
    final a1 = _ev(_keyA, content: '1:a');
    final a2 = _ev(_keyA, at: _now + 1, content: '1:b');
    final note = signNostrEvent(
      privateKey: _keyB,
      kind: 1,
      tags: const [],
      content: 'hi',
      createdAt: _now - 5,
    );
    final out = newestPerAddress([a1, note, a2, note]);
    expect(out.map((e) => e.id), [a2.id, note.id]);
  });
}

class _NeverConnects implements RelayConnector {
  @override
  Future<Never> connect(String url) => Completer<Never>().future;
}
