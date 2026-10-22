/// G52 step 2: a small NIP-01 relay pool — publish, live subscriptions,
/// one-shot fetch, reconnect with backoff (design doc
/// `docs/design/no-login-sharing.md` §4.3–§4.5).
///
/// - **publish** sends one event to every relay and returns one
///   [NostrPublishResult] per relay (`OK` classified by its NIP-01 prefix,
///   [NostrPublishStatus]; `replaced:` / `duplicate:` are accepted-equivalent,
///   [isAcceptedEquivalent]). An event whose JSON exceeds [maxEventBytes]
///   (default [kNostrMaxEventBytes], the relays' 65 536-byte cap) is never
///   sent ([NostrPublishStatus.tooLarge]).
/// - **subscribe** keeps a `REQ` open on every relay while the subscription
///   lives, re-issuing it after a reconnect with `since` = the newest
///   `created_at` that relay delivered minus [kLiveResubscribeOverlap].
/// - **fetchOnce** sends a `REQ`, waits for `EOSE` (or `CLOSED`, a drop, the
///   timeout) on every relay, `CLOSE`s, dedups by id and keeps only the
///   newest event per address (addressable / replaceable kinds — newest
///   `created_at`, tie → lowest id, NIP-01).
/// - **Inbound checks** (every event from a relay): it must match the
///   subscription's filters, not be expired (NIP-40), have a correct id, and
///   — only when [verifySignatures] (default [kVerifyNostrSignatures]: native
///   only, Leo 2026-10-17, §3.3) — a valid BIP-340 signature. Anything else is
///   dropped and logged.
/// - **Connections** open on demand (one per relay). While a live
///   subscription exists, a lost / failed connection is retried after
///   [reconnectMin] doubling to [reconnectMax] plus up to 20 % jitter; the
///   streak resets on the first valid frame of a new connection.
///
/// Every wait (connect, `OK`, `EOSE`, backoff) uses the injected
/// [TimerFactory] (CLAUDE.md "Timeouts/backoff in tests"). Malformed frames
/// are logged via `debugPrint` and ignored, never thrown out of the pool.
/// Publish rate limits / relay blocking policy (§4.4) are the caller's
/// (`LinkSyncEngine`, G52 step 5).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../timer_factory.dart';
import 'nostr_event.dart';
import 'nostr_frames.dart';
import 'relay_connection.dart';

/// The default relays of link groups (Leo 2026-10-17, §9.4 option C).
const kDefaultLinkRelays = ['wss://nos.lol', 'wss://nostr.mom'];

/// Whether inbound events get their BIP-340 signature checked: native only.
/// dart2js verifies at ≈ 170 ms per event (§16); on the web the AES-GCM AAD
/// (binds content to kind / topic / pubkey) and the relays' own checks
/// cover it (Leo 2026-10-17, §3.3). Event ids are checked everywhere.
const bool kVerifyNostrSignatures = !kIsWeb;

const kRelayConnectTimeout = Duration(seconds: 10);
const kRelayOkTimeout = Duration(seconds: 10);

/// §4.3: full fetch waits for `EOSE` up to 10 s per relay (incl. connecting).
const kRelayFetchTimeout = Duration(seconds: 10);

/// §4.3: reconnect backoff 2 s → 4 → … → 5 min, plus jitter.
const kRelayReconnectMin = Duration(seconds: 2);
const kRelayReconnectMax = Duration(minutes: 5);

/// §4.3: a re-issued live `REQ` overlaps the newest seen event by 60 s.
const kLiveResubscribeOverlap = 60;

/// How many event ids the pool / a subscription remembers for dedup and the
/// verification cache.
const _kRememberIds = 4096;

/// The answer of one relay to a publish.
class NostrPublishResult {
  final String relay;
  final NostrPublishStatus status;

  /// The relay's `OK` message (or a local reason).
  final String message;

  const NostrPublishResult(this.relay, this.status, this.message);

  /// The relay holds this event or a newer one for its address (§4.4).
  bool get acceptedEquivalent => isAcceptedEquivalent(status);

