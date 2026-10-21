/// G52 step 5: the **link sync engine** — publishes this device's snapshot
/// of every link group to the Nostr relays and merges the other devices'
/// snapshots (design doc `docs/design/no-login-sharing.md` §4, §5, §8.1).
///
/// One engine per ledger DB ([linkSyncEngineProvider], like `SyncEngine`),
/// for Matrix accounts **and** local mode; never on the signed-out
/// placeholder, never in the offline demo. Without a link channel it does
/// nothing at all — no connection, no NIP-11 request (G43).
///
/// **Publish** (§4.4, §4.5, §5.4). Any change to a link group's stored rows
/// (local write *or* inbound merge — drift table updates) schedules a check
/// after [linkPublishDebounceProvider] (3 s; at most one publish per group
/// per [linkPublishMinIntervalProvider], 5 s). The check builds the group's
/// bootstrap content (incl. tombstones and `pendingSign` rows, records
/// sorted by id) and its [linkSnapshotDigest]; it publishes when the digest
/// differs from `last_published_hash`, or when the last publish is older
/// than [kLinkRefreshAfter] (10 days — `expiration` keeps moving). The
/// snapshot is planned into 1/2/4/8 parts within the smallest content
/// budget of the relays it goes to (NIP-11, `nip11.dart`); parts no longer
/// used are overwritten with header-only parts that expire after a day.
/// Each event gets the channel's next strictly increasing `created_at`
/// (`LinkDao.nextCreatedAt`), `expiration` = now + 30 days, the `alt` tag.
/// A group is **delivered** when every event was accepted by ≥ 1 relay;
/// only then `last_published_hash` / `parts` are recorded. No publish
/// without "me" (`my_participant_id`, §6.2: the join picker comes first).
///
/// **Relay answers** (`link_relay_policy.dart`): `replaced:` → bump
/// `created_at` past our newest event on that relay (fetched) and
/// republish that event once; `rate-limited:` → that relay is skipped for
/// 1 min doubling to 1 h; `blocked:` / `restricted:` / `invalid:` /
/// `pow:` / `auth-required:` → skipped until the next app start (recorded in
/// `link_relay_state:<url>` for the settings page); a group not delivered is
/// retried after 1 min doubling to 1 h ([linkRetryBackoffProvider]).
///
/// **Receive** (§4.3, §5.2). One live subscription on every relay covering
/// all topics (`#d` = topic + `.1`…`.7` of every channel), re-issued when
/// the channel set changes; the first `REQ` has no `since` (it doubles as
/// the app-start full fetch; the pool adds `since` on reconnects), it is
/// closed [linkPauseGraceProvider] (30 s) after the app is paused and
/// reopened on resume with `since` = newest seen − 60 s. Per event, in
/// arrival order: own pubkey → only remembered (its `created_at`); already
/// processed (`link_peers`) → skipped before decrypting; decrypt / header
/// failure, another group or another part than its `d` says → ignored and
/// logged. Otherwise it is merged through the **link path** of `RecordGate`
/// (`linkPolicy: LinkDao.policyOf`, `relayedBy: nostr:<pubkey>`,
/// attestations never trusted) and recorded in `link_peers` — both in one
/// transaction. The merge's table updates schedule a republish (a merge
/// that changed nothing publishes nothing).
///
/// **Status** (§5.3): [LinkGroupSyncStatus] per group — synced (our latest
/// snapshot was accepted by ≥ 1 relay and no merge failed), pending (a
/// publish is due / in flight / retrying), failing (2 consecutive attempts
/// not delivered, every relay rejects us, or the group is too big).
///
/// **Seams for later steps:** [openChannel] (invite, step 6), [refresh]
/// (join's full fetch, pull to refresh, the background round's link phase —
/// steps 7 / 8), [publishAll] (background round), [unpublish] (leave /
/// delete, step 10: header-only parts + NIP-09 deletion), [watchStatus]
/// (sync icon + peers sheet, step 9).
///
/// G19: the DB, DAOs, clock and settings are captured in the constructor;
/// every async path checks [_alive] after each await and bails silently;
/// [dispose] cancels every timer and closes the pool.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show TableUpdate, TableUpdateQuery;
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/about/about_page.dart' show appVersionProvider;
import '../../features/expenses/expenses_provider.dart';
import '../../models/link_model.dart';
import '../database/app_database.dart';
import '../database/daos/expenses_dao.dart';
import '../database/daos/groups_dao.dart';
import '../database/daos/link_dao.dart';
import '../database/daos/members_dao.dart';
import '../database/daos/settings_dao.dart';
import '../database/daos/signing_dao.dart';
import '../demo/demo_mode.dart';
import '../matrix/ledger_transport.dart';
import '../matrix/transport_provider.dart';
import '../session/app_session.dart';
import '../session/local_transport.dart';
import '../sync/ledger_payloads.dart';
import '../sync/record_gate.dart';
import '../sync/record_verifier.dart';
import '../sync/sync_health.dart' show kSyncFailureThreshold;
import 'link_channel.dart';
import 'link_envelope.dart';
import 'link_keys.dart';
import 'link_relay_policy.dart';
import 'link_snapshot.dart';
import 'link_uri.dart';
import 'nostr/nip09.dart';
import 'nostr/nip11.dart';
import 'nostr/nostr_event.dart';
import 'nostr/nostr_frames.dart';
import 'nostr/nostr_relay_pool.dart';
import 'nostr/relay_connection.dart';

// ── constants ───────────────────────────────────────────────────────────────

/// NIP-40 `expiration` of a published snapshot part (§4.2, Leo 2026-10-17).
const kLinkExpiry = Duration(days: 30);

/// Republish an unchanged snapshot once the last publish is this old (§4.4).
const kLinkRefreshAfter = Duration(days: 10);

/// `expiration` of a retired / header-only part (§5.4, §7.3).
const kLinkRetiredExpiry = Duration(days: 1);

/// The NIP-31 `alt` tag (§4.2).
const kLinkAltText = 'MoneyLedger encrypted group data';

/// How long a `replaced:` follow-up fetch of our own event may take.
const kLinkOwnFetchTimeout = Duration(seconds: 5);

/// How long the merge waits for the ledger transport (its crypto verifies
/// signed versions) before falling back to local verification.
const kLinkTransportWait = Duration(seconds: 10);

// ── providers ───────────────────────────────────────────────────────────────

/// Whether the link sync engine may run (off in the offline demo, G15).
final linkSyncEnabledProvider = Provider<bool>((ref) => !kOfflineDemo);

/// How the engine reaches relays (tests: `FakeRelayNetwork`).
final linkRelayConnectorProvider = Provider<RelayConnector>(
  (ref) => const WebSocketRelayConnector(),
);

/// NIP-11 fetcher; null = never fetch (tests).
final linkRelayInfoFetcherProvider = Provider<RelayInfoFetcher?>(
  (ref) => HttpRelayInfoFetcher(),
);

/// The engine's clock (ms epoch) — Nostr `created_at`, expirations, refresh.
final linkClockProvider = Provider<int Function()>(
  (ref) =>
      () => DateTime.now().millisecondsSinceEpoch,
);

/// §4.4: debounce between a change and the publish check.
final linkPublishDebounceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

/// §4.4: at most one publish per group per this interval.
final linkPublishMinIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// Retry of a publish nobody accepted: first delay, doubling up to the max.
final linkRetryBackoffProvider = Provider<({Duration min, Duration max})>(
  (ref) => (min: const Duration(minutes: 1), max: const Duration(hours: 1)),
);

