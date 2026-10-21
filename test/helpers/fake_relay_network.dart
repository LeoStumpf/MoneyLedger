import 'dart:async';
import 'dart:convert';

import 'package:money_ledger/core/link/nostr/nostr_event.dart';
import 'package:money_ledger/core/link/nostr/nostr_frames.dart';
import 'package:money_ledger/core/link/nostr/relay_connection.dart';

/// G52: in-memory Nostr relays behind the [RelayConnector] port — what
/// `NostrRelayPool` talks to in tests (never a real relay).
///
/// Each [FakeRelay] behaves like the default relays (strfry, G51 §16):
/// - **addressable / replaceable** kinds keep one event per address — newest
///   `created_at`, tie → lowest id; the loser gets
///   `OK false "replaced: have newer event"` (also an older `created_at`);
///   a stored id again → `OK true "duplicate: …"`;
/// - **NIP-40**: an expired event is refused (`invalid: event is expired`),
///   a stored one stops being served once [FakeRelayNetwork.nowSeconds]
///   passes its `expiration`;
/// - **size**: event JSON over [FakeRelay.maxEventBytes] →
///   `invalid: event too large: <n>`;
/// - **checks**: a wrong id → `invalid: bad event id`; with
///   [FakeRelay.verifySignatures] a bad signature → `invalid: bad signature`;
/// - **filters**: `ids`, `kinds`, `authors`, `#<tag>`, `since`, `until`,
///   `limit` (newest first) for stored events, then `EOSE`; stored events are
///   delivered live to every open matching subscription (the publisher's
///   own too).
///
/// - **NIP-09**: a kind-5 event's `a` tags (`kind:pubkey:d`, its own
///   pubkey) delete the stored event at that address up to its `created_at`
///   ([FakeRelay.deleted]); the deletion event itself is stored.
///
/// Injected failures: [FakeRelay.offline] (connect throws),
/// [FakeRelay.rejectWith] (every publish → `OK false <message>`, e.g.
/// `rate-limited: …`, `blocked: …`), [FakeRelay.silent] (no `OK` / `EOSE`
/// — timeouts), [FakeRelay.closeSubscriptionsWith] (`CLOSED` instead of
/// stored events), [FakeRelay.dropConnections] / [FakeRelay.dropOnNextEvent],
/// [FakeRelay.sendRaw] (malformed frames), [FakeRelay.store] (an event
/// placed directly, e.g. forged or expired).
///
/// Frames travel asynchronously (microtasks); [FakeRelayNetwork.settle]
/// waits until nothing moved for a few ticks (like
/// `FakeMatrixNetwork.settle()`).
class FakeRelayNetwork implements RelayConnector {
  /// The relays' clock (seconds) for NIP-40.
  int Function() nowSeconds;

  final Map<String, FakeRelay> _relays = {};
  int _activity = 0;

  FakeRelayNetwork({int Function()? nowSeconds})
    : nowSeconds =
          nowSeconds ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);

  /// The relay at [url] (created on first use).
  FakeRelay relay(String url) =>
      _relays.putIfAbsent(url, () => FakeRelay._(this, url));

  @override
  Future<RelayConnection> connect(String url) async {
    _bump();
    await Future<void>.delayed(Duration.zero);
    final r = relay(url);
    r.connectAttempts++;
    if (r.offline) throw StateError('fake relay $url is offline');
    final c = _FakeConnection(r);
    r._conns.add(c);
    return c;
  }

  void _bump() => _activity++;

  /// Waits until no frame was sent or delivered for [quietTicks] consecutive
  /// 2 ms ticks.
  Future<void> settle({
    int quietTicks = 5,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final sw = Stopwatch()..start();
    var seen = _activity;
    var quiet = 0;
    while (quiet < quietTicks) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (_activity != seen) {
        seen = _activity;
        quiet = 0;
      } else {
        quiet++;
      }
      if (sw.elapsed > timeout) {
        throw TimeoutException('fake relays never went quiet', timeout);
      }
    }
  }
}