  @override
  String toString() => 'NostrPublishResult($relay, ${status.name}, $message)';
}

/// How a relay's part of a [NostrRelayPool.fetchOnce] ended.
enum NostrFetchRelayStatus {
  /// `EOSE`: the relay sent everything it holds.
  eose,

  /// `CLOSED` by the relay before `EOSE`.
  closed,

  /// No `EOSE` within the timeout.
  timeout,

  /// Couldn't connect, or the connection dropped.
  offline,
}

/// The result of [NostrRelayPool.fetchOnce].
class NostrFetchResult {
  /// Deduped events, newest per address, newest first.
  final List<NostrEvent> events;

  /// How each relay's fetch ended.
  final Map<String, NostrFetchRelayStatus> relays;

  /// Event id → the relays that served it (also for events dropped as an
  /// older version of an address).
  final Map<String, Set<String>> seenOn;

  const NostrFetchResult({
    required this.events,
    required this.relays,
    required this.seenOn,
  });

  /// Every relay answered with `EOSE`.
  bool get complete =>
      relays.values.every((s) => s == NostrFetchRelayStatus.eose);

  /// At least one relay answered with `EOSE`.
  bool get anyComplete => relays.values.contains(NostrFetchRelayStatus.eose);
}

/// An event a live subscription received, and from which relay (the first
/// one to deliver it — later copies are deduped).
class NostrReceivedEvent {
  final NostrEvent event;
  final String relay;
  const NostrReceivedEvent(this.event, this.relay);
}

