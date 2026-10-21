/// One **background sync round** (G31) — plain Dart, no `package:matrix`, so
/// it is unit-tested offline against the fake relay and in-memory Drift.
///
/// To-device messages queue on the homeserver and are only fetched while
/// MoneyLedger runs. On Android a periodic WorkManager task (see
/// `background_sync_native.dart`) therefore starts a headless engine every
/// ~15 min and calls [runBackgroundRound] with the real Matrix session; the
/// round reuses the app's own sync components ([LedgerSyncer] applies inbound
/// records, [SyncEngine] answers digests / resync requests) in a private
/// [ProviderContainer], then shuts everything down again.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../features/auth/auth_provider.dart';
import '../../features/expenses/expenses_provider.dart';
import '../../features/expenses/ledger_syncer.dart';
import '../../features/history/restore_points.dart';
import '../../features/history/snapshot_store.dart';
import '../database/app_database.dart';
import '../database/daos/settings_dao.dart';
import '../database/daos/link_dao.dart';
import '../database/daos/sync_states_dao.dart';
import '../link/link_sync_engine.dart';
import '../matrix/ledger_transport.dart';
import '../matrix/transport_provider.dart';
import '../session/app_session.dart';
import '../session/local_transport.dart';
import '../sync/self_recovery.dart';
import '../sync/sync_engine.dart';

/// The Android WorkManager period (the platform minimum).
const kBackgroundSyncPeriod = Duration(minutes: 15);

/// Hard bound for one background round (fetch + process + answer + shutdown).
const kBackgroundRoundTimeout = Duration(seconds: 60);

/// G18 review: how long a stopped round waits for a step still in flight
/// (a `/sync`, a digest broadcast, the session being opened) before closing
/// the stores under it.
const kBackgroundInFlightGrace = Duration(seconds: 10);

/// G58: the daily snapshot at the end of a round is skipped when less than
/// this is left of the round's time budget (it waits for the next round /
/// app start — exporting a big ledger takes a moment).
const kBackgroundSnapshotMinRemaining = Duration(seconds: 10);

/// G52 step 8: the link phase's full fetch waits at most this long per relay
/// for `EOSE` (design doc §8.3).
const kBackgroundLinkFetchTimeout = Duration(seconds: 10);

/// G52 step 8: which ledger a round syncs, from the device preferences.
enum BackgroundLedger {
  /// The signed-in Matrix account's ledger (Matrix phase + link phase).
  matrix,

  /// Local mode's ledger (G40) — link phase only, no Matrix client is built.
  local,

  /// Nothing to sync now (e.g. local mode connecting an account) — skipped.
  none,
}

/// A signed-in relay session opened for one background round — the real one
/// wraps a Matrix `Client` restored from its store (never logged in/out here).
abstract interface class BackgroundSession {
  /// The signed-in account's MXID.
  String get userId;

  /// The relay; inbound payloads fetched by [fetchOnce] arrive on its
  /// `onMessage` (buffered until the sync components listen).
  LedgerTransport get transport;

  /// One `/sync` round: fetches the to-device messages queued on the
  /// homeserver. [wait] is the server long-poll timeout (zero = return at
  /// once).
  Future<void> fetchOnce({Duration wait = Duration.zero});

  /// Stops the session and closes its store — **without logging out**.
  Future<void> close();
}

/// How a round ended.
enum BackgroundRoundStatus {
  /// The app (or another round) owns the stores right now — nothing done.
  skippedBusy,

  /// No account is signed in on this device.
  skippedSignedOut,

  /// The signed-in account turned background sync off.
  skippedDisabled,

  /// G52 step 8: local mode without a link group — nothing to sync.
  skippedNothingToSync,

  /// Fetched, processed and answered everything, then shut down.
  completed,

  /// Stopped at the time budget (work so far is kept; the rest waits for the
  /// next round / the app).
  timedOut,

  /// Stopped early on request (the app came to the foreground).
  aborted,