/// One in-memory relay (see [FakeRelayNetwork]).
class FakeRelay {
  final FakeRelayNetwork _net;
  final String url;

  /// Connect attempts throw.
  bool offline = false;

  /// Every publish is answered `OK false <rejectWith>`.
  String? rejectWith;

  /// Never answers `OK` or `EOSE` (stored events are still sent).
  bool silent = false;

  /// Answers every `REQ` with `CLOSED <message>` (and stores nothing for it).
  String? closeSubscriptionsWith;

  /// Drops every connection when the next `EVENT` frame arrives (before
  /// answering it).
  bool dropOnNextEvent = false;

  /// Checks BIP-340 signatures of published events (ids are always checked).
  bool verifySignatures = false;

  /// strfry's event size cap (G51).
  int maxEventBytes = kNostrMaxEventBytes;

  int connectAttempts = 0;

  /// Every client → relay frame, in arrival order.
  final List<String> received = [];

  /// Ids of events removed by a NIP-09 deletion request.
  final List<String> deleted = [];

  final Map<String, NostrEvent> _stored = {};
  final List<_FakeConnection> _conns = [];

  FakeRelay._(this._net, this.url);

  /// The stored, unexpired events (newest first).
  List<NostrEvent> get events {
    final now = _net.nowSeconds();
    return [
      for (final e in _stored.values)
        if (!e.isExpiredAt(now)) e,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Open connections.
  int get connectionCount => _conns.length;

  /// `REQ` frames received.
  List<List<dynamic>> get reqs => _framesOf('REQ');

  /// `CLOSE` frames received.
  List<List<dynamic>> get closes => _framesOf('CLOSE');

  /// `EVENT` frames received.
  List<List<dynamic>> get eventFrames => _framesOf('EVENT');

  /// Open subscription ids (over all connections).
  List<String> get openSubscriptions => [
    for (final c in _conns) ...c._subs.keys,
  ];

  List<List<dynamic>> _framesOf(String type) => [
    for (final f in received)
      if (jsonDecode(f) case final List<dynamic> l
          when l.isNotEmpty && l[0] == type)
        l,
  ];

  /// Stores [event] as if accepted (no checks — forged / expired events
  /// welcome) and delivers it to matching live subscriptions.
  void store(NostrEvent event) {
    _stored[event.address ?? event.id] = event;
    _deliver(event);
  }

  /// Sends a raw frame to every connection.
  void sendRaw(String frame) {
    for (final c in [..._conns]) {
      c._out(frame);
    }
  }

  /// Closes every connection (the clients see their stream end).
  void dropConnections() {
    for (final c in [..._conns]) {
      c._drop();
    }
  }

  void _deliver(NostrEvent event) {
    if (event.isExpiredAt(_net.nowSeconds())) return;
    for (final c in [..._conns]) {
      for (final s in c._subs.entries) {
        if (nostrFiltersMatch(s.value, event)) {
          c._out(jsonEncode(['EVENT', s.key, event.toJson()]));
        }
      }
    }
  }

  void _onFrame(_FakeConnection c, String frame) {
    received.add(frame);
    final Object? json;
    try {
      json = jsonDecode(frame);
    } catch (_) {
      c._out(jsonEncode(['NOTICE', 'error: bad json']));
      return;
    }
    if (json is! List || json.isEmpty) {
      c._out(jsonEncode(['NOTICE', 'error: bad message']));
      return;
    }
    switch (json[0]) {
      case 'EVENT':
        if (dropOnNextEvent) {
          dropOnNextEvent = false;
          dropConnections();
          return;
        }
        _onEvent(c, json.length > 1 ? json[1] : null);
      case 'REQ':
        if (json.length < 2 || json[1] is! String) return;
        final sub = json[1] as String;
        final filters = <NostrFilter>[];
        for (final f in json.skip(2)) {
          final parsed = NostrFilter.tryParse(f);
          if (parsed == null) {
            c._out(jsonEncode(['CLOSED', sub, 'invalid: bad filter']));
            return;
          }
          filters.add(parsed);
        }
        if (closeSubscriptionsWith != null) {
          c._out(jsonEncode(['CLOSED', sub, closeSubscriptionsWith]));
          return;
        }
        c._subs[sub] = filters;
        final sent = <String>{};
        for (final f in filters) {
          var matching = events.where(f.matches);
          if (f.limit != null) matching = matching.take(f.limit!);
          for (final e in matching) {
            if (sent.add(e.id)) {
              c._out(jsonEncode(['EVENT', sub, e.toJson()]));
            }
          }
        }
        if (!silent) c._out(jsonEncode(['EOSE', sub]));
      case 'CLOSE':
        if (json.length > 1) c._subs.remove(json[1]);
      default:
        c._out(jsonEncode(['NOTICE', 'error: unknown message']));
    }
  }

  void _onEvent(_FakeConnection c, Object? raw) {
    final event = NostrEvent.tryParse(raw);
    if (event == null) {
      c._out(jsonEncode(['NOTICE', 'invalid: malformed event']));
      return;
    }
    void ok(bool accepted, String message) {
      if (!silent) c._out(jsonEncode(['OK', event.id, accepted, message]));
    }

    if (!nostrEventIdValid(event)) return ok(false, 'invalid: bad event id');
    if (verifySignatures && !verifyBip340(event.pubkey, event.id, event.sig)) {
      return ok(false, 'invalid: bad signature');
    }
    final size = event.jsonBytes;
    if (size > maxEventBytes) {
      return ok(false, 'invalid: event too large: $size');
    }
    if (event.isExpiredAt(_net.nowSeconds())) {
      return ok(false, 'invalid: event is expired');
    }
    if (rejectWith != null) return ok(false, rejectWith!);
    if (event.kind == 5) _applyDeletion(event);
    final key = event.address ?? event.id;
    final current = _stored[key];
    if (current != null && current.id == event.id) {
      return ok(true, 'duplicate: have this event');
    }
    if (current != null && nostrEventIsNewer(current, event)) {
      return ok(false, 'replaced: have newer event');
    }
    _stored[key] = event;
    ok(true, '');
    _deliver(event);
  }
}

extension on FakeRelay {
  /// NIP-09: an `a` tag `kind:pubkey:d` of the deletion's own pubkey deletes
  /// the stored event at that address up to the deletion's `created_at`.
  void _applyDeletion(NostrEvent deletion) {
    for (final t in deletion.tags) {
      if (t.length < 2 || t[0] != 'a') continue;
      final parts = t[1].split(':');
      if (parts.length < 3 || parts[1] != deletion.pubkey) continue;
      final stored = _stored[t[1]];
      if (stored != null && stored.createdAt <= deletion.createdAt) {
        _stored.remove(t[1]);
        deleted.add(stored.id);
      }
    }
  }
}

class _FakeConnection implements RelayConnection {
  final FakeRelay _relay;
  final _controller = StreamController<String>();
  final Map<String, List<NostrFilter>> _subs = {};
  bool _open = true;

  _FakeConnection(this._relay);

  @override
  Stream<String> get frames => _controller.stream;

  @override
  void send(String frame) {
    if (!_open) return;
    _relay._net._bump();
    scheduleMicrotask(() {
      if (_open) _relay._onFrame(this, frame);
    });
  }

  void _out(String frame) {
    if (!_open) return;
    _relay._net._bump();
    _controller.add(frame);
  }

  void _drop() {
    if (!_open) return;
    _open = false;
    _relay._conns.remove(this);
    _relay._net._bump();
    unawaited(_controller.close());
  }

  @override
  Future<void> close() async => _drop();
}