/// Keeps the newest event per address (and every non-addressable one) —
/// NIP-01 replacement semantics, as a relay would store them.
List<NostrEvent> newestPerAddress(Iterable<NostrEvent> events) {
  final byId = <String, NostrEvent>{};
  final byAddress = <String, NostrEvent>{};
  for (final e in events) {
    final a = e.address;
    if (a == null) {
      byId[e.id] = e;
    } else {
      final cur = byAddress[a];
      if (cur == null || nostrEventIsNewer(e, cur)) byAddress[a] = e;
    }
  }
  return [...byId.values, ...byAddress.values]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

/// A NIP-01 relay pool (see the library doc).
class NostrRelayPool {
  final RelayConnector connector;
  final TimerFactory timers;
  final bool verifySignatures;
  final int maxEventBytes;
  final Duration connectTimeout;
  final Duration okTimeout;
  final Duration fetchTimeout;
  final Duration reconnectMin;
  final Duration reconnectMax;
  final Random _random;
  final int Function() _nowSeconds;

  late final List<_Relay> _relays;
  final List<NostrSubscription> _live = [];
  final _verified = _BoundedMap<String, bool>(_kRememberIds);
  var _subCounter = 0;
  final _connectionChanges = StreamController<void>.broadcast(sync: false);
  late final String _subPrefix =
      'ml${_random.nextInt(1 << 24).toRadixString(16)}';
  bool _closed = false;

  NostrRelayPool({
    List<String> relays = kDefaultLinkRelays,
    this.connector = const WebSocketRelayConnector(),
    this.timers = Timer.new,
    this.verifySignatures = kVerifyNostrSignatures,
    this.maxEventBytes = kNostrMaxEventBytes,
    this.connectTimeout = kRelayConnectTimeout,
    this.okTimeout = kRelayOkTimeout,
    this.fetchTimeout = kRelayFetchTimeout,
    this.reconnectMin = kRelayReconnectMin,
    this.reconnectMax = kRelayReconnectMax,
    Random? random,
    int Function()? nowSeconds,
  }) : _random = random ?? Random(),
       _nowSeconds =
           nowSeconds ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000) {
    _relays = [
      for (final url in {...relays}) _Relay(this, url),
    ];
  }

  /// The relay URLs, in order.
  List<String> get relays => [for (final r in _relays) r.url];

  /// Whether the pool currently holds an open connection to [relay].
  bool isConnected(String relay) =>
      _relays.any((r) => r.url == relay && r.conn != null);

  /// DEV-J: no relay is reachable — none holds an open connection and every
  /// one failed (connect error / timeout / dropped) since its last good
  /// connection. False before anything was tried.
  bool get offline =>
      !_closed && _relays.every((r) => r.conn == null && r._failures > 0);

  /// At least one relay holds an open connection.
  bool get anyConnected => !_closed && _relays.any((r) => r.conn != null);

  /// Fires when a connection opens, fails or drops ([offline] may have
  /// changed). Closed with the pool.
  Stream<void> get connectionChanges => _connectionChanges.stream;

  /// DEV-J: a relay without a connection that a live subscription wants is
  /// tried again **now** (the reconnect backoff is cut short) — e.g. when the
  /// app comes back to the foreground.
  void reconnectNow() {
    if (_closed) return;
    for (final r in _relays) {
      r.reconnectNow();
    }
  }

  void _connectionChanged() {
    if (!_connectionChanges.isClosed) _connectionChanges.add(null);
  }

  /// Publishes [event] to every relay — or only to those in [only] (G52
  /// step 5: relays the caller backs off / blocks are left out); one result
  /// per relay it went to, in [relays] order. Never throws.
  Future<List<NostrPublishResult>> publish(
    NostrEvent event, {
    Duration? timeout,
    Iterable<String>? only,
  }) async {
    final wanted = only?.toSet();
    final targets = [
      for (final r in _relays)
        if (wanted == null || wanted.contains(r.url)) r,
    ];
    final bytes = event.jsonBytes;
    if (bytes > maxEventBytes) {
      debugPrint('[nostr] not publishing ${event.id}: $bytes bytes');
      return [
        for (final r in targets)
          NostrPublishResult(
            r.url,
            NostrPublishStatus.tooLarge,
            'event too large: $bytes',
          ),
      ];
    }
    final frame = encodeEventFrame(event);
    return Future.wait([
      for (final r in targets) r.publish(event.id, frame, timeout ?? okTimeout),
    ]);
  }

  /// Opens a live subscription on every relay (see the library doc). Events
  /// are buffered until the stream is listened to.
  NostrSubscription subscribe(List<NostrFilter> filters) {
    final sub = NostrSubscription._(this, _nextSubId(), filters);
    if (_closed) {
      sub._closed = true;
      unawaited(sub._controller.close());
      return sub;
    }
    _live.add(sub);
    for (final r in _relays) {
      r.addLive(sub);
    }
    return sub;
  }

  /// Fetches the stored events matching [filters] from every relay (see the
  /// library doc). Never throws.
  Future<NostrFetchResult> fetchOnce(
    List<NostrFilter> filters, {
    Duration? timeout,
  }) async {
    final subId = _nextSubId();
    final parts = await Future.wait([
      for (final r in _relays) r.fetch(subId, filters, timeout ?? fetchTimeout),
    ]);
    final all = <NostrEvent>[];
    final seenOn = <String, Set<String>>{};
    final status = <String, NostrFetchRelayStatus>{};
    for (var i = 0; i < _relays.length; i++) {
      final url = _relays[i].url;
      status[url] = parts[i].$1;
      for (final e in parts[i].$2) {
        if ((seenOn[e.id] ??= {}).isEmpty) all.add(e);
        seenOn[e.id]!.add(url);
      }
    }
    return NostrFetchResult(
      events: newestPerAddress(all),
      relays: status,
      seenOn: seenOn,
    );
  }

  /// Closes every subscription and connection; the pool can't be used
  /// afterwards (publishes answer [NostrPublishStatus.offline]).
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final s in [..._live]) {
      await s.close();
    }
    await Future.wait([for (final r in _relays) r.shutdown()]);
    await _connectionChanges.close();
  }

  String _nextSubId() => '$_subPrefix-${_subCounter++}';

  /// The inbound checks shared by fetches and live subscriptions.
  bool _accept(String relay, List<NostrFilter> filters, NostrEvent event) {
    if (!nostrFiltersMatch(filters, event)) {
      debugPrint(
        '[nostr] $relay sent an event outside the filter: ${event.id}',
      );
      return false;
    }
    if (event.isExpiredAt(_nowSeconds())) return false;
    // Keyed by id + sig: a forged copy (right id, bad signature) sent first
    // must not shadow the genuine event.
    final key = '${event.id}:${event.sig}';
    final known = _verified[key];
    final ok =
        known ?? verifyNostrEvent(event, checkSignature: verifySignatures);
    if (known == null) _verified[key] = ok;
    if (!ok) debugPrint('[nostr] $relay sent an invalid event: ${event.id}');
    return ok;
  }

  Duration _backoff(int failures) {
    final steps = max(0, failures - 1);
    var ms = reconnectMin.inMilliseconds * pow(2, min(steps, 20));
    ms = min(ms, reconnectMax.inMilliseconds);
    final jitter = (ms * 0.2 * _random.nextDouble()).round();
    return Duration(milliseconds: ms.round() + jitter);
  }
}