/// `rate-limited:` back-off per relay: first delay, doubling up to the max.
final linkRateLimitBackoffProvider = Provider<({Duration min, Duration max})>(
  (ref) => (min: kRelayRateLimitMin, max: kRelayRateLimitMax),
);

/// How often due refreshes (§4.4, 10 days) are looked for while running.
final linkRefreshCheckIntervalProvider = Provider<Duration>(
  (ref) => const Duration(hours: 6),
);

/// §4.3: the live subscription closes this long after the app is paused.
final linkPauseGraceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

/// BIP-340 verification of inbound events (native only, §3.3).
final linkVerifySignaturesProvider = Provider<bool>(
  (ref) => kVerifyNostrSignatures,
);

/// Whether the engine follows the app lifecycle (pause / resume). Off in
/// container tests (no widgets binding).
final linkAppLifecycleProvider = Provider<bool>((ref) => true);

/// G52 step 8: the engine runs inside an Android background round (G31) —
/// no live subscription, no automatic (debounced / start-up / refresh-timer)
/// publishes: the round drives it with [LinkSyncEngine.refresh] (one full
/// fetch) and [LinkSyncEngine.publishAll] (publish what changed), then
/// disposes it.
final linkBackgroundRoundProvider = Provider<bool>((ref) => false);

/// The `app` header of our snapshots (§5.1; '' when unknown).
final linkAppVersionProvider = FutureProvider<String>((ref) async {
  try {
    return await ref
        .watch(appVersionProvider.future)
        .timeout(const Duration(seconds: 2));
  } catch (_) {
    return '';
  }
});

final linkSyncEngineProvider = Provider.autoDispose<LinkSyncEngine>((ref) {
  // Rebuilt (dispose + restart) when the ledger DB is swapped (G4 / G40).
  ref.watch(appDatabaseProvider);
  final engine = LinkSyncEngine(ref);
  if (ref.read(linkSyncEnabledProvider)) unawaited(engine.start());
  ref.onDispose(engine.dispose);
  return engine;
});

/// G52 step 10 (§7.3): how long leaving / deleting a link group (and
/// *Delete local data*) waits for [LinkSyncEngine.unpublish] in total
/// before it purges anyway — best-effort, the relays drop our events after
/// their expiry regardless.
const kLinkUnpublishMaxWait = Duration(seconds: 8);

/// Unpublishes this device's copy of a link group (true = ≥ 1 relay
/// accepted the deletion; false also when it timed out / failed).
typedef LinkUnpublisher = Future<bool> Function(String groupId);

/// G52 step 10: the seam leave / delete / *Delete local data* use before a
/// link group is purged — [LinkSyncEngine.unpublish] on the running engine
/// (kept alive by `LedgerSyncHost`), bounded by [kLinkUnpublishMaxWait],
/// never throwing. Off (false at once) in the offline demo.
final linkUnpublisherProvider = Provider<LinkUnpublisher>(
  (ref) => (groupId) async {
    if (!ref.read(linkSyncEnabledProvider)) return false;
    try {
      return await ref
          .read(linkSyncEngineProvider)
          .unpublish(groupId)
          .timeout(kLinkUnpublishMaxWait, onTimeout: () => false);
    } catch (e) {
      debugPrint('[link] unpublish of $groupId failed: $e');
      return false;
    }
  },
);

/// Keeps the link sync engine running while there is a ledger (an account
/// or local mode) — watched by `LedgerSyncHost`.
final linkSyncActiveProvider = Provider.autoDispose<bool>((ref) {
  if (ref.watch(ledgerIdentityProvider) == null) return false;
  ref.watch(linkSyncEngineProvider);
  return true;
});

/// §5.3: the sync status of link group [groupId] (G52 step 9 shows it).
final linkGroupSyncStatusProvider = StreamProvider.autoDispose
    .family<LinkGroupSyncStatus, String>(
      (ref, groupId) => ref.watch(linkSyncEngineProvider).watchStatus(groupId),
    );

// ── status ──────────────────────────────────────────────────────────────────

enum LinkSyncPhase { synced, pending, failing }

/// Why a link group isn't (yet) synced.
enum LinkSyncProblem {
  /// No relay accepted the last attempt (offline / timeouts / errors).
  notDelivered,

  /// Every relay refuses our events (`blocked:` / `restricted:` / …).
  relaysReject,

  /// The snapshot doesn't fit 8 parts (§5.4: use Matrix).
  tooLarge,

  /// This device hasn't picked its participant yet — nothing is published.
  noParticipant,

  /// A peer's snapshot couldn't be merged (DB error) — retried later.
  mergeFailed,
}

/// The §5.3 sync status of one link group.
class LinkGroupSyncStatus {
  final LinkSyncPhase phase;

  /// When our snapshot was last accepted by a relay (ms epoch; null = never).
  final int? lastPublishedAt;

  /// Consecutive publish attempts no relay accepted.
  final int consecutiveFailures;
  final LinkSyncProblem? problem;

  const LinkGroupSyncStatus({
    required this.phase,
    this.lastPublishedAt,
    this.consecutiveFailures = 0,
    this.problem,
  });

  @override
  String toString() =>
      'LinkGroupSyncStatus(${phase.name}, problem: ${problem?.name}, '
      'failures: $consecutiveFailures)';
}

/// What [LinkSyncEngine.refresh] found.
class LinkRefreshResult {
  /// Events served (newest per address), ours included.
  final int events;

  /// Peer events merged now (not processed before).
  final int merged;

  /// Every relay answered with `EOSE`.
  final bool complete;

  /// At least one relay answered with `EOSE`.
  final bool anyComplete;

  const LinkRefreshResult({
    required this.events,
    required this.merged,
    required this.complete,
    required this.anyComplete,
  });
}

/// G52 step 9: one relay as the settings page shows it.
class LinkRelayView {
  final String url;

  /// The persisted state (NIP-11 cache, last OK, last rejection).
  final LinkRelayState state;

  /// The relay refused our events this run (skipped until the next start):
  /// its message.
  final String? rejectingMessage;

  /// Backed off after `rate-limited:` until then (ms epoch).
  final int? rateLimitedUntil;

  const LinkRelayView({
    required this.url,
    this.state = const LinkRelayState(),
    this.rejectingMessage,
    this.rateLimitedUntil,
  });
}

/// G52 step 9: the configured relays and their state (settings page).
final linkRelaysViewProvider = StreamProvider.autoDispose<List<LinkRelayView>>(
  (ref) => ref.watch(linkSyncEngineProvider).watchRelays(),
);

// ── engine ──────────────────────────────────────────────────────────────────

class _Channel {
  final LinkChannelModel model;
  final LinkKeys keys;
  final String pubkey;
  _Channel(this.model, this.keys, this.pubkey);

  String get key => '${model.groupId}|${model.epoch}|${model.secret}';
}

class LinkSyncEngine {
  final Ref _ref;
  final AppDatabase _db;
  final LinkDao _link;
  final GroupsDao _groups;
  final MembersDao _members;
  final ExpensesDao _expenses;
  final SigningDao _signing;
  final SettingsDao _settings;
  final String? _identity;
  final int Function() _clock;
  final Duration _debounce;
  final Duration _minInterval;
  final ({Duration min, Duration max}) _retry;
  final Duration _refreshCheck;
  final Duration _pauseGrace;
  final bool _verifySignatures;
  final RelayConnector _connector;
  final RelayInfoFetcher? _infoFetcher;
  final bool _followLifecycle;
  final bool _roundMode;
  final Future<String> _appVersion;
  late final LinkRelayPolicy _policy;

