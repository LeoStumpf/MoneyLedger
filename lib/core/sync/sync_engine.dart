import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/expenses/expenses_provider.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../database/app_database.dart';
import '../session/app_session.dart' show isLocalAccountId;
import '../session/device_prefs.dart' show devicePrefsProvider;
import 'pending_signer.dart';
import '../database/daos/expenses_dao.dart';
import '../database/daos/groups_dao.dart';
import '../database/daos/link_dao.dart';
import '../database/daos/members_dao.dart';
import '../database/daos/settings_dao.dart';
import '../database/daos/signing_dao.dart';
import '../database/daos/sync_states_dao.dart';
import '../matrix/ledger_transport.dart';
import '../matrix/transport_provider.dart';
import 'delivery_policy.dart';
import 'ledger_payloads.dart';
import 'left_groups.dart';
import 'payload_budget.dart';
import 'record_gate.dart';
import 'record_validation.dart' show isValidMxid;
import 'record_verifier.dart';
import 'record_version.dart';
import 'self_recovery.dart';
import 'sync_health.dart';

/// How often each group's digest is broadcast to its members. Injectable so
/// tests can disable/shorten it.
final syncIntervalProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 10),
);

/// Debounce between receiving a ledger payload and sending the "ack" digest.
final pokeDebounceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// G36: the shorter debounce for the ack digest after a **live record**
/// (expense / settlement / member / meta) from a peer — the writer shows
/// "waiting" until our digest arrives, and the 5 s [pokeDebounceProvider] was
/// half of that wait. Bootstraps (many parts) keep the long debounce, and so
/// does a second ack for the same group within [kFastAckMinGap] (a stream of
/// edits still coalesces). Never longer than [pokeDebounceProvider].
final ackDebounceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 1),
);

/// G36: at most one fast ack per group per this window.
const kFastAckMinGap = Duration(seconds: 10);

/// Whether [SyncEngine.start] broadcasts every group's digest right away. The
/// app does (a fresh start announces its state); the Android background round
/// (G31) turns it off and decides itself — it only broadcasts when the last
/// digest is older than the background period.
final digestOnStartProvider = Provider<bool>((ref) => true);

/// Rule 5 asks a digest's sender to bootstrap us into a group we don't know.
/// A burst of digests naming the same unknown group (several peers / devices
/// answering at once) must not fan out into one resync_request each: per group
/// we ask at most once per this window (the bootstrap answer makes the group
/// known; a lost answer is retried by the next digest after the window).
const kGroupResyncCooldown = Duration(seconds: 30);

/// G36: a `resync_request` is answered at most once per (requesting device,
/// scope/group) within this window. A device that was offline gets every
/// queued request at once (a new device's request + its G30 retries, or
/// several peers' digests naming an unknown group) — each used to be answered
/// with a full bootstrap. The first answer reaches the requesting device; a
/// genuinely lost one is retried by the requester after the window.
final resyncAnswerWindowProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 60),
);