/// A live subscription of a [NostrRelayPool].
class NostrSubscription {
  final NostrRelayPool _pool;

  /// The NIP-01 subscription id (the same on every relay).
  final String id;
  List<NostrFilter> _filters;
  final _controller = StreamController<NostrReceivedEvent>();
  final _seen = _BoundedMap<String, bool>(_kRememberIds);

  /// Newest `created_at` delivered per relay (for the re-subscribe `since`).
  final Map<String, int> _newest = {};
  bool _closed = false;

  NostrSubscription._(this._pool, this.id, this._filters);

  /// Deduped, checked events, in arrival order.
  Stream<NostrReceivedEvent> get events => _controller.stream;

  List<NostrFilter> get filters => List.unmodifiable(_filters);

  bool get isClosed => _closed;

  /// Replaces the filters (e.g. the group set changed): re-issues the `REQ`
  /// under the same id on every connected relay, without `since` (new topics
  /// need their stored events).
  void update(List<NostrFilter> filters) {
    if (_closed) return;
    _filters = filters;
    _newest.clear();
    for (final r in _pool._relays) {
      r.sendReq(this);
    }
  }

  /// Closes the subscription (`CLOSE` on every connected relay).
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pool._live.remove(this);
    for (final r in _pool._relays) {
      r.removeLive(this);
    }
    // Not awaited: an unlistened controller's close never completes.
    unawaited(_controller.close());
  }

  /// The filters to send to [relay]: `since` moved up to that relay's newest
  /// delivered event minus the overlap, after a reconnect.
  List<NostrFilter> _filtersFor(String relay) {
    final newest = _newest[relay];
    if (newest == null) return _filters;
    final floor = max(0, newest - kLiveResubscribeOverlap);
    return [
      for (final f in _filters)
        f.since != null && f.since! >= floor ? f : f.withSince(floor),
    ];
  }

  void _onEvent(String relay, NostrEvent event) {
    if (_closed || !_pool._accept(relay, _filters, event)) return;
    _newest[relay] = max(_newest[relay] ?? 0, event.createdAt);
    if (_seen.containsKey(event.id)) return;
    _seen[event.id] = true;
    _controller.add(NostrReceivedEvent(event, relay));
  }
}

/// Callbacks of one subscription id on one relay.
class _SubHandler {
  final void Function(NostrEvent) onEvent;
  final void Function() onEose;
  final void Function(String) onClosed;
  final void Function() onDisconnect;

  /// The live subscription (re-sent after a reconnect), or null for a fetch.
  final NostrSubscription? live;

  _SubHandler({
    required this.onEvent,
    required this.onEose,
    required this.onClosed,
    required this.onDisconnect,
    this.live,
  });
}

/// One relay of the pool: its connection, waiters and subscriptions.
class _Relay {
  final NostrRelayPool pool;
  final String url;
  RelayConnection? conn;
  StreamSubscription<String>? _frames;
  Future<bool>? _connecting;
  int _failures = 0;
  bool _gotValidFrame = false;
  Timer? _reconnect;
  final Map<String, List<void Function(RelayOkMessage?)>> _okWaiters = {};
  final Map<String, _SubHandler> _subs = {};

  _Relay(this.pool, this.url);