  /// Opening the session / database failed.
  failed,
}

class BackgroundRoundResult {
  final BackgroundRoundStatus status;

  /// Inbound ledger payloads seen during the round.
  final int received;

  /// Payloads sent (digest answers, repairs, bootstraps, own digests).
  final int sent;

  /// Whether the round broadcast its own digests (the last one was stale).
  final bool broadcastDigests;

  /// G58: whether the round wrote today's snapshot (restore point).
  final bool snapshot;

  /// G52 step 8: whether the link phase ran (fetch + publish) to the end.
  final bool link;

  /// G52 step 8: link events fetched / merged by the link phase.
  final int linkEvents;
  final int linkMerged;

  const BackgroundRoundResult(
    this.status, {
    this.received = 0,
    this.sent = 0,
    this.broadcastDigests = false,
    this.snapshot = false,
    this.link = false,
    this.linkEvents = 0,
    this.linkMerged = 0,
  });

  @override
  String toString() =>
      'BackgroundRoundResult(${status.name}, '
      'received: $received, sent: $sent, digests: $broadcastDigests, '
      'snapshot: $snapshot, link: $link ($linkMerged/$linkEvents merged))';
}

/// Runs one background round. Every dependency is injected:
///
/// - [tryAcquire] — the concurrency guard: returns false when the app is in
///   the foreground (or another round runs) and the round must not touch the
///   Matrix store / ledger DB at all. Called first, before anything is opened.
/// - [openSession] — restores the relay session; `null` = signed out.
/// - [openDatabase] — opens the account's ledger DB (per account, G4).
/// - [abort] — completes when the round must stop early (app started).
/// - [snapshotStores] — G58: the snapshot store of a ledger DB (by name,
///   `createPlatformSnapshotStore` on Android). After the sync work the
///   round takes the **daily snapshot** like an app start does
///   ([RestorePointsService.snapshotIfDue]: once per local day — shared
///   `snapshot_checked_day` with the app —, only if the ledger changed and
///   has a group, 7 daily + 4 weekly kept). Null = no snapshots. Skipped
///   when less than [snapshotMinRemaining] of the budget is left; stopped
///   midway, it writes nothing more (the file write itself is atomic).
/// - [whichLedger] — G52 step 8: matrix / local / none, read from the
///   device preferences **before** anything is opened (null = matrix). In
///   local mode no Matrix session is opened at all ([openSession] isn't
///   called); [openLocalDatabase] opens local mode's ledger.
/// - [linkOverrides] — G52 step 8: overrides for the link sync engine
///   (tests: the fake relays, clock). The round always runs it in
///   [linkBackgroundRoundProvider] mode (no live subscription, no automatic
///   publishes) and without NIP-11 fetches (the app start refreshes them).
/// - [abortRequests] — G18 review 2: cancels the session's homeserver
///   requests in flight (closes its HTTP client). Called when the round is
///   stopped, **before** it waits for the step in flight and closes the
///   stores: a request may take up to `kHttpHeaderTimeout` (90 s), far
///   longer than [inFlightGrace] — aborted, the step fails at once instead
///   of finishing (and writing) after the stores were closed.
///
/// Steps: open the session and the account DB; start [LedgerSyncer] +
/// [SyncEngine] (no startup digest); fetch once and wait until the relay is
/// quiet (all answers sent); broadcast our own digests only if the last one
/// is older than [digestMaxAge]; fetch again (with a short long-poll, picking
/// up peers' immediate answers) while the previous pass produced traffic, at
/// most [maxFetches] times (the **Matrix phase**, only with a session). Then
/// the **link phase** (G52 step 8, design doc §8.3) when the ledger has a
/// link channel — in local mode too: one full fetch of every link group's
/// topics on every relay (`EOSE` or [linkFetchTimeout]) merged through the
/// link path, then publish what changed (`LinkSyncEngine.publishAll`). Then
/// the daily snapshot; then dispose and close everything. The whole round
/// is bounded by [timeout].
///
/// G18 review: when the round is stopped (time budget / [abort]) while a step
/// is still running, it waits up to [inFlightGrace] for that step before it
/// disposes the sync components and closes the DB + session — a step must
/// never keep using stores that are being closed (or, once the slot is
/// released, that the app has reopened). A session still being opened is
/// awaited (bounded the same way) and closed before the round returns.
Future<BackgroundRoundResult> runBackgroundRound({
  required Future<bool> Function() tryAcquire,
  required Future<BackgroundSession?> Function() openSession,
  required AppDatabase Function(String mxid) openDatabase,
  Future<BackgroundLedger> Function()? whichLedger,
  AppDatabase Function()? openLocalDatabase,
  List<Override> linkOverrides = const [],
  Duration linkFetchTimeout = kBackgroundLinkFetchTimeout,
  Future<void>? abort,
  void Function()? abortRequests,
  SnapshotStore? Function(String dbName)? snapshotStores,
  Duration snapshotMinRemaining = kBackgroundSnapshotMinRemaining,
  Duration timeout = kBackgroundRoundTimeout,
  Duration quietPeriod = const Duration(seconds: 2),
  Duration pokeDebounce = const Duration(milliseconds: 300),
  Duration followUpWait = const Duration(seconds: 5),
  Duration digestMaxAge = kBackgroundSyncPeriod,
  int maxFetches = 3,
  Duration inFlightGrace = kBackgroundInFlightGrace,
  int Function()? clock,
}) async {
  final now = clock ?? () => DateTime.now().millisecondsSinceEpoch;
  if (!await tryAcquire()) {
    debugPrint('[bg] skipped: app in foreground / round already running');
    return const BackgroundRoundResult(BackgroundRoundStatus.skippedBusy);
  }

  final deadline = DateTime.now().add(timeout);
  var aborted = false;
  final stop = Completer<void>();
  final budget = Timer(timeout, () {
    if (!stop.isCompleted) stop.complete();
  });
  unawaited(
    abort?.then((_) {
      aborted = true;
      if (!stop.isCompleted) stop.complete();
    }),
  );

  /// The step currently running (completes, never throws) — awaited before
  /// the stores are closed.
  Future<void>? inFlight;

  /// Awaits [f] unless the round is stopped first. Returns false if stopped.
  /// [touchesStores]: false for a pure wait (nothing to settle before close).
  Future<bool> guard(Future<void> f, {bool touchesStores = true}) async {
    var done = false;
    // G18 review 2: typed `void` — the error handler used to return null for
    // a Future<bool>, so a failing step threw an ArgumentError instead.
    final step = f.then<void>(
      (_) {
        done = true;
      },
      onError: (Object e) {
        debugPrint('[bg] step failed: $e');
        done = true;
      },
    );
    if (touchesStores) inFlight = step;
    if (stop.isCompleted) return false;
    await Future.any([step, stop.future]);
    return done && !stop.isCompleted;
  }

  void cancelRequests() {
    try {
      abortRequests?.call();
    } catch (e) {
      debugPrint('[bg] aborting requests failed: $e');
    }
  }

  /// Waits (bounded) for a step still running when the round stopped.
  Future<void> settleInFlight() async {
    final step = inFlight;
    if (step == null) return;
    try {
      await step.timeout(inFlightGrace);
    } on TimeoutException {
      debugPrint('[bg] a step is still running — closing anyway');
    } catch (_) {
      // The step's own failure was logged by guard().
    }
  }

  BackgroundSession? session;
  AppDatabase? db;
  ProviderContainer? container;
  TrackingTransport? tracked;
  LinkSyncEngine? linkEngine;
  var broadcast = false;
  var linkDone = false;
  var linkEvents = 0;
  var linkMerged = 0;
  BackgroundRoundResult ended() => _ended(
    aborted,
    tracked,
    broadcast,
    linkEvents: linkEvents,
    linkMerged: linkMerged,
  );
  try {
    // G52 step 8: local mode never builds a Matrix client (G40/G79) — decide
    // before anything is opened.
    BackgroundLedger ledger;
    try {
      ledger = whichLedger == null
          ? BackgroundLedger.matrix
          : await whichLedger();
    } catch (e) {
      debugPrint('[bg] could not read the device preferences: $e');
      return const BackgroundRoundResult(BackgroundRoundStatus.failed);
    }
    if (ledger == BackgroundLedger.none ||
        (ledger == BackgroundLedger.local && openLocalDatabase == null)) {
      debugPrint('[bg] skipped: no ledger to sync right now');
      return const BackgroundRoundResult(
        BackgroundRoundStatus.skippedSignedOut,
      );
    }
    final local = ledger == BackgroundLedger.local;

    if (!local) {
      try {
        final opening = openSession();
        final first = await Future.any<Object?>([
          opening,
          stop.future.then((_) => _stopped),
        ]);
        if (identical(first, _stopped)) {
          // Timed out / aborted while restoring: close it once it's open —
          // before returning (the caller releases the slot after we return).
          cancelRequests();
          try {
            final s = await opening.timeout(inFlightGrace);
            await s?.close();
          } catch (e) {
            debugPrint('[bg] session still opening / close failed: $e');
          }
          return BackgroundRoundResult(
            aborted
                ? BackgroundRoundStatus.aborted
                : BackgroundRoundStatus.timedOut,
          );
        }
        session = first as BackgroundSession?;
      } catch (e) {
        debugPrint('[bg] could not open the Matrix session: $e');
        return const BackgroundRoundResult(BackgroundRoundStatus.failed);
      }
      if (session == null || session.userId.isEmpty) {
        debugPrint('[bg] skipped: signed out');
        return const BackgroundRoundResult(
          BackgroundRoundStatus.skippedSignedOut,
        );
      }
    }
    final identity = local ? kLocalAccountId : session!.userId;
    var hasLinks = false;
    try {
      final opened = db = local ? openLocalDatabase!() : openDatabase(identity);
      if (!await SettingsDao(opened).backgroundSyncEnabled()) {
        debugPrint('[bg] skipped: background sync disabled for $identity');
        return const BackgroundRoundResult(
          BackgroundRoundStatus.skippedDisabled,
        );
      }
      hasLinks = (await LinkDao(opened).getAllChannels()).isNotEmpty;
    } catch (e) {
      debugPrint('[bg] could not open the ledger DB: $e');
      return const BackgroundRoundResult(BackgroundRoundStatus.failed);
    }
    if (local && !hasLinks) {
      debugPrint('[bg] skipped: local mode without link groups');
      return const BackgroundRoundResult(
        BackgroundRoundStatus.skippedNothingToSync,
      );
    }

    final s = session;
    final t = tracked = s == null ? null : TrackingTransport(s.transport);
    final LedgerTransport transport = t ?? LocalOnlyTransport('');
    final openedDb = db;
    final c = container = ProviderContainer(
      overrides: [
        accountUserIdProvider.overrideWithValue(local ? null : identity),
        // G40: a round only ever syncs the ledger it opened.
        localModeActiveProvider.overrideWithValue(local),
        ledgerIdentityProvider.overrideWithValue(identity),
        accountDatabaseOpenerProvider.overrideWithValue((_) => openedDb),
        localDatabaseOpenerProvider.overrideWithValue(() => openedDb),
        ledgerTransportProvider.overrideWith((ref) async => transport),
        // No periodic timer inside a round, a short ack debounce (the round
        // must see the ack digests go out before it shuts down), no startup
        // digest (decided below), no new-device retry loop.
        syncIntervalProvider.overrideWithValue(const Duration(days: 1)),
        pokeDebounceProvider.overrideWithValue(pokeDebounce),
        digestOnStartProvider.overrideWithValue(false),
        selfResyncRetryDelaysProvider.overrideWithValue(const []),
        if (snapshotStores != null)
          snapshotStoreFactoryProvider.overrideWithValue(snapshotStores),
        // G52 step 8: the link engine only does what the round asks for.
        linkBackgroundRoundProvider.overrideWithValue(true),
        linkRelayInfoFetcherProvider.overrideWithValue(null),
        ...linkOverrides,
      ],
    );
    debugPrint('[bg] round started for $identity');

    // ── Matrix phase (only with a session) ──────────────────────────────
    if (s != null && t != null) {
      c.listen(ledgerSyncerProvider, (_, _) {});
      c.listen(syncEngineProvider, (_, _) {});
      final engine = c.read(syncEngineProvider);
      if (!await guard(
        Future.wait([c.read(ledgerSyncerProvider).ready, engine.ready]),
      )) {
        return ended();
      }

      Future<bool> waitQuiet() =>
          guard(t.quiet(quietPeriod, deadline: deadline), touchesStores: false);

      var activityBefore = t.activity;
      if (!await guard(s.fetchOnce())) return ended();
      if (!await waitQuiet()) return ended();

      // Our own periodic digest — only when the last one is stale (answering
      // a peer's digest during this round already counts as a fresh one).
      final lastDigest = await SyncStatesDao(openedDb).latestDigestSentAt();
      if (now() - lastDigest >= digestMaxAge.inMilliseconds) {
        broadcast = true;
        if (!await guard(engine.broadcastDigests())) return ended();
        if (!await waitQuiet()) return ended();
      }

      // Follow-up fetches: answers / repairs from peers that are online
      // right now arrive within seconds. Stop once a pass brings no traffic.
      var fetches = 1;
      while (fetches < maxFetches && t.activity != activityBefore) {
        activityBefore = t.activity;
        fetches++;
        if (!await guard(s.fetchOnce(wait: followUpWait))) return ended();
        if (!await waitQuiet()) return ended();
      }
    }

    // ── link phase (G52 step 8, design doc §8.3) ────────────────────────
    if (hasLinks) {
      c.listen(linkSyncEngineProvider, (_, _) {});
      final link = c.read(linkSyncEngineProvider);
      linkEngine = link;
      if (!await guard(link.ready)) return ended();
      if (!await guard(
        link.refresh(timeout: linkFetchTimeout).then((r) {
          linkEvents = r.events;
          linkMerged = r.merged;
        }),
      )) {
        return ended();
      }
      // Publish what changed (incl. a due 10-day refresh) — after the merge,
      // so our snapshot already carries the peers' versions.
      if (!await guard(link.publishAll())) return ended();
      linkDone = true;
    }

    // G58: the daily restore point — the app may not be opened for days.
    var snapshot = false;
    if (snapshotStores != null) {
      if (deadline.difference(DateTime.now()) < snapshotMinRemaining) {
        debugPrint('[bg] snapshot skipped: round budget almost used up');
      } else {
        final service = c
            .listen(restorePointsServiceProvider, (_, _) {})
            .read();
        if (!await guard(
          service
              .snapshotIfDue(
                DateTime.fromMillisecondsSinceEpoch(now()),
                cancelled: () => stop.isCompleted,
              )
              .then((wrote) => snapshot = wrote),
        )) {
          return ended();
        }
      }
    }
    final result = BackgroundRoundResult(
      BackgroundRoundStatus.completed,
      received: t?.received ?? 0,
      sent: t?.sent ?? 0,
      broadcastDigests: broadcast,
      snapshot: snapshot,
      link: linkDone,
      linkEvents: linkEvents,
      linkMerged: linkMerged,
    );
    debugPrint('[bg] round done: $result');
    return result;
  } finally {
    budget.cancel();
    // Stopped early: cut the requests in flight first, so the step settles
    // now instead of writing into closed stores later (G18 review 2) — the
    // link engine's relay connections too (disposing it closes its pool;
    // its steps bail at their next await).
    if (stop.isCompleted) {
      cancelRequests();
      linkEngine?.dispose();
    }
    await settleInFlight();
    // Order matters: stop the sync components first, then close the ledger
    // DB, then the session (its store holds the Olm sessions — closed last,
    // after every send has been handed over).
    container?.dispose();
    try {
      await db?.close();
    } catch (_) {}
    try {
      await session?.close();
    } catch (e) {
      debugPrint('[bg] session close failed: $e');
    }
    tracked?.dispose();
  }
}