  bool _disposed = false;
  bool _started = false;

  List<String> _relays = kDefaultLinkRelays;
  final Map<String, LinkRelayState> _relayStates = {};
  Future<void>? _relaysLoading;
  bool _relayInfoChecked = false;
  final _relayChanges = StreamController<void>.broadcast();

  /// Groups to publish even when their snapshot is unchanged (a relay was
  /// added — it doesn't hold our events yet).
  final Set<String> _forced = {};

  NostrRelayPool? _pool;
  NostrSubscription? _sub;
  StreamSubscription<NostrReceivedEvent>? _subEvents;
  StreamSubscription<Set<TableUpdate>>? _tables;
  Timer? _refreshTimer;
  Timer? _pauseTimer;
  AppLifecycleListener? _lifecycle;
  bool _paused = false;

  final Map<String, _Channel> _channels = {};
  final Map<String, ({String group, int part})> _byTopic = {};
  Future<void> _reloadChain = Future.value();

  final Map<String, Timer> _debounceTimers = {};
  final Map<String, Timer> _retryTimers = {};
  final Map<String, int> _retryStreak = {};
  final Set<String> _publishing = {};

  /// The publish run in flight per group (step 12 waits for it).
  final Map<String, Future<void>> _publishRuns = {};

  /// Groups whose link is being reset / switched (step 12): nothing is
  /// published or merged for them meanwhile.
  final Set<String> _resetting = {};
  final Set<String> _dirty = {};
  final Map<String, int> _lastPublishAt = {};
  final Map<String, int> _failures = {};

  /// Newest `created_at` of our own events seen per `d` tag.
  final Map<String, int> _ownNewest = {};

  Future<void> _inbound = Future.value();
  int _busy = 0;

  RecordGate? _gate;
  RecordVerifier? _verifier;

  final Map<String, LinkGroupSyncStatus> _status = {};
  final Set<String> _mergeFailed = {};
  final _statusChanges = StreamController<String>.broadcast();
  final Completer<void> _ready = Completer<void>();

  LinkSyncEngine(Ref ref)
    : _ref = ref,
      _db = ref.read(appDatabaseProvider),
      _link = LinkDao(ref.read(appDatabaseProvider)),
      _groups = ref.read(groupsDaoProvider),
      _members = ref.read(membersDaoProvider),
      _expenses = ref.read(expensesDaoProvider),
      _signing = ref.read(signingDaoProvider),
      _settings = SettingsDao(ref.read(appDatabaseProvider)),
      _identity = ref.read(ledgerIdentityProvider),
      _clock = ref.read(linkClockProvider),
      _debounce = ref.read(linkPublishDebounceProvider),
      _minInterval = ref.read(linkPublishMinIntervalProvider),
      _retry = ref.read(linkRetryBackoffProvider),
      _refreshCheck = ref.read(linkRefreshCheckIntervalProvider),
      _pauseGrace = ref.read(linkPauseGraceProvider),
      _verifySignatures = ref.read(linkVerifySignaturesProvider),
      _connector = ref.read(linkRelayConnectorProvider),
      _infoFetcher = ref.read(linkRelayInfoFetcherProvider),
      _roundMode = ref.read(linkBackgroundRoundProvider),
      _followLifecycle =
          ref.read(linkAppLifecycleProvider) &&
          !ref.read(linkBackgroundRoundProvider),
      _appVersion = ref.read(linkAppVersionProvider.future) {
    final rl = ref.read(linkRateLimitBackoffProvider);
    _policy = LinkRelayPolicy(
      clock: _clock,
      rateLimitMin: rl.min,
      rateLimitMax: rl.max,
    );
  }

  bool get _alive => !_disposed && !_db.isClosed;

  int get _nowSec => _clock() ~/ 1000;

  /// Completes once [start] has loaded the channels (or gave up).
  Future<void> get ready => _ready.future;

  /// No work in flight and no publish waiting for its debounce (tests; the
  /// back-off retry timers don't count).
  bool get isIdle => _busy == 0 && _debounceTimers.isEmpty;

  /// How many link channels the engine has loaded.
  int get channelCount => _channels.length;

  /// The relays the engine publishes to / reads from.
  List<String> get relays => List.unmodifiable(_relays);

  /// The relay back-off / block state (settings page, tests).
  LinkRelayPolicy get relayPolicy => _policy;

  /// The persisted state of [relay] as last loaded / written.
  LinkRelayState? relayState(String relay) => _relayStates[relay];

  /// G52 step 9: the relays with their state, now and after every change
  /// (a relay answer, a NIP-11 fetch, [setRelays]). Reads the relay list
  /// from the settings but never contacts a relay.
  Stream<List<LinkRelayView>> watchRelays() async* {
    await _ensureRelaysLoaded();
    if (!_alive) return;
    yield relayViews;
    await for (final _ in _relayChanges.stream) {
      if (!_alive) return;
      yield relayViews;
    }
  }

  /// The relays with their current state (see [watchRelays]).
  List<LinkRelayView> get relayViews => [
    for (final r in _relays)
      LinkRelayView(
        url: r,
        state: _relayStates[r] ?? const LinkRelayState(),
        rejectingMessage: _policy.rejecting[r],
        rateLimitedUntil: _policy.rateLimitedUntil(r),
      ),
  ];

  void _emitRelays() {
    if (!_relayChanges.isClosed) _relayChanges.add(null);
  }

  LinkGroupSyncStatus? statusOf(String groupId) => _status[groupId];

  /// The status of [groupId]: the current one (if known), then every change.
  Stream<LinkGroupSyncStatus> watchStatus(String groupId) async* {
    final now = _status[groupId];
    if (now != null) yield now;
    await for (final id in _statusChanges.stream) {
      final s = _status[id];
      if (id == groupId && s != null) yield s;
    }
  }

  // ── lifecycle ─────────────────────────────────────────────────────────────