  bool get _wantsLive =>
      !pool._closed && _subs.values.any((h) => h.live != null);

  Future<bool> ensureConnected() {
    if (pool._closed) return Future.value(false);
    if (conn != null) return Future.value(true);
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<bool> _connect() async {
    _reconnect?.cancel();
    _reconnect = null;
    final RelayConnection c;
    try {
      c = await _openWithTimeout();
    } catch (e) {
      _failures++;
      debugPrint('[nostr] $url: connect failed ($e)');
      _scheduleReconnect();
      pool._connectionChanged();
      return false;
    }
    if (pool._closed) {
      unawaited(c.close());
      return false;
    }
    conn = c;
    _gotValidFrame = false;
    _frames = c.frames.listen(
      _onFrame,
      onDone: () => _onDisconnect(c),
      onError: (Object e) {
        debugPrint('[nostr] $url: connection error ($e)');
        _onDisconnect(c);
      },
      cancelOnError: true,
    );
    for (final h in [..._subs.values]) {
      if (h.live != null) sendReq(h.live!);
    }
    pool._connectionChanged();
    return true;
  }

  Future<RelayConnection> _openWithTimeout() {
    final done = Completer<RelayConnection>();
    final timer = pool.timers(pool.connectTimeout, () {
      if (!done.isCompleted) {
        done.completeError(TimeoutException('connect', pool.connectTimeout));
      }
    });
    pool.connector
        .connect(url)
        .then(
          (c) {
            timer.cancel();
            if (done.isCompleted) {
              unawaited(c.close()); // arrived after the timeout
            } else {
              done.complete(c);
            }
          },
          onError: (Object e) {
            timer.cancel();
            if (!done.isCompleted) done.completeError(e);
          },
        );
    return done.future;
  }

  void _onFrame(String frame) {
    final msg = parseRelayMessage(frame);
    if (msg == null) {
      final head = frame.length > 80 ? '${frame.substring(0, 80)}…' : frame;
      debugPrint('[nostr] $url: ignored frame $head');
      return;
    }
    if (!_gotValidFrame) {
      _gotValidFrame = true;
      _failures = 0;
    }
    switch (msg) {
      case RelayEventMessage(:final subscriptionId, :final event):
        _subs[subscriptionId]?.onEvent(event);
      case RelayOkMessage():
        final waiters = _okWaiters.remove(msg.eventId);
        if (waiters != null) {
          for (final w in waiters) {
            w(msg);
          }
        }
      case RelayEoseMessage(:final subscriptionId):
        _subs[subscriptionId]?.onEose();
      case RelayClosedMessage(:final subscriptionId, :final message):
        debugPrint('[nostr] $url: CLOSED $subscriptionId "$message"');
        _subs[subscriptionId]?.onClosed(message);
      case RelayNoticeMessage(:final message):
        debugPrint('[nostr] $url: NOTICE "$message"');
    }
  }

  void _onDisconnect(RelayConnection c) {
    if (!identical(conn, c)) return;
    conn = null;
    _frames = null;
    unawaited(c.close());
    final waiters = [..._okWaiters.values.expand((w) => w)];
    _okWaiters.clear();
    for (final w in waiters) {
      w(null);
    }
    for (final h in [..._subs.values]) {
      h.onDisconnect();
    }
    if (pool._closed) return;
    debugPrint('[nostr] $url: disconnected');
    _failures++;
    _scheduleReconnect();
    pool._connectionChanged();
  }

  void reconnectNow() {
    if (!_wantsLive || conn != null || _connecting != null) return;
    _reconnect?.cancel();
    _reconnect = null;
    unawaited(ensureConnected());
  }

  void _scheduleReconnect() {
    if (!_wantsLive || _reconnect != null || conn != null) return;
    final delay = pool._backoff(_failures);
    _reconnect = pool.timers(delay, () {
      _reconnect = null;
      if (_wantsLive) unawaited(ensureConnected());
    });
  }

  // ---------------------------------------------------------------- publish

  Future<NostrPublishResult> publish(
    String eventId,
    String frame,
    Duration timeout,
  ) async {
    final done = Completer<NostrPublishResult>();
    void finish(NostrPublishStatus s, String m) {
      if (!done.isCompleted) done.complete(NostrPublishResult(url, s, m));
    }

    final timer = pool.timers(
      timeout,
      () => finish(NostrPublishStatus.timeout, 'no OK'),
    );
    void onOk(RelayOkMessage? m) => m == null
        ? finish(NostrPublishStatus.offline, 'connection lost')
        : finish(classifyOk(m.accepted, m.message), m.message);

    final connected = await ensureConnected();
    final c = conn; // may have dropped again in between
    if (!connected || c == null) {
      finish(NostrPublishStatus.offline, 'not connected');
    } else if (!done.isCompleted) {
      (_okWaiters[eventId] ??= []).add(onOk);
      c.send(frame);
    }
    final result = await done.future;
    timer.cancel();
    final waiters = _okWaiters[eventId];
    waiters?.remove(onOk);
    if (waiters != null && waiters.isEmpty) _okWaiters.remove(eventId);
    return result;
  }

  // ------------------------------------------------------------------ fetch

  Future<(NostrFetchRelayStatus, List<NostrEvent>)> fetch(
    String subId,
    List<NostrFilter> filters,
    Duration timeout,
  ) async {
    final done = Completer<NostrFetchRelayStatus>();
    void finish(NostrFetchRelayStatus s) {
      if (!done.isCompleted) done.complete(s);
    }

    final events = <NostrEvent>[];
    final timer = pool.timers(
      timeout,
      () => finish(NostrFetchRelayStatus.timeout),
    );
    final handler = _SubHandler(
      onEvent: (e) {
        if (!done.isCompleted && pool._accept(url, filters, e)) events.add(e);
      },
      onEose: () => finish(NostrFetchRelayStatus.eose),
      onClosed: (_) => finish(NostrFetchRelayStatus.closed),
      onDisconnect: () => finish(NostrFetchRelayStatus.offline),
    );
    final connected = await ensureConnected();
    final c = conn;
    if (!connected || c == null) {
      finish(NostrFetchRelayStatus.offline);
    } else if (!done.isCompleted) {
      _subs[subId] = handler;
      c.send(encodeReqFrame(subId, filters));
    }
    final status = await done.future;
    timer.cancel();
    if (identical(_subs[subId], handler)) {
      _subs.remove(subId);
      if (status == NostrFetchRelayStatus.eose ||
          status == NostrFetchRelayStatus.timeout) {
        conn?.send(encodeCloseFrame(subId));
      }
    }
    return (status, events);
  }

  // ------------------------------------------------------------------- live

  void addLive(NostrSubscription sub) {
    _subs[sub.id] = _SubHandler(
      live: sub,
      onEvent: (e) => sub._onEvent(url, e),
      onEose: () {},
      onClosed: (_) {},
      onDisconnect: () {},
    );
    if (conn != null) {
      sendReq(sub);
    } else {
      unawaited(ensureConnected());
    }
  }

  void sendReq(NostrSubscription sub) {
    if (conn == null || _subs[sub.id]?.live != sub) return;
    conn!.send(encodeReqFrame(sub.id, sub._filtersFor(url)));
  }

  void removeLive(NostrSubscription sub) {
    if (_subs[sub.id]?.live != sub) return;
    _subs.remove(sub.id);
    conn?.send(encodeCloseFrame(sub.id));
    if (!_wantsLive) {
      _reconnect?.cancel();
      _reconnect = null;
    }
  }

  Future<void> shutdown() async {
    _reconnect?.cancel();
    _reconnect = null;
    final c = conn;
    final frames = _frames;
    if (c != null) _onDisconnect(c);
    await frames?.cancel();
    await c?.close();
  }
}

/// A map that forgets its oldest entries beyond [capacity].
class _BoundedMap<K, V> {
  final int capacity;
  final _map = <K, V>{};
  _BoundedMap(this.capacity);

  V? operator [](K key) => _map[key];
  bool containsKey(K key) => _map.containsKey(key);
  void operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }
}