/// Sentinel: the round was stopped while a step was still pending.
const Object _stopped = Object();

BackgroundRoundResult _ended(
  bool aborted,
  TrackingTransport? t,
  bool broadcast, {
  int linkEvents = 0,
  int linkMerged = 0,
}) {
  final status = aborted
      ? BackgroundRoundStatus.aborted
      : BackgroundRoundStatus.timedOut;
  final result = BackgroundRoundResult(
    status,
    received: t?.received ?? 0,
    sent: t?.sent ?? 0,
    broadcastDigests: broadcast,
    linkEvents: linkEvents,
    linkMerged: linkMerged,
  );
  debugPrint('[bg] round stopped early: $result');
  return result;
}

/// Wraps the session's transport to observe traffic: inbound payloads and
/// sends (in flight + completed) — the round is "quiet" when nothing moved
/// for a while and no send is pending. Public only for its unit test
/// (`test/core/tracking_transport_test.dart`); [now] is injectable so the
/// test drives the clock with `fakeAsync`.
@visibleForTesting
class TrackingTransport implements LedgerTransport {
  TrackingTransport(this._inner, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _lastActivity = _now();
  }

  final LedgerTransport _inner;
  final DateTime Function() _now;

  /// Inbound payloads already counted — the mapped stream runs once per
  /// listener (LedgerSyncer + SyncEngine), each payload counts once. (No own
  /// listener: the first listener triggers the inbox replay, which must reach
  /// the sync components.)
  final Set<TransportMessage> _seen = Set.identity();
  int received = 0;
  int sent = 0;
  int _inFlight = 0;