final syncEngineProvider = Provider.autoDispose<SyncEngine>((ref) {
  // Rebuild (dispose + restart) when the signed-in account's ledger DB is
  // swapped (G4), so it never keeps reading/writing a closed or foreign DB.
  ref.watch(appDatabaseProvider);
  final engine = SyncEngine(ref);
  engine.start();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Anti-entropy for the roomless relay (Phase C). The Drift DB is the
/// replication log: peers periodically exchange per-group digests
/// (`{recordId: updatedAt}`, tombstones included) and re-send exactly the
/// records the other side lacks — so a lost to-device message, however it was
/// lost, is repaired by the next digest cycle instead of diverging forever.
///
/// Digest receiver rules (protocol v2):
/// 1. Records where our copy is newer / the sender lacks them → re-send the
///    normal record payload to the sender (targeted repair; LedgerSyncer on
///    their side applies it LWW).
/// 2. The digest's `members` map is applied via LWW (membership gossip — fixes
///    the case where the introducer of a member goes offline before telling
///    the others).
/// 3. A digest with `reply: false` is always answered with our own digest
///    marked `reply: true`; replies are never answered (bounded two-message
///    exchange — residual divergence is caught by the next periodic cycle).
/// 4. A digest that exactly matches our state records `lastInSyncAt` for
///    (group, sender) — this feeds the sync-status UI. (`LedgerSyncer` can
///    prove the same earlier from an inbound record — G29,
///    `peer_convergence.dart`.)
/// 5. A digest for a group we don't know → `resync_request` back to the
///    sender (they bootstrap us if we're a member).
/// 6. A digest from a sender we have as `removed` → reply only with their
///    member-tombstone payload so their device learns of the removal.
/// 7. A digest for a group we **left / deleted** (a [LeftGroupTombstone], G9)
///    never triggers rule 5 — the group stays gone — unless the digest lists
///    our MXID `active` with a clock newer than the tombstone (we were
///    **re-added**): then rule 5 applies as usual. If the digest instead still
///    lists us `active` with an older clock (the peer missed our leave notice)
///    and we left (not merely deleted), we re-send our stored `removed` member
///    payload to the sender, nothing else.
/// 8. (G6) A digest from an account that is **not a participant** of the
///    group at all is ignored — no member gossip, no repair, no reply (it used
///    to fall through to rules 1–3). Rule 2's member entries are signed
///    versions and go through the same verification as live records
///    ([RecordGate]). The digest's `rejected` map lists versions the sender
///    refused: rule 1 doesn't re-send a record whose version the sender
///    already refused, and rule 4 treats such "agree to disagree" entries as
///    matching (see [compareDigest]) — so a refused version never loops.
/// 9. (G14) **Bucketed digests.** A digest that doesn't fit one to-device
///    message ([payloadBudgetProvider], see `payload_budget.dart`) is sent
///    as bucket hashes ([buildDigestMessages]): `bucket_bits`, the hash of
///    every bucket, and full entries only for its `detail` buckets. The
///    receiver compares hashes; matching buckets are in sync, `detail`
///    buckets are compared (rule 1 repairs within them), the rest are
///    *unresolved*. Exchange (bounded to three messages):
///    primary (summary, no detail) → reply detailing our unresolved +
///    differing buckets (same bits) → one `final` digest detailing those
///    same buckets, so the replier learns what it lacks too; `final` is never
///    answered. A reply to a bucketed digest is always bucketed; a reply to a
///    flat one is flat when it fits. Rule 4 needs no unresolved bucket.
/// 10. (G52) A **link-only** group (`group_policy.dart`: this device's link
///    channel + an unsigned meta) has no Matrix side: no digests, bootstraps
///    or resync answers for it, no pending-row signing; inbound digests /
///    resync requests naming it are ignored (also while joining it — a
///    channel without meta yet). A Matrix group can't become link-only by
///    inbound data — the channel is device-local, created by the user.
///
/// G27: records compare by `(updated_at, content hash)` — digest entries are
/// `"<updated_at>:<hash8>"` (plus `meta_hash`; members are hashed from their
/// gossiped versions), so two versions with the same clock are seen as
/// different and the higher hash wins everywhere (`record_version.dart`).
class SyncEngine {
  final Ref _ref;

  /// The account DB this engine was built for and its DAOs, captured once at
  /// construction: every async path uses these instead of re-reading providers
  /// after an await, so a mid-flight account switch (G4) can never make an
  /// old engine read from / write to the *new* account's DB.
  final AppDatabase _db;
  final GroupsDao _groups;
  final MembersDao _members;
  final ExpensesDao _expenses;
  final SyncStatesDao _syncStates;
  final SettingsDao _settings;
  final SigningDao _signing;

  /// G52 (§6.4): link-only groups are skipped entirely — no digests,
  /// bootstraps, resync answers, signing of pending rows.
  final LinkDao _link;

  /// G14: max JSON bytes per to-device message (captured, like the DAOs).
  final int _budget;

  LedgerTransport? _transport;

  /// G6: verifies the digests' member gossip (built in [start]).
  RecordGate? _gate;
  StreamSubscription<TransportMessage>? _sub;
  Timer? _periodic;
  final Map<String, Timer> _pokes = {};
  final Map<String, int> _groupResyncAskedAt = {};

  /// G36: `'<user>|<device>|<scope or group>'` → when we last answered it.
  final Map<String, int> _resyncAnsweredAt = {};
  bool _disposed = false;

  SyncEngine(Ref ref)
    : _ref = ref,
      _db = ref.read(appDatabaseProvider),
      _groups = ref.read(groupsDaoProvider),
      _members = ref.read(membersDaoProvider),
      _expenses = ref.read(expensesDaoProvider),
      _syncStates = ref.read(syncStatesDaoProvider),
      _settings = SettingsDao(ref.read(appDatabaseProvider)),
      _signing = ref.read(signingDaoProvider),
      _link = LinkDao(ref.read(appDatabaseProvider)),
      _budget = ref.read(payloadBudgetProvider);

  /// Whether async work may continue. Checked after **every** await: the
  /// engine may have been disposed (logout / account switch / container
  /// teardown) or its DB closed — on an account switch Riverpod closes the old
  /// DB eagerly, before this engine's own `onDispose` has run.
  bool get _alive => !_disposed && !_db.isClosed;

  final Completer<void> _ready = Completer<void>();

  /// Completes once [start] has subscribed to the transport (or gave up:
  /// signed out / no transport). The background round (G31) waits for it
  /// before fetching, so no inbound payload is processed half-attached.
  Future<void> get ready => _ready.future;

  Future<void> start() async {
    try {
      await _start();
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  Future<void> _start() async {
    // Signed out: there is no account ledger to sync. (Pages that watch this
    // provider directly may still build it during a login/logout transition;
    // starting here would send a spurious empty-DB resync_request — G24.)
    if (_db.isSignedOutPlaceholder) return;
    final LedgerTransport transport;
    try {
      transport = await withDeliveryPolicy(
        _ref.read(ledgerTransportProvider.future),
        _settings,
      );
    } catch (e) {
      if (_alive) debugPrint('[sync] engine inactive, no transport: $e');
      return;
    }
    if (!_alive) return;
    // G40: local mode — no relay, nothing to sync (and no "new device"
    // resync request from the empty local DB).
    if (isLocalAccountId(transport.userId)) return;
    if (kDebugMode) debugPrint('[sync] engine started for ${transport.userId}');
    _transport = transport;
    _gate = RecordGate(
      verifier: RecordVerifier(
        crypto: transport.crypto,
        directory: transport.deviceKeys,
        signing: _signing,
      ),
      signing: _signing,
      groups: _groups,
      members: _members,
      expenses: _expenses,
      // G53: mixed groups accept unsigned versions their members relay.
      matrixPolicy: _link.policyOf,
      isAlive: () => _alive,
    );
    _sub = transport.onMessage.listen(_onMessage);
    // G6: our own device key is first-hand knowledge.
    final me = transport.crypto.identity;
    if (me != null) {
      try {
        await _signing.pinServerKeys({
          me.user: {me.device: me.key},
        });
      } catch (e) {
        if (!_alive) return;
        debugPrint('[sync] pinning own device key failed: $e');
      }
      if (!_alive) return;
    }
    _ready.complete();
    _periodic = Timer.periodic(
      _ref.read(syncIntervalProvider),
      (_) => broadcastDigests(),
    );
    try {
      // New or reinstalled device (empty local DB): ask our own other devices
      // for everything. Groups shared by peers are additionally recovered
      // organically — their digests name groups we don't know (rule 5).
      final groups = await _matrixGroups();
      if (!_alive) return;
      if (groups.isEmpty) {
        _startSelfRecovery();
        return;
      }
    } catch (e) {
      if (!_alive) return;
      debugPrint('[sync] self-resync check failed: $e');
    }
    if (_ref.read(digestOnStartProvider)) await broadcastDigests();
  }

  // ── new-device recovery (G30) ─────────────────────────────────────────────

  /// Pending self-resync retry; null when recovery isn't (or no longer) running.
  Timer? _selfResyncRetry;
  bool _selfRecoveryActive = false;

  /// Empty DB at start: send `resync_request{scope: all}` to our own MXID and
  /// retry with backoff ([selfResyncRetryDelaysProvider]) while the DB stays
  /// empty and no bootstrap has arrived. Our other devices only answer while
  /// the app runs there, so the groups page shows "Restoring…" meanwhile
  /// ([SelfRecovery]) — ended early when a send finds no other own device
  /// (nothing to restore).
  void _startSelfRecovery() {
    _selfRecoveryActive = true;
    _setRestoring(true);
    _selfResyncAttempt(0);
  }

  Future<void> _selfResyncAttempt(int attempt) async {
    final transport = _transport;
    if (transport == null || !_alive || !_selfRecoveryActive) return;
    try {
      if (attempt > 0) {
        final groups = await _matrixGroups();
        if (!_alive || !_selfRecoveryActive) return;
        if (groups.isNotEmpty) {
          _endSelfRecovery();
          return;
        }
      }
      final result = await transport.sendToUsers(
        {transport.userId},
        resyncRequestEventType,
        {'v': protocolVersion, 'scope': 'all'},
      );
      if (!_alive || !_selfRecoveryActive) return;
      if (kDebugMode) {
        debugPrint(
          '[sync] self resync_request #${attempt + 1} → '
          '${result.deviceCount} own device(s)',
        );
      }
      if (result.deviceCount == 0) {
        // No other device of ours exists: there is nobody to restore from.
        // (Groups shared with peers still arrive organically via rule 5.)
        _endSelfRecovery();
        return;
      }
    } catch (e) {
      if (!_alive) return;
      // e.g. encryption not ready right after login — the retry covers it.
      debugPrint('[sync] self resync_request #${attempt + 1} failed: $e');
    }
    final delays = _ref.read(selfResyncRetryDelaysProvider);
    if (attempt >= delays.length) {
      // Out of retries: stop asking. The UI's own timeout ends "Restoring…".
      _selfRecoveryActive = false;
      return;
    }
    _selfResyncRetry = _ref.read(selfRecoveryTimerFactoryProvider)(
      delays[attempt],
      () => _selfResyncAttempt(attempt + 1),
    );
  }

  void _endSelfRecovery() {
    _selfRecoveryActive = false;
    _selfResyncRetry?.cancel();
    _selfResyncRetry = null;
    _setRestoring(false);
  }

  void _setRestoring(bool restoring) {
    if (!_alive || !_ref.mounted) return;
    final notifier = _ref.read(selfRecoveryProvider.notifier);
    if (restoring) {
      notifier.begin(_ref.read(selfRecoveryTimeoutProvider));
    } else {
      notifier.finish();
    }
  }

  void dispose() {
    _disposed = true;
    _selfResyncRetry?.cancel();
    _sub?.cancel();
    _periodic?.cancel();
    for (final t in _pokes.values) {
      t.cancel();
    }
    _pokes.clear();
  }

  /// G52: the groups Matrix syncs — every group but the link-only ones.
  Future<List<GroupModel>> _matrixGroups() async {
    final out = <GroupModel>[];
    for (final g in await _groups.getAllGroups()) {
      if (!_alive) break;
      if (!await _link.isLinkOnly(g.roomId)) out.add(g);
    }
    return out;
  }

  /// Sends a digest for every local group to its active members (G52: not
  /// for link-only groups).
  Future<void> broadcastDigests() async {
    if (!_alive) return;
    try {
      final groups = await _matrixGroups();
      for (final g in groups) {
        if (!_alive) return;
        await _sendDigest(g.roomId);
      }
      if (!_alive) return;
      await _pinMemberDevices(groups.map((g) => g.roomId));
    } catch (e) {
      if (_alive) debugPrint('[sync] digest broadcast failed: $e');
    }
  }

  /// G6: pins the current devices of every active claimed member of
  /// [groupIds] as first-hand key knowledge — proactively, while they exist,
  /// so records they sign stay verifiable after they sign out.
  Future<void> _pinMemberDevices(Iterable<String> groupIds) async {
    final transport = _transport;
    if (transport == null) return;
    final users = <String>{transport.userId};
    for (final g in groupIds) {
      users.addAll(await _members.activeClaimedMatrixIds(g));
      if (!_alive) return;
    }
    try {
      final devices = await transport.deviceKeys
          .currentDevices(users)
          .timeout(const Duration(seconds: 10));
      if (!_alive) return;
      await _signing.pinServerKeys(devices);
    } catch (e) {
      if (_alive) debugPrint('[sync] device-key refresh failed: $e');
    }
  }

  /// G6: signs this group's rows written while the signer wasn't ready
  /// (`pendingSign`, same clock) — they are never sent unsigned.
  ///
  /// G18 review 2: not while a local-ledger adoption into this account is
  /// still pending — the adoption signs those rows itself, with their
  /// creation statements ("added by"); signing them first would lose those
  /// for records edited in local mode.
  Future<void> _signPending(String groupId) async {
    final transport = _transport;
    if (transport == null || transport.crypto.identity == null) return;
    if (_localAdoptionPending(transport.userId)) return;
    await signPendingRows(
      crypto: transport.crypto,
      groups: _groups,
      members: _members,
      expenses: _expenses,
      groupId: groupId,
      isAlive: () => _alive,
    );
  }

  /// Whether the device preferences say the local ledger is still being
  /// adopted into [me] (G40). Only consulted when the app built them — a
  /// background round never does (no adoption runs there).
  bool _localAdoptionPending(String me) {
    try {
      if (!_ref.exists(devicePrefsProvider)) return false;
      return _ref.read(devicePrefsProvider).value?.adoptInto == me;
    } catch (_) {
      return false;
    }
  }

  /// Debounced "something changed in [groupId]": coalesces a burst of inbound
  /// payloads into one digest, which acts as the delivery ack to the writer.
  void pokeGroup(String groupId, {bool liveRecord = false}) {
    if (!_alive) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final delay = pokeDelay(
      liveRecord: liveRecord,
      lastFastAckAt: _fastAckAt[groupId],
      now: now,
      normal: _ref.read(pokeDebounceProvider),
      fast: _ref.read(ackDebounceProvider),
    );
    if (liveRecord && delay < _ref.read(pokeDebounceProvider)) {
      _fastAckAt[groupId] = now;
    }
    _pokes[groupId]?.cancel();
    _pokes[groupId] = Timer(delay, () {
      _pokes.remove(groupId);
      _sendDigest(groupId);
    });
  }

  /// G68 *Sync now* (the group's sync sheet): sends [groupId]'s digest to
  /// its active members right away (a pending poke is dropped) — their
  /// replies repair what differs and mark them in sync.
  Future<void> syncGroupNow(String groupId) async {
    if (!_alive) return;
    _pokes.remove(groupId)?.cancel();
    await _sendDigest(groupId);
  }

  /// G36: when the last fast ack per group was scheduled.
  final Map<String, int> _fastAckAt = {};

  /// G36: the debounce before the ack digest — [fast] after a live record
  /// from a peer unless a fast ack for the group was scheduled less than
  /// [minGap] ago, else [normal]; never longer than [normal].
  @visibleForTesting
  static Duration pokeDelay({
    required bool liveRecord,
    required int? lastFastAckAt,
    required int now,
    required Duration normal,
    required Duration fast,
    Duration minGap = kFastAckMinGap,
  }) {
    if (!liveRecord || fast >= normal) return normal;
    if (lastFastAckAt != null && now - lastFastAckAt < minGap.inMilliseconds) {
      return normal;
    }
    return fast;
  }

  void _onMessage(TransportMessage msg) {
    // G18 review: a plaintext payload's sender isn't authenticated.
    if (!_alive || !msg.encrypted) return;
    switch (msg.type) {
      case digestEventType:
        _onDigest(msg);
      case resyncRequestEventType:
        _onResyncRequest(msg);
      case expenseEventType ||
          settlementEventType ||
          groupMetaEventType ||
          memberEventType ||
          bootstrapEventType:
        final group = msg.content['group'] as String?;
        if (group != null) {
          pokeGroup(group, liveRecord: msg.type != bootstrapEventType);
        }
        // A bootstrap answers our new-device recovery: stop retrying. The
        // "Restoring…" state ends once LedgerSyncer has stored it (the groups
        // list is non-empty) — give it the poke window to land first.
        if (msg.type == bootstrapEventType && _selfRecoveryActive) {
          _selfRecoveryActive = false;
          _selfResyncRetry?.cancel();
          _selfResyncRetry = Timer(_ref.read(pokeDebounceProvider), () {
            if (_alive) _setRestoring(false);
          });
        }
    }
  }

  /// Health reports go to the (account-scoped, G4) [SyncHealth] — but only
  /// while this engine is still the live one, so a stale engine can't leak the
  /// previous account's failures into the next account's state.
  void _reportDelivery(Set<String> targets, SendResult result) {
    if (_alive && _ref.mounted) {
      _ref.read(syncHealthProvider.notifier).reportDelivery(targets, result);
    }
  }

  void _reportFailure(Object e) {
    if (_alive && _ref.mounted) {
      _ref.read(syncHealthProvider.notifier).reportFailure(e);
    }
  }

  /// A repair / answer send (digest-triggered repair, bootstrap reply, removal
  /// notice): its outcome feeds [SyncHealth] like replication and digests do
  /// (G15 — these used to fail with only a debug log). Rethrows so the caller
  /// stops its sequence; only send errors are reported, never a malformed
  /// inbound payload (a peer must not be able to flip our health state).
  Future<void> _sendTracked(
    LedgerTransport transport,
    Set<String> targets,
    String type,
    Map<String, dynamic> content,
  ) async {
    final SendResult result;
    try {
      result = await transport.sendToUsers(targets, type, content);
    } catch (e) {
      _reportFailure(e);
      rethrow;
    }
    _reportDelivery(targets, result);
  }

  Future<void> _sendDigest(
    String groupId, {
    String? onlyTo,
    bool reply = false,
    bool last = false,
    int? bits,
    Set<int> detailBuckets = const {},
    Set<String> detailIds = const {},
  }) async {
    final transport = _transport;
    if (transport == null || !_alive) return;
    try {
      // G52: a link-only group has no Matrix side.
      if (await _link.isLinkOnly(groupId) || !_alive) return;
      await _signPending(groupId);
      if (!_alive) return;
      final group = await _groups.getGroup(groupId);
      if (group == null || !_alive) return;
      final members = await _members.getMembers(groupId);
      if (!_alive) return;
      // A device that knows itself to be removed stops broadcasting digests —
      // this also bounds the rule-6 exchange (removed member's digest →
      // member-tombstone payload → poke) to a single round. Self is the
      // participant claimed by this device's account.
      final self = _claimedBy(members, transport.userId);
      if (self == null || !self.isActive) return;
      final expenses = await _expenses.getAllExpensesForGroup(groupId);
      if (!_alive) return;
      final settlements = await _expenses.getAllSettlementsForGroup(groupId);
      if (!_alive) return;
      // Self is included (like ExpenseAdder replication): the digest reaches the user's own
      // other devices too, which is what repairs a stale second device. Targets
      // are the claimed accounts only — pure-local participants are unreachable.
      final targets = onlyTo != null
          ? {onlyTo}
          : members
                .where((m) => m.isActive && isValidMxid(m.matrixId))
                .map((m) => m.matrixId!)
                .toSet();
      if (targets.isEmpty) return;
      final (rejected, rejectedMore) = splitRefusals(
        await _signing.rejectedSetsForGroup(groupId),
      );
      if (!_alive) return;
      // G14: flat when it fits, else bucketed (possibly several messages).
      final messages = buildDigestMessages(
        group,
        members,
        expenses,
        settlements,
        reply: reply,
        last: last,
        budget: _budget,
        bits: bits,
        detail: detailBuckets,
        detailIds: detailIds,
        rejected: rejected,
        rejectedMore: rejectedMore,
      );
      late SendResult result;
      for (final m in messages) {
        result = await transport.sendToUsers(targets, digestEventType, m);
        if (!_alive) return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      // Only targets that had a device were actually sent to.
      for (final t in targets.difference(result.unreachableUsers)) {
        if (!_alive) return;
        await _syncStates.markDigestSent(groupId, t, now);
      }
      _reportDelivery(targets, result);
    } catch (e) {
      // After dispose / DB close an error is expected noise, not a sync fault.
      if (!_alive) return;
      _reportFailure(e);
      debugPrint('[sync] digest send failed for $groupId: $e');
    }
  }

  Future<void> _onDigest(TransportMessage msg) async {
    final content = msg.content;
    final groupId = content['group'] as String?;
    if (groupId == null) return;
    final transport = _transport;
    if (transport == null) return;
    try {
      // G52: never answer / repair / resync a link-only group over Matrix
      // (also one this device is joining: channel, no meta yet).
      if (await _link.isLinkOnly(groupId) || !_alive) return;
      final group = await _groups.getGroup(groupId);
      if (!_alive) return;
      if (group == null) {
        // Rule 7: a group we left / deleted stays gone unless we were re-added.
        final left = await _settings.leftGroup(groupId);
        if (!_alive) return;
        if (left != null) {
          final view = classifyPeerViewOfMe(
            memberRecords: (content['members'] as Map? ?? const {}).values,
            myMxid: transport.userId,
            leftAt: left.leftAt,
          );
          if (view == PeerViewOfMe.staleActive && left.removalNotice != null) {
            await _sendTracked(
              transport,
              {msg.senderId},
              memberEventType,
              left.removalNotice!,
            );
            return;
          }
          if (view != PeerViewOfMe.readded) return;
          // Re-added: fall through to rule 5 — LedgerSyncer accepts the
          // bootstrap answer because it carries our newer active record.
        }
        // Rule 5: we don't know this group — ask the sender to bootstrap us
        // (at most once per group per cooldown window).
        final now = DateTime.now().millisecondsSinceEpoch;
        final askedAt = _groupResyncAskedAt[groupId];
        if (askedAt != null &&
            now - askedAt < kGroupResyncCooldown.inMilliseconds) {
          return;
        }
        _groupResyncAskedAt[groupId] = now;
        await _sendTracked(
          transport,
          {msg.senderId},
          resyncRequestEventType,
          {'v': protocolVersion, 'scope': 'group', 'group': groupId},
        );
        return;
      }

      final members = await _members.getMembers(groupId);
      if (!_alive) return;
      final senderRec = _claimedBy(members, msg.senderId);
      if (senderRec == null) {
        // Rule 8: not a participant of this group at all — never let it
        // gossip members, pull records or get a reply.
        debugPrint('[sync] ignored digest for $groupId from non-member');
        return;
      }
      if (!senderRec.isActive) {
        // Rule 6: the sender was removed — tell their device, nothing else.
        await _sendTracked(
          transport,
          {msg.senderId},
          memberEventType,
          memberPayload(senderRec),
        );
        return;
      }

      final expenses = await _expenses.getAllExpensesForGroup(groupId);
      if (!_alive) return;
      final settlements = await _expenses.getAllSettlementsForGroup(groupId);
      if (!_alive) return;
      final (rejected, rejectedMore) = splitRefusals(
        await _signing.rejectedSetsForGroup(groupId),
      );
      if (!_alive) return;

      // Compare against pre-merge state: "identical" must mean the sender had
      // everything we had at this moment.
      final diff = compareDigest(
        localMetaUpdatedAt: group.updatedAt,
        localMetaHash: groupMetaVersionHash(group),
        localMembers: {
          for (final m in members)
            m.userId: (status: m.status, updatedAt: m.updatedAt),
        },
        localMemberHashes: {
          for (final m in members) m.userId: memberVersionHash(m),
        },
        localExpenses: {for (final e in expenses) e.id: e.updatedAt},
        localExpenseHashes: {
          for (final e in expenses) e.id: expenseVersionHash(e),
        },
        localSettlements: {for (final s in settlements) s.id: s.updatedAt},
        localSettlementHashes: {
          for (final s in settlements) s.id: settlementVersionHash(s),
        },
        localRejected: rejected,
        localRejectedMore: rejectedMore,
        remote: content,
      );

      // Rule 2: membership gossip — each entry is a signed member version,
      // verified + merged LWW exactly like a live member payload (G6).
      final gate = _gate!;
      for (final entry in (content['members'] as Map? ?? const {}).entries) {
        if (!_alive) return;
        final m = entry.value;
        if (entry.key is! String || m is! Map) continue;
        await gate.member({
          ...Map<String, dynamic>.from(m),
          'group': groupId,
          'participant_id': entry.key,
        }, relayedBy: msg.senderId);
      }

      // Rule 1: targeted repair of records the sender lacks or has stale
      // (never a row still waiting for its signature — G6).
      for (final id in diff.expenseIdsToSend) {
        if (!_alive) return;
        final e = await _expenses.getExpenseById(id);
        if (e != null && !e.pendingSign && _alive) {
          await _sendTracked(
            transport,
            {msg.senderId},
            expenseEventType,
            expensePayload(e),
          );
        }
      }
      for (final id in diff.settlementIdsToSend) {
        if (!_alive) return;
        final s = await _expenses.getSettlementById(id);
        if (s != null && !s.pendingSign && _alive) {
          await _sendTracked(
            transport,
            {msg.senderId},
            settlementEventType,
            settlementPayload(s),
          );
        }
      }
      if (!_alive) return;
      if (diff.sendGroupMeta && !group.pendingSign) {
        await _sendTracked(
          transport,
          {msg.senderId},
          groupMetaEventType,
          groupMetaPayload(group),
        );
        if (!_alive) return;
      }

      // Rule 4: an exact match proves the sender has everything we have.
      if (diff.identical) {
        await _syncStates.markInSync(
          groupId,
          msg.senderId,
          DateTime.now().millisecondsSinceEpoch,
        );
        if (!_alive) return;
      }

      // Rule 3: always answer a primary digest. A reply to a bucketed digest
      // is bucketed too (same bits), detailing the buckets we couldn't
      // resolve and those that differ (rule 9).
      final bits = diff.bucketBits;
      if (content['reply'] != true) {
        await _sendDigest(
          groupId,
          onlyTo: msg.senderId,
          reply: true,
          bits: bits,
          detailBuckets: diff.unresolvedBuckets,
          detailIds: diff.differingIds,
        );
      } else if (content['final'] != true &&
          bits != null &&
          diff.detailBuckets.isNotEmpty) {
        // Rule 9: a bucketed reply that detailed buckets gets one `final`
        // answer detailing the same buckets — so the replier learns what *it*
        // lacks there (or that we agree). A `final` is never answered.
        await _sendDigest(
          groupId,
          onlyTo: msg.senderId,
          reply: true,
          last: true,
          bits: bits,
          detailBuckets: diff.detailBuckets,
        );
      }
    } catch (e) {
      if (_alive) debugPrint('[sync] digest handling failed for $groupId: $e');
    }
  }

  Future<void> _onResyncRequest(TransportMessage msg) async {
    final transport = _transport;
    if (transport == null) return;
    final scope = msg.content['scope'] as String?;
    final what = scope == 'group' ? 'group:${msg.content['group']}' : '$scope';
    final key = '${msg.senderId}|${msg.senderDevice ?? ''}|$what';
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!shouldAnswerResync(
      _resyncAnsweredAt[key],
      now,
      _ref.read(resyncAnswerWindowProvider),
    )) {
      if (kDebugMode) {
        debugPrint(
          '[sync] duplicate resync_request ($what) — already answered',
        );
      }
      return;
    }
    _resyncAnsweredAt[key] = now;
    try {
      if (scope == 'group') {
        final groupId = msg.content['group'] as String?;
        if (groupId == null) return;
        await _sendBootstrapIfMember(transport, groupId, msg.senderId);
      } else if (scope == 'all') {
        // Full resync is for the user's own (new/reinstalled) devices only.
        if (msg.senderId != transport.userId) return;
        final groups = await _matrixGroups();
        for (final g in groups) {
          if (!_alive) return;
          await _sendBootstrap(transport, g.roomId, msg.senderId);
        }
      }
    } catch (e) {
      // Not answered after all: a repeated request may try again.
      _resyncAnsweredAt.remove(key);
      if (_alive) debugPrint('[sync] resync handling failed: $e');
    }
  }

  /// G36: whether a `resync_request` last answered at [answeredAt] (null =
  /// never) may be answered again at [now].
  @visibleForTesting
  static bool shouldAnswerResync(int? answeredAt, int now, Duration window) =>
      answeredAt == null || now - answeredAt >= window.inMilliseconds;

  Future<void> _sendBootstrapIfMember(
    LedgerTransport transport,
    String groupId,
    String requester,
  ) async {
    if (requester != transport.userId) {
      final members = await _members.getMembers(groupId);
      final rec = _claimedBy(members, requester);
      if (rec == null || !rec.isActive) return; // not a member — no data
    }
    if (!_alive) return;
    await _sendBootstrap(transport, groupId, requester);
  }

  /// The participant claimed by the Matrix account [matrixId], if any. All the
  /// engine's "who is this account?" lookups go through here — senders and self
  /// are identified by their MXID, not the (possibly local) participant id.
  /// (Duplicates from the pre-G26 re-add bug resolve like everywhere else —
  /// see [claimedBy].)
  static MemberModel? _claimedBy(List<MemberModel> members, String matrixId) =>
      claimedBy(members, matrixId);

  Future<void> _sendBootstrap(
    LedgerTransport transport,
    String groupId,
    String to,
  ) async {
    // G52: a link-only group is never bootstrapped over Matrix.
    if (await _link.isLinkOnly(groupId) || !_alive) return;
    await _signPending(groupId);
    if (!_alive) return;
    final group = await _groups.getGroup(groupId);
    final members = await _members.getMembers(groupId);
    final expenses = await _expenses.getAllExpensesForGroup(groupId);
    final settlements = await _expenses.getAllSettlementsForGroup(groupId);
    if (!_alive) return;
    final parts = buildBootstrapParts(
      groupId,
      group,
      members,
      expenses,
      settlements,
      deviceKeys: await _signing.attestationsFor(
        snapshotSigners(group, members, expenses, settlements),
      ),
      budget: _budget,
    );
    // G14: one self-contained part per to-device message (any order).
    for (final part in parts) {
      if (!_alive) return;
      await _sendTracked(transport, {to}, bootstrapEventType, part);
    }
  }
}

/// Builds the per-group **flat** digest payload: `id → "<updatedAt>:<hash8>"`
/// maps for every record **including tombstones** (G27: the short content
/// hash makes a same-clock divergence visible), the group meta's clock +
/// hash, plus the members map (which doubles as gossip).
@visibleForTesting
Map<String, dynamic> buildDigestContent(
  GroupModel group,
  List<MemberModel> members,
  List<ExpenseModel> expenses,
  List<SettlementModel> settlements, {
  required bool reply,
  Map<String, Map<String, RecordVersion>> rejected = const {},
  Map<String, Map<String, List<RecordVersion>>> rejectedMore = const {},
}) => {
  ..._digestHeader(
    group,
    members,
    reply: reply,
    rejected: rejected,
    rejectedMore: rejectedMore,
  ),
  'expenses': {
    for (final e in expenses) e.id: encodeDigestVersion(expenseVersion(e)),
  },
  'settlements': {
    for (final s in settlements)
      s.id: encodeDigestVersion(settlementVersion(s)),
  },
};

Map<String, dynamic> _digestHeader(
  GroupModel group,
  List<MemberModel> members, {
  required bool reply,
  bool last = false,
  Map<String, Map<String, RecordVersion>> rejected = const {},
  Map<String, Map<String, List<RecordVersion>>> rejectedMore = const {},
}) => {
  'v': protocolVersion,
  'group': group.roomId,
  'reply': reply,
  if (last) 'final': true,
  'meta_updated_at': group.updatedAt,
  'meta_hash': groupMetaVersionHash(group).substring(0, kDigestHashChars),
  // G6: each entry is the full signed member version (verifiable gossip);
  // a row still waiting for its signature isn't gossiped yet.
  'members': {
    for (final m in members)
      if (!m.pendingSign)
        m.userId: {
          'status': m.status,
          'updated_at': m.updatedAt,
          'name': m.displayName,
          'matrix_id': m.matrixId,
          if (m.sig != null) 'sig': m.sig!.toJson(),
        },
  },
  if (rejected.isNotEmpty) 'rejected': digestRejectedMap(rejected),
  // G18 review 2: further refused versions of the same records (older
  // peers ignore the key; they only miss these extra "don't re-send" hints).
  if (rejectedMore.isNotEmpty)
    'rejected_more': digestRejectedMoreMap(rejectedMore),
};

/// G14: the digest for a group as one or more to-device messages of at most
/// [budget] bytes of JSON.
///
/// - **Flat** (the format of [buildDigestContent]) when it fits [budget] and
///   no bucketed shape is required ([bits] == null).
/// - Otherwise **bucketed**: the records are hashed into `2^bits` buckets by
///   id (`record_version.dart`); every message carries the header (meta,
///   members, rejected), `bucket_bits` and the hash of **every** bucket
///   (`buckets`, a list indexed by bucket), plus the full entries of the
///   buckets in its `detail` list — [detail] is spread over as many messages
///   as needed (one message with an empty `detail` when there is none). A
///   receiver compares bucket hashes first and needs entries only for the
///   buckets that differ (see [compareDigest] and the [SyncEngine] rules).
///
/// [bits] defaults to [digestBucketBitsFor] the record count; a reply to a
/// bucketed digest uses the sender's bits (bucket indices must agree).
/// [last] marks the third message of a bucketed exchange (`final`, never
/// answered).
@visibleForTesting
List<Map<String, dynamic>> buildDigestMessages(
  GroupModel group,
  List<MemberModel> members,
  List<ExpenseModel> expenses,
  List<SettlementModel> settlements, {
  required bool reply,
  required int budget,
  bool last = false,
  int? bits,
  Set<int> detail = const {},
  Set<String> detailIds = const {},
  Map<String, Map<String, RecordVersion>> rejected = const {},
  Map<String, Map<String, List<RecordVersion>>> rejectedMore = const {},
}) {
  if (bits == null) {
    final flat = buildDigestContent(
      group,
      members,
      expenses,
      settlements,
      reply: reply,
      rejected: rejected,
      rejectedMore: rejectedMore,
    );
    if (encodedPayloadBytes(flat) <= budget) return [flat];
  }
  final b = bits ?? digestBucketBitsFor(expenses.length + settlements.length);
  final expVersions = {for (final e in expenses) e.id: expenseVersion(e)};
  final setVersions = {for (final s in settlements) s.id: settlementVersion(s)};
  final header = {
    ..._digestHeader(
      group,
      members,
      reply: reply,
      last: last,
      rejected: rejected,
      rejectedMore: rejectedMore,
    ),
    'bucket_bits': b,
    'buckets': digestBucketHashes(
      expenses: expVersions,
      settlements: setVersions,
      bits: b,
    ),
  };
  // Entries per detail bucket.
  final wanted = {...detail, for (final id in detailIds) digestBucketOf(id, b)};
  final perBucket = <int, ({Map<String, String> e, Map<String, String> s})>{
    for (final d in wanted.toList()..sort()) d: (e: {}, s: {}),
  };
  for (final MapEntry(key: id, value: v) in expVersions.entries) {
    perBucket[digestBucketOf(id, b)]?.e[id] = encodeDigestVersion(v);
  }
  for (final MapEntry(key: id, value: v) in setVersions.entries) {
    perBucket[digestBucketOf(id, b)]?.s[id] = encodeDigestVersion(v);
  }
  Map<String, dynamic> message(List<int> buckets) => {
    ...header,
    'detail': buckets,
    'expenses': {for (final d in buckets) ...perBucket[d]!.e},
    'settlements': {for (final d in buckets) ...perBucket[d]!.s},
  };
  if (perBucket.isEmpty) return [message(const [])];
  final headerBytes = encodedPayloadBytes(message(const []));
  final out = <Map<String, dynamic>>[];
  var current = <int>[];
  var size = headerBytes;
  for (final MapEntry(key: d, value: entries) in perBucket.entries) {
    // ~ `"<id>":"<ms>:<hash8>",` per entry + the bucket index.
    final bytes =
        8 +
        encodedPayloadBytes({'e': entries.e, 's': entries.s}) -
        encodedPayloadBytes(const {'e': {}, 's': {}});
    if (current.isNotEmpty && size + bytes > budget) {
      out.add(message(current));
      current = [];
      size = headerBytes;
    }
    current.add(d);
    size += bytes;
  }
  out.add(message(current));
  return out;
}

/// The digest's `rejected` map (G6) from [SigningDao.rejectedForGroup]'s
/// kind → id → refused version: `{expenses: {id: "T:hash8"}, settlements:
/// {…}, members: {participantId: "T:hash8"}, meta: "T:hash8"}`. G18 review:
/// entries name the **exact** refused version (clock + G27 hash prefix, like
/// the record entries); a bare clock (older peers) matches any version at
/// that clock.
Map<String, dynamic> digestRejectedMap(
  Map<String, Map<String, RecordVersion>> byKind,
) {
  Map<String, String> enc(Map<String, RecordVersion> m) => {
    for (final MapEntry(:key, :value) in m.entries)
      key: encodeDigestVersion(value),
  };
  return {
    if (byKind['expense'] case final m? when m.isNotEmpty) 'expenses': enc(m),
    if (byKind['settlement'] case final m? when m.isNotEmpty)
      'settlements': enc(m),
    if (byKind['member'] case final m? when m.isNotEmpty) 'members': enc(m),
    if (byKind['meta'] case final m? when m.isNotEmpty)
      'meta': encodeDigestVersion(
        m.values.reduce((a, b) => compareVersions(a, b) >= 0 ? a : b),
      ),
  };
}

/// G18 review 2: the digest's `rejected_more` section — the refused versions
/// beyond the highest one per record ([splitRefusals]): `{expenses: {id:
/// ["T:hash8", …]}, settlements: {…}, members: {…}, meta: ["T:hash8", …]}`.
Map<String, dynamic> digestRejectedMoreMap(
  Map<String, Map<String, List<RecordVersion>>> byKind,
) {
  Map<String, List<String>> enc(Map<String, List<RecordVersion>> m) => {
    for (final MapEntry(:key, :value) in m.entries)
      if (value.isNotEmpty)
        key: [for (final v in value) encodeDigestVersion(v)],
  };
  return {
    if (byKind['expense'] case final m? when m.isNotEmpty) 'expenses': enc(m),
    if (byKind['settlement'] case final m? when m.isNotEmpty)
      'settlements': enc(m),
    if (byKind['member'] case final m? when m.isNotEmpty) 'members': enc(m),
    if (byKind['meta'] case final m? when m.isNotEmpty)
      'meta': [
        for (final vs in m.values)
          for (final v in vs) encodeDigestVersion(v),
      ],
  };
}

/// Splits [SigningDao.rejectedSetsForGroup]'s refusal sets (highest first)
/// into the highest version per record (the digest's `rejected`) and the
/// rest (`rejected_more`). For `meta` the highest over all entries is kept.
(
  Map<String, Map<String, RecordVersion>>,
  Map<String, Map<String, List<RecordVersion>>>,
)
splitRefusals(Map<String, Map<String, List<RecordVersion>>> sets) {
  final top = <String, Map<String, RecordVersion>>{};
  final more = <String, Map<String, List<RecordVersion>>>{};
  for (final MapEntry(key: kind, value: byId) in sets.entries) {
    for (final MapEntry(key: id, value: vs) in byId.entries) {
      if (vs.isEmpty) continue;
      (top[kind] ??= {})[id] = vs.first;
      if (vs.length > 1) (more[kind] ??= {})[id] = vs.sublist(1);
    }
  }
  return (top, more);
}

/// Whether [a] and [b] are the same version: same clock and, when both
/// hashes are known, the same hash (prefix).
bool _sameVersion(RecordVersion a, RecordVersion b) =>
    a.at == b.at && compareVersions(a, b) == 0;

class DigestDiff {
  /// Records our side must re-send because the sender lacks them or has an
  /// older revision.
  final List<String> expenseIdsToSend;
  final List<String> settlementIdsToSend;
  final bool sendGroupMeta;

  /// The sender has records/revisions we lack — our reply digest will make
  /// them repair us.
  final bool senderHasNewer;

  /// Exact match between the digest and our local state.
  final bool identical;

  /// G14: ids (expenses and settlements) whose versions differ between the
  /// two sides (excluding "agree to disagree") — the buckets our reply must
  /// detail.
  final Set<String> differingIds;

  /// G14: for a bucketed digest, the buckets whose hashes differ but whose
  /// entries the sender didn't include (`detail`) — we can't tell yet who
  /// lacks what there. Empty for a flat digest.
  final Set<int> unresolvedBuckets;

  /// G14: the bucket exponent of a bucketed digest, null for a flat one.
  final int? bucketBits;

  /// G14: the buckets the (bucketed) digest detailed.
  final Set<int> detailBuckets;

  const DigestDiff({
    required this.expenseIdsToSend,
    required this.settlementIdsToSend,
    required this.sendGroupMeta,
    required this.senderHasNewer,
    required this.identical,
    this.differingIds = const {},
    this.unresolvedBuckets = const {},
    this.bucketBits,
    this.detailBuckets = const {},
  });
}

/// The bucket exponent + hashes + detail list of a bucketed digest, or null
/// for a flat (or malformed bucketed) one.
({int bits, List<String> hashes, Set<int> detail})? _bucketsOf(
  Map<String, dynamic> remote,
) {
  final bits = remote['bucket_bits'];
  final hashes = remote['buckets'];
  if (bits is! int || bits < 0 || bits > 16 || hashes is! List) return null;
  if (hashes.length != 1 << bits || hashes.any((h) => h is! String)) {
    return null;
  }
  final rawDetail = remote['detail'];
  return (
    bits: bits,
    hashes: hashes.cast<String>(),
    detail: {
      if (rawDetail is List)
        for (final d in rawDetail)
          if (d is int && d >= 0 && d < hashes.length) d,
    },
  );
}

/// Pure digest comparison (plain Dart, unit-testable without a DB).
///
/// G6: [localRejected] (kind → id → version, from
/// [SigningDao.rejectedForGroup]) are the versions *we* refused,
/// `remote['rejected']` (digest format, see [digestRejectedMap]) the ones the
/// *sender* refused. A refused version is "seen": we never re-send a version
/// the sender refused, a sender holding exactly what we refused isn't
/// "newer", and both count as matching for rule 4 — the two sides agree to
/// disagree instead of looping. G18 review: only the **exact** refused
/// version (clock + hash) counts — any other version is repaired as usual.
///
/// G27: versions compare by clock, then content hash (`compareVersions`) —
/// the `local*Hashes` maps / [localMetaHash] hold our full hashes, the
/// digest the first 8 hex chars. Without a hash (either side) an equal clock
/// counts as the same version.
///
/// G14: a **bucketed** digest is compared bucket by bucket — buckets whose
/// hash matches ours are in sync, `detail` buckets are compared entry by
/// entry, the rest are [DigestDiff.unresolvedBuckets] (never identical).
@visibleForTesting
DigestDiff compareDigest({
  required int localMetaUpdatedAt,
  String localMetaHash = '',
  required Map<String, ({String status, int updatedAt})> localMembers,
  Map<String, String> localMemberHashes = const {},
  required Map<String, int> localExpenses,
  Map<String, String> localExpenseHashes = const {},
  required Map<String, int> localSettlements,
  Map<String, String> localSettlementHashes = const {},
  Map<String, Map<String, RecordVersion>> localRejected = const {},
  Map<String, Map<String, List<RecordVersion>>> localRejectedMore = const {},
  required Map<String, dynamic> remote,
}) {
  final remoteRejected = remote['rejected'] is Map
      ? remote['rejected'] as Map
      : const {};
  Map<String, RecordVersion> rejectedSection(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.key is String) e.key as String: ?parseDigestVersion(e.value),
  };
  final theirRejected = {
    'expense': rejectedSection(remoteRejected['expenses']),
    'settlement': rejectedSection(remoteRejected['settlements']),
    'member': rejectedSection(remoteRejected['members']),
  };
  // G18 review 2: further refused versions per record (`rejected_more`).
  final remoteMore = remote['rejected_more'] is Map
      ? remote['rejected_more'] as Map
      : const {};
  List<RecordVersion> versionList(Object? raw) => [
    if (raw is List)
      for (final v in raw) ?parseDigestVersion(v),
  ];
  Map<String, List<RecordVersion>> moreSection(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.key is String) e.key as String: versionList(e.value),
  };
  final theirMore = {
    'expense': moreSection(remoteMore['expenses']),
    'settlement': moreSection(remoteMore['settlements']),
    'member': moreSection(remoteMore['members']),
  };

  /// We may skip sending our [local] version: the sender refused exactly it.
  bool theyRefused(String kind, String id, RecordVersion local) {
    final r = theirRejected[kind]![id];
    if (r != null && _sameVersion(local, r)) return true;
    return (theirMore[kind]![id] ?? const []).any(
      (v) => _sameVersion(local, v),
    );
  }

  /// The sender's version [theirs] isn't news: we refused exactly it.
  bool weRefused(String kind, String id, RecordVersion theirs) {
    final r = localRejected[kind]?[id];
    if (r != null && _sameVersion(theirs, r)) return true;
    return (localRejectedMore[kind]?[id] ?? const []).any(
      (v) => _sameVersion(theirs, v),
    );
  }

  Map<String, RecordVersion> versions(
    Map<String, int> clocks,
    Map<String, String> hashes,
  ) => {
    for (final MapEntry(key: id, value: at) in clocks.entries)
      id: (at: at, hash: hashes[id] ?? ''),
  };
  final localExp = versions(localExpenses, localExpenseHashes);
  final localSet = versions(localSettlements, localSettlementHashes);

  // G14: bucketed digest → which of our records are in scope.
  final buckets = _bucketsOf(remote);
  final unresolved = <int>{};
  var scope = (String id) => true;
  if (buckets != null) {
    final ours = digestBucketHashes(
      expenses: localExp,
      settlements: localSet,
      bits: buckets.bits,
    );
    for (var b = 0; b < ours.length; b++) {
      if (ours[b] != buckets.hashes[b] && !buckets.detail.contains(b)) {
        unresolved.add(b);
      }
    }
    scope = (id) => buckets.detail.contains(digestBucketOf(id, buckets.bits));
  }

  var senderHasNewer = false;
  final differing = <String>{};

  (List<String>, bool) diffRecords(
    String kind,
    Map<String, RecordVersion> local,
    Map<String, dynamic> remoteMap,
  ) {
    final toSend = <String>[];
    var theirsNewer = false;
    for (final MapEntry(key: id, value: mine) in local.entries) {
      if (!scope(id)) continue;
      final theirs = parseDigestVersion(remoteMap[id]);
      final c = theirs == null ? 1 : compareVersions(mine, theirs);
      if (c > 0 && !theyRefused(kind, id, mine)) {
        toSend.add(id);
        differing.add(id);
      }
      if (theirs != null && c < 0 && !weRefused(kind, id, theirs)) {
        theirsNewer = true;
        differing.add(id);
      }
    }
    for (final MapEntry(:key, :value) in remoteMap.entries) {
      if (local.containsKey(key) || !scope(key)) continue;
      final theirs = parseDigestVersion(value);
      if (theirs != null && weRefused(kind, key, theirs)) continue;
      theirsNewer = true;
      differing.add(key);
    }
    return (toSend, theirsNewer);
  }

  final remoteExpenses = (remote['expenses'] as Map? ?? const {});
  final remoteSettlements = (remote['settlements'] as Map? ?? const {});
  final (expensesToSend, expTheirs) = diffRecords(
    'expense',
    localExp,
    Map<String, dynamic>.from(remoteExpenses),
  );
  final (settlementsToSend, setTheirs) = diffRecords(
    'settlement',
    localSet,
    Map<String, dynamic>.from(remoteSettlements),
  );
  senderHasNewer = expTheirs || setTheirs;

  final RecordVersion remoteMeta = (
    at: remote['meta_updated_at'] as int? ?? 0,
    hash: localMetaHash.isEmpty ? '' : remote['meta_hash'] as String? ?? '',
  );
  final RecordVersion localMeta = (at: localMetaUpdatedAt, hash: localMetaHash);
  final metaCmp = compareVersions(localMeta, remoteMeta);
  final theirMetaRefused = parseDigestVersion(remoteRejected['meta']);
  final ourMetaRefused = localRejected['meta']?.values.fold<RecordVersion?>(
    null,
    (a, b) => a == null || compareVersions(b, a) > 0 ? b : a,
  );
  final metaTheyRefused =
      (theirMetaRefused != null && _sameVersion(localMeta, theirMetaRefused)) ||
      versionList(remoteMore['meta']).any((v) => _sameVersion(localMeta, v));
  final metaWeRefused =
      (ourMetaRefused != null && _sameVersion(remoteMeta, ourMetaRefused)) ||
      (localRejectedMore['meta']?.values ?? const <List<RecordVersion>>[]).any(
        (vs) => vs.any((v) => _sameVersion(remoteMeta, v)),
      );
  final sendGroupMeta = metaCmp > 0 && !metaTheyRefused;
  if (metaCmp < 0 && !metaWeRefused) senderHasNewer = true;
  final metaMatches =
      metaCmp == 0 ||
      (metaCmp < 0 && metaWeRefused) ||
      (metaCmp > 0 && metaTheyRefused);

  var membersIdentical = true;
  final remoteMembers = (remote['members'] as Map? ?? const {});
  final groupId = remote['group'];

  /// The full content hash of a gossiped member entry ('' if unparsable).
  String remoteMemberHash(String pid, Map r) {
    if (groupId is! String) return '';
    final m = memberFromPayload({
      ...Map<String, dynamic>.from(r),
      'group': groupId,
      'participant_id': pid,
    });
    return m == null ? '' : memberVersionHash(m);
  }

  for (final entry in localMembers.entries) {
    final r = remoteMembers[entry.key] as Map?;
    final remoteAt = r?['updated_at'] as int? ?? 0;
    final localHash = localMemberHashes[entry.key] ?? '';
    final remoteHash = r == null ? '' : remoteMemberHash(entry.key, r);
    final RecordVersion mine = (at: entry.value.updatedAt, hash: localHash);
    final RecordVersion theirs = (at: remoteAt, hash: remoteHash);
    final c = compareVersions(
      mine,
      localHash.isEmpty ? (at: remoteAt, hash: '') : theirs,
    );
    final same = r != null && r['status'] == entry.value.status && c == 0;
    final agreedToDisagree =
        (r != null && c < 0 && weRefused('member', entry.key, theirs)) ||
        ((r == null || c > 0) && theyRefused('member', entry.key, mine));
    if (!same && !agreedToDisagree) membersIdentical = false;
  }
  for (final MapEntry(:key, :value) in remoteMembers.entries) {
    if (localMembers.containsKey(key)) continue;
    if (key is String && value is Map) {
      final RecordVersion theirs = (
        at: value['updated_at'] as int? ?? 0,
        hash: remoteMemberHash(key, value),
      );
      if (weRefused('member', key, theirs)) continue;
    }
    membersIdentical = false;
  }

  return DigestDiff(
    expenseIdsToSend: expensesToSend,
    settlementIdsToSend: settlementsToSend,
    sendGroupMeta: sendGroupMeta,
    senderHasNewer: senderHasNewer,
    identical:
        !senderHasNewer &&
        unresolved.isEmpty &&
        expensesToSend.isEmpty &&
        settlementsToSend.isEmpty &&
        !sendGroupMeta &&
        metaMatches &&
        membersIdentical,
    differingIds: differing,
    unresolvedBuckets: unresolved,
    bucketBits: buckets?.bits,
    detailBuckets: buckets?.detail ?? const {},
  );
}