  Future<void> start() async {
    try {
      await _start();
    } catch (e) {
      if (_alive) debugPrint('[link] engine start failed: $e');
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  Future<void> _start() async {
    if (_started || !_alive) return;
    _started = true;
    // Signed out: no ledger; pages may still build this during a
    // login/logout transition (as SyncEngine, G24).
    if (_db.isSignedOutPlaceholder) return;
    _tables = _db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            _db.linkChannels,
            _db.groups,
            _db.members,
            _db.expenses,
            _db.settlements,
          ]),
        )
        .listen(_onTables);
    await _reloadChannels();
    if (!_alive) return;
    if (_followLifecycle) {
      try {
        _lifecycle = AppLifecycleListener(
          onPause: onAppPaused,
          onResume: onAppResumed,
        );
      } catch (_) {
        // No widgets binding (a headless isolate): no pause / resume.
      }
    }
    if (_roundMode) return;
    _refreshTimer = Timer.periodic(_refreshCheck, (_) {
      for (final g in _channels.keys) {
        _schedulePublish(g);
      }
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lifecycle?.dispose();
    _refreshTimer?.cancel();
    _pauseTimer?.cancel();
    for (final t in [..._debounceTimers.values, ..._retryTimers.values]) {
      t.cancel();
    }
    _debounceTimers.clear();
    _retryTimers.clear();
    unawaited(_tables?.cancel());
    unawaited(_subEvents?.cancel());
    final pool = _pool;
    _pool = null;
    _sub = null;
    if (pool != null) unawaited(pool.close());
    unawaited(_statusChanges.close());
    unawaited(_relayChanges.close());
    if (!_ready.isCompleted) _ready.complete();
  }

  /// §4.3: the app went to the background — the live subscription closes
  /// after [linkPauseGraceProvider] (30 s).
  void onAppPaused() {
    if (!_alive) return;
    _paused = true;
    _pauseTimer?.cancel();
    _pauseTimer = Timer(_pauseGrace, () {
      _pauseTimer = null;
      if (_alive && _paused) unawaited(_closeLive());
    });
  }

  /// §4.3: back in the foreground — reopen the live subscription with
  /// `since` = the newest event seen − 60 s.
  void onAppResumed() {
    if (!_alive) return;
    _paused = false;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    if (_sub == null && _channels.isNotEmpty) {
      unawaited(_track(() => _updateSubscription(sinceNewest: true)));
    }
  }

  /// G52 step 8 review: a background round delegated to the running app
  /// ([refresh] + [publishAll]) reopens the relay connections while the app
  /// is paused (its live subscription was closed after the grace period) —
  /// close them again afterwards, so a backgrounded app doesn't hold
  /// sockets until it resumes. No-op in the foreground, while the live
  /// subscription is open or while other work is still running.
  Future<void> releaseIdleConnections() async {
    if (!_alive || !_paused || _sub != null || _busy > 0) return;
    if (_debounceTimers.isNotEmpty) return;
    final pool = _pool;
    _pool = null;
    await pool?.close();
  }

  Future<void> _closeLive() async {
    final sub = _sub;
    final events = _subEvents;
    final pool = _pool;
    _sub = null;
    _subEvents = null;
    _pool = null;
    await events?.cancel();
    await sub?.close();
    await pool?.close();
  }

  Future<T> _track<T>(Future<T> Function() work) async {
    _busy++;
    try {
      return await work();
    } finally {
      _busy--;
    }
  }

  // ── channels + subscription ───────────────────────────────────────────────

  void _onTables(Set<TableUpdate> updates) {
    if (!_alive) return;
    var ledger = false;
    var channels = false;
    for (final u in updates) {
      if (u.table == _db.linkChannels.actualTableName) {
        channels = true;
      } else {
        ledger = true;
      }
    }
    if (channels) unawaited(_reloadChannels());
    if (ledger) {
      for (final g in _channels.keys) {
        _schedulePublish(g);
      }
    }
  }

  /// Re-reads the channels (serialised); derives the keys of new ones,
  /// forgets dropped ones, and re-issues the subscription when the topic set
  /// changed. New channels get a publish check.
  Future<void> _reloadChannels() {
    _busy++;
    final next = _reloadChain.then((_) async {
      try {
        await _reloadChannelsNow();
      } catch (e) {
        if (_alive) debugPrint('[link] loading channels failed: $e');
      }
    });
    _reloadChain = next.whenComplete(() => _busy--);
    return _reloadChain;
  }

  Future<void> _reloadChannelsNow() async {
    if (!_alive) return;
    final models = await _link.getAllChannels();
    if (!_alive) return;
    if (models.isNotEmpty) {
      await _ensureRelaysLoaded();
      if (!_alive) return;
      // §4.6: NIP-11 only once there is something to sync (G43).
      if (!_relayInfoChecked) {
        _relayInfoChecked = true;
        unawaited(_track(refreshRelayInfo));
      }
    }
    final fresh = <String, _Channel>{};
    final added = <String>[];
    for (final m in models) {
      final old = _channels[m.groupId];
      final key = '${m.groupId}|${m.epoch}|${m.secret}';
      if (old != null && old.key == key && old.model.nostrPriv == m.nostrPriv) {
        fresh[m.groupId] = _Channel(m, old.keys, old.pubkey);
        // "Me" picked / changed (join, step 7): publish now.
        if (old.model.myParticipantId != m.myParticipantId) {
          added.add(m.groupId);
        }
        continue;
      }
      try {
        final keys = await deriveLinkKeys(decodeLinkSecret(m.secret));
        fresh[m.groupId] = _Channel(m, keys, nostrPublicKey(m.nostrPriv));
        added.add(m.groupId);
      } catch (e) {
        debugPrint('[link] channel of ${m.groupId} unusable: $e');
      }
      if (!_alive) return;
    }
    final topicsBefore = _byTopic.keys.toSet();
    for (final g in _channels.keys.where((g) => !fresh.containsKey(g))) {
      _debounceTimers.remove(g)?.cancel();
      _retryTimers.remove(g)?.cancel();
      _status.remove(g);
    }
    _channels
      ..clear()
      ..addAll(fresh);
    _byTopic.clear();
    for (final c in _channels.values) {
      for (var i = 0; i < kLinkMaxParts; i++) {
        _byTopic[linkPartTopic(c.keys.topic, i)] = (
          group: c.model.groupId,
          part: i,
        );
      }
    }
    if (!_setEquals(topicsBefore, _byTopic.keys.toSet())) {
      await _updateSubscription();
      if (!_alive) return;
    }
    for (final g in added) {
      _status[g] ??= const LinkGroupSyncStatus(phase: LinkSyncPhase.pending);
      _emit(g);
      _schedulePublish(g, delay: Duration.zero);
    }
  }

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  /// Loads the relay list and each relay's persisted state once (no
  /// network).
  Future<void> _ensureRelaysLoaded() => _relaysLoading ??= _loadRelays();

  Future<void> _loadRelays() async {
    if (!_alive || _db.isSignedOutPlaceholder) return;
    try {
      _relays = parseLinkRelays(await _settings.linkRelaysRaw(), _relays);
      for (final r in _relays) {
        if (!_alive) return;
        _relayStates[r] ??= LinkRelayState.decode(
          await _settings.linkRelayStateRaw(r),
        );
      }
    } catch (e) {
      if (_alive) debugPrint('[link] loading relays failed: $e');
    }
    _emitRelays();
  }

  /// G52 step 9 — the relay settings: replaces the relay list (stored in
  /// `link_relays`; the defaults clear the setting so a later app update's
  /// defaults apply). [info] = NIP-11 documents the settings page fetched
  /// while adding a relay. The connections are rebuilt; a relay that wasn't
  /// in the list before gets every link group's snapshot at once (forced
  /// publish — it holds none of our events yet).
  Future<void> setRelays(
    List<String> relays, {
    Map<String, RelayInfo> info = const {},
  }) => _track(() async {
    await _ensureRelaysLoaded();
    final next = <String>{
      for (final r in relays)
        if (relayInfoUrl(r) != null) r,
    }.toList();
    if (next.isEmpty) throw ArgumentError('at least one relay is needed');
    if (!_alive) return;
    if (_sameList(next, kDefaultLinkRelays)) {
      await _settings.clearLinkRelays();
    } else {
      await _settings.setLinkRelaysRaw(jsonEncode(next));
    }
    if (!_alive) return;
    final added = next.where((r) => !_relays.contains(r)).toList();
    final changed = !_sameList(next, _relays);
    _relays = next;
    for (final r in next) {
      if (!_alive) return;
      _relayStates[r] ??= LinkRelayState.decode(
        await _settings.linkRelayStateRaw(r),
      );
    }
    for (final e in info.entries) {
      if (!next.contains(e.key)) continue;
      await _saveRelayState(
        e.key,
        (_relayStates[e.key] ?? const LinkRelayState()).copyWith(
          info: e.value,
          infoFetchedAt: _clock(),
        ),
      );
      if (!_alive) return;
    }
    _emitRelays();
    if (!changed) return;
    // Rebuild the pool on the new list (the live subscription with it).
    await _closeLive();
    if (!_alive || _channels.isEmpty) return;
    await _updateSubscription();
    if (!_alive) return;
    unawaited(_track(refreshRelayInfo));
    if (added.isEmpty || _roundMode) return;
    for (final g in _channels.keys) {
      _forced.add(g);
      _schedulePublish(g, delay: Duration.zero);
    }
  });

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// §4.6: fetches the NIP-11 document of every relay whose cached one is
  /// missing or older than 7 days (best-effort; a failure keeps the cache).
  Future<void> refreshRelayInfo({bool force = false}) async {
    final fetcher = _infoFetcher;
    if (fetcher == null) return;
    for (final r in [..._relays]) {
      final state = _relayStates[r] ?? const LinkRelayState();
      if (!force && !state.infoStale(_clock())) continue;
      try {
        final info = await fetcher.fetch(r);
        if (!_alive) return;
        await _saveRelayState(
          r,
          state.copyWith(info: info, infoFetchedAt: _clock()),
        );
      } catch (e) {
        if (!_alive) return;
        debugPrint('[link] NIP-11 of $r unavailable: $e');
      }
    }
  }

  Future<void> _saveRelayState(String relay, LinkRelayState state) async {
    _relayStates[relay] = state;
    _emitRelays();
    if (!_alive) return;
    try {
      await _settings.setLinkRelayStateRaw(relay, state.encode());
    } catch (e) {
      if (_alive) debugPrint('[link] saving relay state failed: $e');
    }
  }

  NostrRelayPool _ensurePool() => _pool ??= NostrRelayPool(
    relays: _relays,
    connector: _connector,
    verifySignatures: _verifySignatures,
    nowSeconds: () => _nowSec,
  );

  List<NostrFilter> _filters(Iterable<String> topics, {int? since}) => [
    NostrFilter(
      kinds: const [kLinkEventKind],
      tags: {'d': topics.toList()..sort()},
      since: since,
    ),
  ];

  Future<void> _updateSubscription({bool sinceNewest = false}) async {
    if (!_alive) return;
    // Step 8: a background round reads with refresh() only.
    if (_byTopic.isEmpty || _paused || _roundMode) {
      if (_sub != null) await _closeLive();
      return;
    }
    int? since;
    if (sinceNewest) {
      final newest = await _link.newestPeerCreatedAt();
      if (!_alive) return;
      if (newest > kLiveResubscribeOverlap) {
        since = newest - kLiveResubscribeOverlap;
      }
    }
    final filters = _filters(_byTopic.keys, since: since);
    final sub = _sub;
    if (sub != null) {
      sub.update(filters);
      return;
    }
    final fresh = _ensurePool().subscribe(filters);
    _sub = fresh;
    _subEvents = fresh.events.listen((r) => _enqueue(r.event));
  }

  // ── inbound ───────────────────────────────────────────────────────────────

  /// Queues [event] behind the events before it; completes when handled.
  Future<bool> _enqueue(NostrEvent event) {
    _busy++;
    final done = _inbound.then((_) async {
      try {
        return await _handle(event);
      } catch (e) {
        if (_alive) debugPrint('[link] event ${event.id} failed: $e');
        return false;
      }
    });
    _inbound = done.whenComplete(() => _busy--);
    return done;
  }

  /// Handles one event; returns whether a peer snapshot was merged.
  Future<bool> _handle(NostrEvent event) async {
    if (!_alive) return false;
    final route = _byTopic[event.dTag];
    if (route == null || event.kind != kLinkEventKind) return false;
    final ch = _channels[route.group];
    if (ch == null) return false;
    final group = route.group;
    // Step 12: the link is being replaced — an event of the old topic is
    // dropped (not recorded: its publisher would show up as a peer of the
    // new link).
    if (_resetting.contains(group)) return false;
    if (event.pubkey == ch.pubkey) {
      _ownNewest[event.dTag] = math.max(
        _ownNewest[event.dTag] ?? 0,
        event.createdAt,
      );
      return false;
    }
    if (await _link.isProcessed(group, event.pubkey, route.part, event.id)) {
      return false;
    }
    if (!_alive) return false;
    final Map<String, dynamic> content;
    final LinkSnapshotHeader header;
    try {
      content = await openLinkContent(
        event.content,
        ch.keys.encKey,
        d: event.dTag,
        pubkey: event.pubkey,
      );
      header = parseLinkSnapshotHeader(content);
    } on LinkEnvelopeException catch (e) {
      debugPrint('[link] ignored event ${event.id} in $group: $e');
      return false;
    } on LinkSnapshotException catch (e) {
      debugPrint('[link] ignored event ${event.id} in $group: $e');
      return false;
    }
    if (!_alive) return false;
    if (header.group != group || header.part != route.part) {
      debugPrint(
        '[link] ignored event ${event.id}: names group ${header.group} part '
        '${header.part}, published under $group part ${route.part}',
      );
      return false;
    }
    final gate = await _gateFor();
    if (gate == null || !_alive) return false;
    final signers = _signerUsers(content);
    if (signers.isNotEmpty) {
      await _verifier?.prefetch(signers);
      if (!_alive) return false;
    }
    try {
      await _db.transaction(() async {
        await gate.snapshot(
          content,
          relayedBy: 'nostr:${event.pubkey}',
          trustAttestations: false,
        );
        if (!_alive) return;
        await _link.recordPeerEvent(
          groupId: group,
          pubkey: event.pubkey,
          part: route.part,
          eventId: event.id,
          createdAt: event.createdAt,
          seenAt: _clock(),
          me: header.me,
          snapshotDigest: linkSnapshotDigest(content),
        );
      });
    } catch (e) {
      if (!_alive) return false;
      debugPrint('[link] merging ${event.id} into $group failed: $e');
      _mergeFailed.add(group);
      _setStatus(
        group,
        LinkGroupSyncStatus(
          phase: LinkSyncPhase.pending,
          lastPublishedAt: _status[group]?.lastPublishedAt,
          problem: LinkSyncProblem.mergeFailed,
        ),
      );
      return false;
    }
    if (_mergeFailed.remove(group)) _schedulePublish(group);
    return true;
  }

  static Set<String> _signerUsers(Map<String, dynamic> content) {
    final users = <String>{};
    void scan(Object? r) {
      if (r is! Map) return;
      for (final k in const ['sig', 'origin']) {
        final s = r[k];
        if (s is Map && s['user'] is String) users.add(s['user'] as String);
      }
    }

    scan(content['meta']);
    for (final k in const ['members', 'expenses', 'settlements']) {
      final list = content[k];
      if (list is List) list.forEach(scan);
    }
    return users;
  }

  /// The link-path gate, built on first use: signed versions (mixed groups)
  /// are verified with the ledger transport's crypto — or, while that isn't
  /// available, local verification (`LocalOnlyTransport`: Ed25519, no
  /// device directory).
  Future<RecordGate?> _gateFor() async {
    final have = _gate;
    if (have != null) return have;
    LedgerTransport transport;
    try {
      transport = await _ref
          .read(ledgerTransportProvider.future)
          .timeout(kLinkTransportWait);
    } catch (_) {
      transport = LocalOnlyTransport('');
    }
    if (!_alive) return null;
    final verifier = RecordVerifier(
      crypto: transport.crypto,
      directory: transport.deviceKeys,
      signing: _signing,
      clock: _clock,
    );
    _verifier = verifier;
    return _gate ??= RecordGate(
      verifier: verifier,
      signing: _signing,
      groups: _groups,
      members: _members,
      expenses: _expenses,
      linkPolicy: _link.policyOf,
      isAlive: () => _alive,
      clock: _clock,
    );
  }

  /// §4.3 full fetch: every stored event of [groupId]'s topics (all link
  /// groups when null) from every relay, `EOSE` or [timeout] per relay,
  /// merged like live events. For join (step 7), pull to refresh and the
  /// background round (step 8).
  Future<LinkRefreshResult> refresh({String? groupId, Duration? timeout}) =>
      _track(() async {
        await _reloadChain;
        final topics = [
          for (final e in _byTopic.entries)
            if (groupId == null || e.value.group == groupId) e.key,
        ];
        if (!_alive || topics.isEmpty) {
          return const LinkRefreshResult(
            events: 0,
            merged: 0,
            complete: false,
            anyComplete: false,
          );
        }
        final result = await _ensurePool().fetchOnce(
          _filters(topics),
          timeout: timeout,
        );
        var merged = 0;
        for (final e in result.events) {
          if (!_alive) break;
          if (await _enqueue(e)) merged++;
        }
        return LinkRefreshResult(
          events: result.events.length,
          merged: merged,
          complete: result.complete,
          anyComplete: result.anyComplete,
        );
      });

  /// G52 step 7 — **join**: stores the channel of [groupId] for the link
  /// secret [secret] ([joinLinkChannel]: refuses a group this device holds
  /// as a non-link group or shares with another link — throws
  /// [LinkJoinException]) **before** anything is merged, loads it, then a
  /// full fetch of its topics ([refresh]) merges the group through the link
  /// path. Nothing is published until "me" is set (the join picker).
  Future<LinkRefreshResult> join(
    String groupId,
    String secret, {
    Duration? timeout,
  }) async {
    await joinLinkChannel(_db, groupId, secret: secret, clock: _clock);
    if (!_alive) {
      return const LinkRefreshResult(
        events: 0,
        merged: 0,
        complete: false,
        anyComplete: false,
      );
    }
    await _reloadChannels();
    return refresh(groupId: groupId, timeout: timeout);
  }

  /// G68 *Sync now* (the group's sync sheet): one full fetch of [groupId]
  /// from every relay, merged, then a publish check right away (a pending
  /// retry back-off is cut short; relays that reject us stay skipped).
  Future<LinkRefreshResult> syncNow(String groupId, {Duration? timeout}) async {
    final result = await refresh(groupId: groupId, timeout: timeout);
    if (!_alive || !_channels.containsKey(groupId)) return result;
    _retryTimers.remove(groupId)?.cancel();
    _lastPublishAt.remove(groupId);
    _schedulePublish(groupId, delay: Duration.zero);
    return result;
  }

  // ── publish ───────────────────────────────────────────────────────────────

  /// Schedules a publish check of [groupId] (after a local change the
  /// table updates do this on their own).
  void pokeGroup(String groupId) => _schedulePublish(groupId);

  void _schedulePublish(String group, {Duration? delay}) {
    if (!_alive || !_channels.containsKey(group)) return;
    if (_resetting.contains(group)) return;
    // Step 8: in a background round only publishAll() publishes (after the
    // full fetch merged the peers' snapshots — never our stale one first).
    if (_roundMode) return;
    if (_publishing.contains(group)) {
      _dirty.add(group);
      return;
    }
    var wait = delay ?? _debounce;
    final last = _lastPublishAt[group];
    if (last != null) {
      final gap = _minInterval - Duration(milliseconds: _clock() - last);
      if (gap > wait) wait = gap;
    }
    _debounceTimers.remove(group)?.cancel();
    _debounceTimers[group] = Timer(wait, () {
      _debounceTimers.remove(group);
      unawaited(_publish(group));
    });
  }

  /// Runs every pending / due publish now and waits for it (the background
  /// round's "publish what changed", step 8).
  Future<void> publishAll() => _track(() async {
    await _reloadChain;
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();
    await Future.wait([
      for (final g in [..._channels.keys]) _publish(g),
    ]);
  });

  Future<void> _publish(String group) async {
    if (!_alive || _resetting.contains(group)) return;
    if (_publishing.contains(group)) {
      _dirty.add(group);
      return;
    }
    _publishing.add(group);
    _busy++;
    final run = Completer<void>();
    _publishRuns[group] = run.future;
    try {
      await _publishNow(group);
    } catch (e) {
      if (_alive) {
        debugPrint('[link] publishing $group failed: $e');
        _failed(group, LinkSyncProblem.notDelivered);
      }
    } finally {
      _publishing.remove(group);
      _publishRuns.remove(group);
      run.complete();
      _busy--;
      if (_dirty.remove(group)) _schedulePublish(group);
    }
  }

  /// The group's bootstrap content as stored now (one read transaction),
  /// records sorted by id; null when the group isn't stored.
  Future<Map<String, dynamic>?> _bootstrapOf(String group) =>
      _db.transaction(() async {
        final g = await _groups.getGroup(group);
        if (g == null) return null;
        final members = await _members.getMembers(group)
          ..sort((a, b) => a.userId.compareTo(b.userId));
        final expenses = await _expenses.getAllExpensesForGroup(group)
          ..sort((a, b) => a.id.compareTo(b.id));
        final settlements = await _expenses.getAllSettlementsForGroup(group)
          ..sort((a, b) => a.id.compareTo(b.id));
        return buildBootstrapContent(
          group,
          g,
          members,
          expenses,
          settlements,
          deviceKeys: await _signing.attestationsFor(
            snapshotSigners(g, members, expenses, settlements),
          ),
          includePending: true,
        );
      });

  Future<void> _publishNow(String group) async {
    final ch = await _link.getChannel(group);
    final route = _channels[group];
    if (ch == null || route == null || !_alive) return;
    final me = ch.myParticipantId;
    if (me == null) {
      _setStatus(
        group,
        const LinkGroupSyncStatus(
          phase: LinkSyncPhase.pending,
          problem: LinkSyncProblem.noParticipant,
        ),
      );
      return;
    }
    final bootstrap = await _bootstrapOf(group);
    if (bootstrap == null || !_alive) return;
    final digest = linkSnapshotDigest(bootstrap);
    final now = _clock();
    final due =
        _forced.contains(group) ||
        digest != ch.lastPublishedHash ||
        now - ch.lastPublishedAt >= kLinkRefreshAfter.inMilliseconds;
    if (!due) {
      _synced(group, ch.lastPublishedAt);
      return;
    }
    _setStatus(
      group,
      LinkGroupSyncStatus(
        phase: (_failures[group] ?? 0) >= kSyncFailureThreshold
            ? LinkSyncPhase.failing
            : LinkSyncPhase.pending,
        lastPublishedAt: ch.lastPublishedAt == 0 ? null : ch.lastPublishedAt,
        consecutiveFailures: _failures[group] ?? 0,
      ),
    );
    final targets = [
      for (final r in _relays)
        if (_policy.canPublish(r)) r,
    ];
    if (targets.isEmpty) {
      final wait = _policy.nextAvailableIn(_relays);
      if (wait == null) {
        _failed(group, LinkSyncProblem.relaysReject, retry: false);
      } else {
        _scheduleRetry(group, atLeast: wait);
      }
      return;
    }
    final app = await _appVersion.catchError((_) => '');
    if (!_alive) return;
    final budget = targets
        .map((r) => relayContentBudget(_relayStates[r]?.info))
        .reduce(math.min);
    final LinkSnapshotPlan plan;
    try {
      plan = planLinkSnapshot(bootstrap, me: me, app: app, budget: budget);
    } on LinkSnapshotTooLargeException catch (e) {
      debugPrint('[link] $group too big for link sharing: $e');
      _failed(group, LinkSyncProblem.tooLarge, retry: false);
      return;
    }
    final parts = plan.parts.length;
    final expiry = _nowSec + kLinkExpiry.inSeconds;
    final retiredExpiry = _nowSec + kLinkRetiredExpiry.inSeconds;
    final events = <({String d, String content, int expiration})>[
      for (final p in plan.parts)
        (
          d: linkPartTopic(route.keys.topic, p.index),
          content: await _seal(route, p.index, p.packed),
          expiration: expiry,
        ),
      for (final i in retiredLinkParts(ch.parts, parts))
        (
          d: linkPartTopic(route.keys.topic, i),
          content: await _seal(
            route,
            i,
            packLinkSnapshot(
              buildRetiredLinkPart(
                bootstrap,
                me: me,
                app: app,
                index: i,
                parts: parts,
              ),
            ),
          ),
          expiration: retiredExpiry,
        ),
    ];
    if (!_alive) return;
    var delivered = true;
    for (final e in events) {
      final ok = await _publishEvent(
        group,
        route,
        d: e.d,
        content: e.content,
        expiration: e.expiration,
        targets: targets,
      );
      if (!_alive) return;
      if (!ok) delivered = false;
    }
    if (!delivered) {
      final wait = _policy.nextAvailableIn(_relays);
      if (wait == null) {
        _failed(group, LinkSyncProblem.relaysReject, retry: false);
      } else {
        _failed(group, LinkSyncProblem.notDelivered, atLeast: wait);
      }
      return;
    }
    await _link.recordPublished(
      group,
      hash: digest ?? '',
      at: now,
      parts: parts,
    );
    if (!_alive) return;
    _forced.remove(group);
    _lastPublishAt[group] = now;
    _failures.remove(group);
    _retryStreak.remove(group);
    _retryTimers.remove(group)?.cancel();
    _synced(group, now);
  }

  Future<String> _seal(_Channel route, int part, List<int> packed) =>
      sealLinkContent(
        packed,
        route.keys.encKey,
        d: linkPartTopic(route.keys.topic, part),
        pubkey: route.pubkey,
      );

  /// Signs and publishes one event (a fresh `created_at`); `replaced:` →
  /// one republish past our newest event there. Returns whether ≥ 1 relay
  /// holds it.
  Future<bool> _publishEvent(
    String group,
    _Channel route, {
    required String d,
    required String content,
    required int expiration,
    required List<String> targets,
  }) async {
    Future<List<NostrPublishResult>?> once(Iterable<String> to) async {
      final createdAt = await _link.nextCreatedAt(group, _nowSec);
      if (createdAt == null || !_alive) return null;
      final event = signNostrEvent(
        privateKey: route.model.nostrPriv,
        kind: kLinkEventKind,
        tags: [
          ['d', d],
          ['expiration', '$expiration'],
          ['alt', kLinkAltText],
        ],
        content: content,
        createdAt: createdAt,
      );
      final results = await _ensurePool().publish(event, only: to);
      if (!_alive) return null;
      for (final r in results) {
        await _noteAnswer(r);
        if (!_alive) return null;
      }
      return results;
    }

    final first = await once(targets);
    if (first == null) return false;
    var ok = first.any((r) => classifyRelayAnswer(r) == RelayAnswer.ok);
    final replaced = [
      for (final r in first)
        if (classifyRelayAnswer(r) == RelayAnswer.replaced) r.relay,
    ];
    if (replaced.isEmpty) return ok;
    // §4.4 / §4.5: a relay holds a newer event of ours at this address —
    // move our clock past it and republish once.
    final newest = await _ownNewestOn(route, d);
    if (!_alive) return false;
    await _link.bumpCreatedAt(group, newest);
    if (!_alive) return false;
    final second = await once(replaced);
    if (second == null) return false;
    // A second `replaced:` still means the relay holds an event of ours.
    ok =
        ok ||
        second.any((r) {
          final a = classifyRelayAnswer(r);
          return a == RelayAnswer.ok || a == RelayAnswer.replaced;
        });
    return ok;
  }

  /// The newest `created_at` of our own event at `d` on the relays (a
  /// short fetch), at least what the live subscription saw.
  Future<int> _ownNewestOn(_Channel route, String d) async {
    var newest = _ownNewest[d] ?? 0;
    final result = await _ensurePool().fetchOnce([
      NostrFilter(
        kinds: const [kLinkEventKind],
        authors: [route.pubkey],
        tags: {
          'd': [d],
        },
      ),
    ], timeout: kLinkOwnFetchTimeout);
    for (final e in result.events) {
      newest = math.max(newest, e.createdAt);
    }
    return newest;
  }

  Future<void> _noteAnswer(NostrPublishResult r) async {
    final answer = _policy.onResult(r);
    final state = _relayStates[r.relay] ?? const LinkRelayState();
    switch (answer) {
      case RelayAnswer.ok:
        await _saveRelayState(r.relay, state.copyWith(lastOkAt: _clock()));
      case RelayAnswer.rateLimited:
      case RelayAnswer.rejects:
        debugPrint('[link] ${r.relay} refused our event: ${r.message}');
        await _saveRelayState(
          r.relay,
          state.copyWith(
            lastRejectionAt: _clock(),
            lastRejection: answer.name,
            lastRejectionMessage: r.message,
          ),
        );
      case RelayAnswer.tooLarge:
        // A sharding bug (§5.4), not the relay's fault.
        debugPrint('[link] ${r.relay}: event too large (${r.message})');
      case RelayAnswer.replaced:
      case RelayAnswer.transient:
        break;
    }
  }

  void _scheduleRetry(String group, {Duration atLeast = Duration.zero}) {
    if (!_alive) return;
    final streak = (_retryStreak[group] ?? 0) + 1;
    _retryStreak[group] = streak;
    final ms = math.min(
      _retry.min.inMilliseconds * math.pow(2, math.min(streak - 1, 20)),
      _retry.max.inMilliseconds.toDouble(),
    );
    var wait = Duration(milliseconds: ms.round());
    if (atLeast > wait) wait = atLeast;
    _retryTimers.remove(group)?.cancel();
    _retryTimers[group] = Timer(wait, () {
      _retryTimers.remove(group);
      _schedulePublish(group, delay: Duration.zero);
    });
  }

  void _failed(
    String group,
    LinkSyncProblem problem, {
    bool retry = true,
    Duration atLeast = Duration.zero,
  }) {
    final failures = (_failures[group] ?? 0) + 1;
    _failures[group] = failures;
    final hard =
        problem == LinkSyncProblem.relaysReject ||
        problem == LinkSyncProblem.tooLarge;
    _setStatus(
      group,
      LinkGroupSyncStatus(
        phase: hard || failures >= kSyncFailureThreshold
            ? LinkSyncPhase.failing
            : LinkSyncPhase.pending,
        lastPublishedAt: _status[group]?.lastPublishedAt,
        consecutiveFailures: failures,
        problem: problem,
      ),
    );
    if (retry) _scheduleRetry(group, atLeast: atLeast);
  }

  void _synced(String group, int publishedAt) {
    _setStatus(
      group,
      LinkGroupSyncStatus(
        phase: _mergeFailed.contains(group)
            ? LinkSyncPhase.pending
            : LinkSyncPhase.synced,
        lastPublishedAt: publishedAt == 0 ? null : publishedAt,
        problem: _mergeFailed.contains(group)
            ? LinkSyncProblem.mergeFailed
            : null,
      ),
    );
  }

  void _setStatus(String group, LinkGroupSyncStatus status) {
    if (!_alive || !_channels.containsKey(group)) return;
    _status[group] = status;
    _emit(group);
  }

  void _emit(String group) {
    if (!_statusChanges.isClosed) _statusChanges.add(group);
  }

  // ── open / unpublish ──────────────────────────────────────────────────────

  /// Opens this device's link channel of [groupId] (`openLinkChannel`: own
  /// claim dropped, "me" set, fresh secret + Nostr key); the engine then
  /// publishes it. Returns the channel (existing one unchanged).
  Future<LinkChannelModel> openChannel(String groupId) =>
      openLinkChannel(_db, groupId, identity: _identity, clock: _clock);

  /// §7.3 (leave / delete, G52 step 10): overwrites every part this device
  /// published with a header-only part (meta + members, no records) that
  /// expires after a day, then asks the relays to delete all of them
  /// (NIP-09). Best-effort within [timeout]; returns whether ≥ 1 relay
  /// accepted the deletion (true at once, sending nothing, when this device
  /// never published for the group). The channel itself stays — the caller
  /// purges.
  Future<bool> unpublish(
    String groupId, {
    Duration timeout = const Duration(seconds: 5),
  }) => _track(() async {
    // G52 step 10: right after start the channels may not be loaded yet.
    if (_started) await ready;
    await _reloadChain;
    _debounceTimers.remove(groupId)?.cancel();
    _retryTimers.remove(groupId)?.cancel();
    final route = _channels[groupId];
    final ch = await _link.getChannel(groupId);
    if (route == null || ch == null || !_alive) return false;
    // Step 10 review: this device never signed an event for the group (a
    // restore re-opened the channel and nobody picked "me" yet) — nothing
    // of ours is on the relays, and a header-only part would be the first
    // thing it ever published.
    if (ch.lastCreatedAt == 0) return true;
    final targets = [
      for (final r in _relays)
        if (!_policy.rejects(r)) r,
    ];
    if (targets.isEmpty) return false;
    final bootstrap = await _bootstrapOf(groupId);
    if (!_alive) return false;
    final app = await _appVersion.catchError((_) => '');
    final me = ch.myParticipantId ?? '';
    final used = math.max(ch.parts, 1);
    final dTags = [
      for (var i = 0; i < used; i++) linkPartTopic(route.keys.topic, i),
    ];
    final expiry = _nowSec + kLinkRetiredExpiry.inSeconds;
    if (bootstrap != null) {
      final empty = {
        ...bootstrap,
        'expenses': const <Object?>[],
        'settlements': const <Object?>[],
      };
      for (var i = 0; i < used; i++) {
        final part = i == 0
            ? buildLinkSnapshotPart(empty, me: me, app: app)
            : buildRetiredLinkPart(empty, me: me, app: app, index: i, parts: 1);
        final content = await _seal(route, i, packLinkSnapshot(part));
        final createdAt = await _link.nextCreatedAt(groupId, _nowSec);
        if (createdAt == null || !_alive) return false;
        final event = signNostrEvent(
          privateKey: ch.nostrPriv,
          kind: kLinkEventKind,
          tags: [
            ['d', dTags[i]],
            ['expiration', '$expiry'],
            ['alt', kLinkAltText],
          ],
          content: content,
          createdAt: createdAt,
        );
        await _ensurePool().publish(event, only: targets, timeout: timeout);
        if (!_alive) return false;
      }
    }
    final createdAt = await _link.nextCreatedAt(groupId, _nowSec);
    if (createdAt == null || !_alive) return false;
    final deletion = buildNostrDeletion(
      privateKey: ch.nostrPriv,
      kind: kLinkEventKind,
      dTags: dTags,
      createdAt: createdAt,
    );
    final results = await _ensurePool().publish(
      deletion,
      only: targets,
      timeout: timeout,
    );
    return results.any((r) => r.acceptedEquivalent);
  });

  // ── reset / switch (step 12) ──────────────────────────────────────────────

  /// G52 step 12 — **Reset invite link** (§7.3, §14 Q10): this device's
  /// copy leaves the old topic ([unpublish]: header-only parts + NIP-09,
  /// bounded by [kLinkUnpublishMaxWait] in total — offline it simply
  /// expires), then the channel is replaced ([replaceLinkChannel]: a new
  /// random secret, the next epoch, a fresh Nostr key, "me" kept, the old
  /// peers forgotten) and the group is published under the new topic right
  /// away. Nothing is posted on the old topic that points to the new one —
  /// the removed person could read it; the new link is shared directly.
  /// Returns the new channel (its link is what the invite sheet shows).
  Future<LinkChannelModel> resetLink(String groupId) =>
      _replaceLink(groupId, null);

  /// G52 step 12 — **switch to a new link** of a group this device already
  /// shares with another one (someone reset the invite link and sent the
  /// new one; the join page asks first): like [resetLink] with the new
  /// link's [secret] (`k`), then a full fetch of the new topic merges the
  /// others who switched already. The same secret as now → nothing changes
  /// (only the fetch).
  Future<LinkRefreshResult> switchLink(
    String groupId,
    String secret, {
    Duration? timeout,
  }) async {
    await _replaceLink(groupId, secret);
    return refresh(groupId: groupId, timeout: timeout);
  }

  Future<LinkChannelModel> _replaceLink(String groupId, String? secret) =>
      _track(() async {
        if (_started) await ready;
        await _reloadChain;
        if (!_alive) throw StateError('link sync engine disposed');
        final current = await _link.getChannel(groupId);
        if (current == null) {
          throw const LinkChannelException(LinkChannelError.noChannel);
        }
        if (secret != null) {
          if (secret == current.secret) return current;
          decodeLinkSecret(secret); // malformed → nothing unpublished
        }
        _resetting.add(groupId);
        try {
          _debounceTimers.remove(groupId)?.cancel();
          _retryTimers.remove(groupId)?.cancel();
          // A publish in flight would put the old copy back on the old
          // topic after the unpublish; a merge in flight would record a
          // peer of the old link after the peers are forgotten.
          await _publishRuns[groupId];
          await _inbound;
          if (!_alive) throw StateError('link sync engine disposed');
          try {
            await unpublish(
              groupId,
            ).timeout(kLinkUnpublishMaxWait, onTimeout: () => false);
          } catch (e) {
            if (_alive) debugPrint('[link] unpublish of $groupId failed: $e');
          }
          if (!_alive) throw StateError('link sync engine disposed');
          final next = await replaceLinkChannel(
            _db,
            groupId,
            secret: secret,
            clock: _clock,
          );
          _failures.remove(groupId);
          _retryStreak.remove(groupId);
          _forced.remove(groupId);
          _lastPublishAt.remove(groupId);
          _mergeFailed.remove(groupId);
          _status[groupId] = const LinkGroupSyncStatus(
            phase: LinkSyncPhase.pending,
          );
          _emit(groupId);
          await _reloadChannels();
          return next;
        } finally {
          _resetting.remove(groupId);
          if (_alive) _schedulePublish(groupId, delay: Duration.zero);
        }
      });

  /// The status of every link group (tests / settings).
  @visibleForTesting
  Map<String, LinkGroupSyncStatus> get statuses => Map.unmodifiable(_status);
}