  /// Bumped on every inbound payload and every send start / end.
  int activity = 0;
  late DateTime _lastActivity;

  void _touch() {
    activity++;
    _lastActivity = _now();
  }

  @override
  String get userId => _inner.userId;

  @override
  RecordCrypto get crypto => _inner.crypto;

  @override
  DeviceKeyDirectory get deviceKeys => _inner.deviceKeys;

  @override
  Stream<TransportMessage> get onMessage => _inner.onMessage.map((m) {
    if (_seen.add(m)) received++;
    _touch();
    return m;
  });

  @override
  Future<SendResult> sendToUsers(
    Set<String> userIds,
    String type,
    Map<String, dynamic> content, {
    DeliveryPolicy policy = DeliveryPolicy.everyone,
  }) async {
    _inFlight++;
    _touch();
    try {
      final r = await _inner.sendToUsers(
        userIds,
        type,
        content,
        policy: policy,
      );
      sent++;
      return r;
    } finally {
      _inFlight--;
      _touch();
    }
  }

  @override
  Future<String?> profileName(String matrixId) => _inner.profileName(matrixId);

  /// Completes once no send is in flight and nothing happened for [period]
  /// **since this call** (or at [deadline]). Measuring from the call too, not
  /// only from the last activity, matters on a slow / loaded device: opening
  /// the DB and attaching the sync components can take longer than [period],
  /// and the inbox replay of payloads queued while the app was closed is only
  /// scheduled once they attach — without this the round could judge itself
  /// "quiet" before that replay ran and shut down without applying it (G15).
  Future<void> quiet(Duration period, {required DateTime deadline}) async {
    const tick = Duration(milliseconds: 50);
    final start = _now();
    while (_now().isBefore(deadline)) {
      final since = _lastActivity.isAfter(start) ? _lastActivity : start;
      if (_inFlight == 0 && _now().difference(since) >= period) {
        return;
      }
      await Future<void>.delayed(tick);
    }
  }

  void dispose() => _seen.clear();
}
