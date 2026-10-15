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

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/expenses/expenses_provider.dart';
import '../../features/expenses/ledger_syncer.dart';
import '../database/app_database.dart';
import '../database/daos/settings_dao.dart';
import '../database/daos/sync_states_dao.dart';
import '../matrix/ledger_transport.dart';
import '../matrix/transport_provider.dart';
import '../sync/self_recovery.dart';
import '../sync/sync_engine.dart';

/// The Android WorkManager period (the platform minimum).
const kBackgroundSyncPeriod = Duration(minutes: 15);

/// Hard bound for one background round (fetch + process + answer + shutdown).
const kBackgroundRoundTimeout = Duration(seconds: 60);

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

  const BackgroundRoundResult(
    this.status, {
    this.received = 0,
    this.sent = 0,
    this.broadcastDigests = false,
  });

  @override
  String toString() => 'BackgroundRoundResult(${status.name}, '
      'received: $received, sent: $sent, digests: $broadcastDigests)';
}

/// Runs one background round. Every dependency is injected:
///
/// - [tryAcquire] — the concurrency guard: returns false when the app is in
///   the foreground (or another round runs) and the round must not touch the
///   Matrix store / ledger DB at all. Called first, before anything is opened.
/// - [openSession] — restores the relay session; `null` = signed out.
/// - [openDatabase] — opens the account's ledger DB (per account, G4).
/// - [abort] — completes when the round must stop early (app started).
///
/// Steps: open the session and the account DB; start [LedgerSyncer] +
/// [SyncEngine] (no startup digest); fetch once and wait until the relay is
/// quiet (all answers sent); broadcast our own digests only if the last one
/// is older than [digestMaxAge]; fetch again (with a short long-poll, picking
/// up peers' immediate answers) while the previous pass produced traffic, at
/// most [maxFetches] times; then dispose and close everything. The whole
/// round is bounded by [timeout].
Future<BackgroundRoundResult> runBackgroundRound({
  required Future<bool> Function() tryAcquire,
  required Future<BackgroundSession?> Function() openSession,
  required AppDatabase Function(String mxid) openDatabase,
  Future<void>? abort,
  Duration timeout = kBackgroundRoundTimeout,
  Duration quietPeriod = const Duration(seconds: 2),
  Duration pokeDebounce = const Duration(milliseconds: 300),
  Duration followUpWait = const Duration(seconds: 5),
  Duration digestMaxAge = kBackgroundSyncPeriod,
  int maxFetches = 3,
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
  unawaited(abort?.then((_) {
    aborted = true;
    if (!stop.isCompleted) stop.complete();
  }));

  /// Awaits [f] unless the round is stopped first. Returns false if stopped.
  Future<bool> guard(Future<void> f) async {
    if (stop.isCompleted) return false;
    var done = false;
    await Future.any([
      f.then((_) => done = true, onError: (Object e) {
        debugPrint('[bg] step failed: $e');
        done = true;
      }),
      stop.future,
    ]);
    return done && !stop.isCompleted;
  }

  BackgroundSession? session;
  AppDatabase? db;
  ProviderContainer? container;
  _TrackingTransport? tracked;
  var broadcast = false;
  try {
    try {
      final opening = openSession();
      final first = await Future.any<Object?>(
          [opening, stop.future.then((_) => _stopped)]);
      if (identical(first, _stopped)) {
        // Timed out / aborted while restoring: close it once it's open.
        unawaited(opening.then((s) => s?.close(), onError: (_) {}));
        return BackgroundRoundResult(aborted
            ? BackgroundRoundStatus.aborted
            : BackgroundRoundStatus.timedOut);
      }
      session = first as BackgroundSession?;
    } catch (e) {
      debugPrint('[bg] could not open the Matrix session: $e');
      return const BackgroundRoundResult(BackgroundRoundStatus.failed);
    }
    if (session == null || session.userId.isEmpty) {
      debugPrint('[bg] skipped: signed out');
      return const BackgroundRoundResult(
          BackgroundRoundStatus.skippedSignedOut);
    }
    final mxid = session.userId;
    try {
      db = openDatabase(mxid);
      if (!await SettingsDao(db).backgroundSyncEnabled()) {
        debugPrint('[bg] skipped: background sync disabled for $mxid');
        return const BackgroundRoundResult(
            BackgroundRoundStatus.skippedDisabled);
      }
    } catch (e) {
      debugPrint('[bg] could not open the ledger DB: $e');
      return const BackgroundRoundResult(BackgroundRoundStatus.failed);
    }

    final t = tracked = _TrackingTransport(session.transport);
    final openedDb = db;
    final c = container = ProviderContainer(overrides: [
      accountUserIdProvider.overrideWithValue(mxid),
      accountDatabaseOpenerProvider.overrideWithValue((_) => openedDb),
      ledgerTransportProvider.overrideWith((ref) async => t),
      // No periodic timer inside a round, a short ack debounce (the round
      // must see the ack digests go out before it shuts down), no startup
      // digest (decided below), no new-device retry loop.
      syncIntervalProvider.overrideWithValue(const Duration(days: 1)),
      pokeDebounceProvider.overrideWithValue(pokeDebounce),
      digestOnStartProvider.overrideWithValue(false),
      selfResyncRetryDelaysProvider.overrideWithValue(const []),
    ]);
    c.listen(ledgerSyncerProvider, (_, _) {});
    c.listen(syncEngineProvider, (_, _) {});
    final engine = c.read(syncEngineProvider);
    if (!await guard(Future.wait(
        [c.read(ledgerSyncerProvider).ready, engine.ready]))) {
      return _ended(aborted, t, broadcast);
    }

    Future<bool> waitQuiet() =>
        guard(t.quiet(quietPeriod, deadline: deadline));

    debugPrint('[bg] round started for $mxid');
    var activityBefore = t.activity;
    if (!await guard(session.fetchOnce())) {
      return _ended(aborted, t, broadcast);
    }
    if (!await waitQuiet()) return _ended(aborted, t, broadcast);

    // Our own periodic digest — only when the last one is stale (answering a
    // peer's digest during this round already counts as a fresh one).
    final lastDigest = await SyncStatesDao(openedDb).latestDigestSentAt();
    if (now() - lastDigest >= digestMaxAge.inMilliseconds) {
      broadcast = true;
      if (!await guard(engine.broadcastDigests())) {
        return _ended(aborted, t, broadcast);
      }
      if (!await waitQuiet()) return _ended(aborted, t, broadcast);
    }

    // Follow-up fetches: answers / repairs from peers that are online right
    // now arrive within seconds. Stop once a pass brings no traffic.
    var fetches = 1;
    while (fetches < maxFetches && t.activity != activityBefore) {
      activityBefore = t.activity;
      fetches++;
      if (!await guard(session.fetchOnce(wait: followUpWait))) {
        return _ended(aborted, t, broadcast);
      }
      if (!await waitQuiet()) return _ended(aborted, t, broadcast);
    }
    final result = BackgroundRoundResult(BackgroundRoundStatus.completed,
        received: t.received, sent: t.sent, broadcastDigests: broadcast);
    debugPrint('[bg] round done: $result');
    return result;
  } finally {
    budget.cancel();
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
    bool aborted, _TrackingTransport t, bool broadcast) {
  final status = aborted
      ? BackgroundRoundStatus.aborted
      : BackgroundRoundStatus.timedOut;
  final result = BackgroundRoundResult(status,
      received: t.received, sent: t.sent, broadcastDigests: broadcast);
  debugPrint('[bg] round stopped early: $result');
  return result;
}

/// Wraps the session's transport to observe traffic: inbound payloads and
/// sends (in flight + completed) — the round is "quiet" when nothing moved
/// for a while and no send is pending.
class _TrackingTransport implements LedgerTransport {
  _TrackingTransport(this._inner);

  final LedgerTransport _inner;

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
  DateTime _lastActivity = DateTime.now();

  void _touch() {
    activity++;
    _lastActivity = DateTime.now();
  }

  @override
  String get userId => _inner.userId;

  @override
  Stream<TransportMessage> get onMessage =>
      _inner.onMessage.map((m) {
        if (_seen.add(m)) received++;
        _touch();
        return m;
      });

  @override
  Future<SendResult> sendToUsers(
      Set<String> userIds, String type, Map<String, dynamic> content) async {
    _inFlight++;
    _touch();
    try {
      final r = await _inner.sendToUsers(userIds, type, content);
      sent++;
      return r;
    } finally {
      _inFlight--;
      _touch();
    }
  }

  /// Completes once no send is in flight and nothing happened for [period]
  /// (or at [deadline]).
  Future<void> quiet(Duration period, {required DateTime deadline}) async {
    const tick = Duration(milliseconds: 50);
    while (DateTime.now().isBefore(deadline)) {
      if (_inFlight == 0 &&
          DateTime.now().difference(_lastActivity) >= period) {
        return;
      }
      await Future<void>.delayed(tick);
    }
  }

  void dispose() => _seen.clear();
}
