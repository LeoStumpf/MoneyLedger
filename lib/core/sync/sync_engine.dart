import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/expenses/expenses_provider.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../database/app_database.dart';
import '../database/daos/expenses_dao.dart';
import '../database/daos/groups_dao.dart';
import '../database/daos/members_dao.dart';
import '../database/daos/settings_dao.dart';
import '../database/daos/signing_dao.dart';
import '../database/daos/sync_states_dao.dart';
import '../matrix/ledger_transport.dart';
import '../matrix/transport_provider.dart';
import 'delivery_policy.dart';
import 'ledger_payloads.dart';
import 'left_groups.dart';
import 'record_gate.dart';
import 'record_signing.dart';
import 'record_verifier.dart';
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
/// Digest receiver rules (protocol v1):
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

  LedgerTransport? _transport;

  /// G6: verifies the digests' member gossip (built in [start]).
  RecordGate? _gate;
  StreamSubscription<TransportMessage>? _sub;
  Timer? _periodic;
  final Map<String, Timer> _pokes = {};
  final Map<String, int> _groupResyncAskedAt = {};
  bool _disposed = false;

  SyncEngine(Ref ref)
    : _ref = ref,
      _db = ref.read(appDatabaseProvider),
      _groups = ref.read(groupsDaoProvider),
      _members = ref.read(membersDaoProvider),
      _expenses = ref.read(expensesDaoProvider),
      _syncStates = ref.read(syncStatesDaoProvider),
      _settings = SettingsDao(ref.read(appDatabaseProvider)),
      _signing = ref.read(signingDaoProvider);

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
      final groups = await _groups.getAllGroups();
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
        final groups = await _groups.getAllGroups();
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

  /// Sends a digest for every local group to its active members.
  Future<void> broadcastDigests() async {
    if (!_alive) return;
    try {
      final groups = await _groups.getAllGroups();
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
  Future<void> _signPending(String groupId) async {
    final transport = _transport;
    if (transport == null || transport.crypto.identity == null) return;
    final crypto = transport.crypto;
    final group = await _groups.getGroup(groupId);
    if (!_alive) return;
    if (group != null && group.pendingSign) {
      await _groups.upsertGroupLww(
        groupCompanion(await signGroupMeta(crypto, group)),
      );
    }
    for (final m in await _members.getMembers(groupId)) {
      if (!_alive) return;
      if (m.pendingSign) {
        await _members.upsertMemberLww(
          memberCompanion(await signMember(crypto, m)),
        );
      }
    }
    for (final e in await _expenses.getAllExpensesForGroup(groupId)) {
      if (!_alive) return;
      if (e.pendingSign) {
        await _expenses.upsertExpenseLww(
          expenseCompanion(
            await signExpense(
              crypto,
              e,
              creating: e.origin == null && e.updatedAt == e.createdAt,
            ),
          ),
        );
      }
    }
    for (final st in await _expenses.getAllSettlementsForGroup(groupId)) {
      if (!_alive) return;
      if (st.pendingSign) {
        await _expenses.upsertSettlementLww(
          settlementCompanion(
            await signSettlement(
              crypto,
              st,
              creating: st.origin == null && st.updatedAt == st.createdAt,
            ),
          ),
        );
      }
    }
  }

  /// Debounced "something changed in [groupId]": coalesces a burst of inbound
  /// payloads into one digest, which acts as the delivery ack to the writer.
  void pokeGroup(String groupId) {
    if (!_alive) return;
    _pokes[groupId]?.cancel();
    _pokes[groupId] = Timer(_ref.read(pokeDebounceProvider), () {
      _pokes.remove(groupId);
      _sendDigest(groupId);
    });
  }

  void _onMessage(TransportMessage msg) {
    if (!_alive) return;
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
        if (group != null) pokeGroup(group);
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
  }) async {
    final transport = _transport;
    if (transport == null || !_alive) return;
    try {
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
                .where((m) => m.isActive && m.matrixId != null)
                .map((m) => m.matrixId!)
                .toSet();
      if (targets.isEmpty) return;
      final rejected = await _signing.rejectedForGroup(groupId);
      if (!_alive) return;
      final result = await transport.sendToUsers(
        targets,
        digestEventType,
        buildDigestContent(
          group,
          members,
          expenses,
          settlements,
          reply: reply,
          rejected: rejected,
        ),
      );
      if (!_alive) return;
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
      final rejected = await _signing.rejectedForGroup(groupId);
      if (!_alive) return;

      // Compare against pre-merge state: "identical" must mean the sender had
      // everything we had at this moment.
      final diff = compareDigest(
        localMetaUpdatedAt: group.updatedAt,
        localMembers: {
          for (final m in members)
            m.userId: (status: m.status, updatedAt: m.updatedAt),
        },
        localExpenses: {for (final e in expenses) e.id: e.updatedAt},
        localSettlements: {for (final s in settlements) s.id: s.updatedAt},
        localRejected: rejected,
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

      // Rule 3: always answer a primary digest; never answer a reply.
      if (content['reply'] != true) {
        await _sendDigest(groupId, onlyTo: msg.senderId, reply: true);
      }
    } catch (e) {
      if (_alive) debugPrint('[sync] digest handling failed for $groupId: $e');
    }
  }

  Future<void> _onResyncRequest(TransportMessage msg) async {
    final transport = _transport;
    if (transport == null) return;
    try {
      final scope = msg.content['scope'] as String?;
      if (scope == 'group') {
        final groupId = msg.content['group'] as String?;
        if (groupId == null) return;
        await _sendBootstrapIfMember(transport, groupId, msg.senderId);
      } else if (scope == 'all') {
        // Full resync is for the user's own (new/reinstalled) devices only.
        if (msg.senderId != transport.userId) return;
        final groups = await _groups.getAllGroups();
        for (final g in groups) {
          if (!_alive) return;
          await _sendBootstrap(transport, g.roomId, msg.senderId);
        }
      }
    } catch (e) {
      if (_alive) debugPrint('[sync] resync handling failed: $e');
    }
  }

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
    await _signPending(groupId);
    if (!_alive) return;
    final group = await _groups.getGroup(groupId);
    final members = await _members.getMembers(groupId);
    final expenses = await _expenses.getAllExpensesForGroup(groupId);
    final settlements = await _expenses.getAllSettlementsForGroup(groupId);
    if (!_alive) return;
    final content = buildBootstrapContent(
      groupId,
      group,
      members,
      expenses,
      settlements,
      deviceKeys: await _signing.attestationsFor(
        snapshotSigners(group, members, expenses, settlements),
      ),
    );
    if (!_alive) return;
    await _sendTracked(transport, {to}, bootstrapEventType, content);
  }
}

/// Builds the per-group digest payload: `id → updatedAt` maps for every record
/// **including tombstones**, plus the members map (which doubles as gossip).
@visibleForTesting
Map<String, dynamic> buildDigestContent(
  GroupModel group,
  List<MemberModel> members,
  List<ExpenseModel> expenses,
  List<SettlementModel> settlements, {
  required bool reply,
  Map<String, Map<String, int>> rejected = const {},
}) => {
  'v': protocolVersion,
  'group': group.roomId,
  'reply': reply,
  'meta_updated_at': group.updatedAt,
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
  'expenses': {for (final e in expenses) e.id: e.updatedAt},
  'settlements': {for (final s in settlements) s.id: s.updatedAt},
  if (rejected.isNotEmpty) 'rejected': digestRejectedMap(rejected),
};

/// The digest's `rejected` map (G6) from [SigningDao.rejectedForGroup]'s
/// kind → id → clock: `{expenses: {id: T}, settlements: {…}, members:
/// {participantId: T}, meta: T}`.
Map<String, dynamic> digestRejectedMap(
  Map<String, Map<String, int>> byKind,
) => {
  if (byKind['expense'] case final m? when m.isNotEmpty) 'expenses': m,
  if (byKind['settlement'] case final m? when m.isNotEmpty) 'settlements': m,
  if (byKind['member'] case final m? when m.isNotEmpty) 'members': m,
  if (byKind['meta'] case final m? when m.isNotEmpty)
    'meta': m.values.reduce((a, b) => a > b ? a : b),
};

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

  const DigestDiff({
    required this.expenseIdsToSend,
    required this.settlementIdsToSend,
    required this.sendGroupMeta,
    required this.senderHasNewer,
    required this.identical,
  });
}

/// Pure digest comparison (plain Dart, unit-testable without a DB).
///
/// G6: [localRejected] (kind → id → clock, from [SigningDao.rejectedForGroup])
/// are the versions *we* refused, `remote['rejected']` (digest format, see
/// [digestRejectedMap]) the ones the *sender* refused. A refused version is
/// "seen": we never re-send a record the sender refused at (or above) our
/// clock, a sender holding exactly what we refused isn't "newer", and both
/// count as matching for rule 4 — the two sides agree to disagree instead of
/// looping.
@visibleForTesting
DigestDiff compareDigest({
  required int localMetaUpdatedAt,
  required Map<String, ({String status, int updatedAt})> localMembers,
  required Map<String, int> localExpenses,
  required Map<String, int> localSettlements,
  Map<String, Map<String, int>> localRejected = const {},
  required Map<String, dynamic> remote,
}) {
  final remoteRejected = remote['rejected'] is Map
      ? remote['rejected'] as Map
      : const {};
  Map<String, int> rejectedSection(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.key is String && e.value is int) e.key as String: e.value as int,
  };
  final theirRejected = {
    'expense': rejectedSection(remoteRejected['expenses']),
    'settlement': rejectedSection(remoteRejected['settlements']),
    'member': rejectedSection(remoteRejected['members']),
  };
  int? ourRejected(String kind, String id) => localRejected[kind]?[id];

  /// We may skip sending our [local] version: the sender refused it.
  bool theyRefused(String kind, String id, int local) {
    final r = theirRejected[kind]![id];
    return r != null && r >= local;
  }

  /// The sender's [remoteAt] isn't news: we refused that version already.
  bool weRefused(String kind, String id, int remoteAt) {
    final r = ourRejected(kind, id);
    return r != null && remoteAt <= r;
  }

  var senderHasNewer = false;

  (List<String>, bool) diffRecords(
    String kind,
    Map<String, int> local,
    Map<String, dynamic> remoteMap,
  ) {
    final toSend = <String>[];
    var theirsNewer = false;
    for (final entry in local.entries) {
      final remoteAt = remoteMap[entry.key] as int?;
      if ((remoteAt == null || remoteAt < entry.value) &&
          !theyRefused(kind, entry.key, entry.value)) {
        toSend.add(entry.key);
      }
      if (remoteAt != null &&
          remoteAt > entry.value &&
          !weRefused(kind, entry.key, remoteAt)) {
        theirsNewer = true;
      }
    }
    for (final MapEntry(:key, :value) in remoteMap.entries) {
      if (local.containsKey(key)) continue;
      if (value is int && weRefused(kind, key, value)) continue;
      theirsNewer = true;
    }
    return (toSend, theirsNewer);
  }

  final remoteExpenses = (remote['expenses'] as Map? ?? const {});
  final remoteSettlements = (remote['settlements'] as Map? ?? const {});
  final (expensesToSend, expTheirs) = diffRecords(
    'expense',
    localExpenses,
    Map<String, dynamic>.from(remoteExpenses),
  );
  final (settlementsToSend, setTheirs) = diffRecords(
    'settlement',
    localSettlements,
    Map<String, dynamic>.from(remoteSettlements),
  );
  senderHasNewer = expTheirs || setTheirs;

  final remoteMeta = remote['meta_updated_at'] as int? ?? 0;
  final theirMetaRefused = remoteRejected['meta'] as int?;
  final ourMetaRefused = localRejected['meta']?.values.fold<int?>(
    null,
    (a, b) => a == null || b > a ? b : a,
  );
  final metaTheyRefused =
      theirMetaRefused != null && theirMetaRefused >= localMetaUpdatedAt;
  final metaWeRefused = ourMetaRefused != null && remoteMeta <= ourMetaRefused;
  final sendGroupMeta = localMetaUpdatedAt > remoteMeta && !metaTheyRefused;
  if (remoteMeta > localMetaUpdatedAt && !metaWeRefused) senderHasNewer = true;
  final metaMatches =
      remoteMeta == localMetaUpdatedAt ||
      (remoteMeta > localMetaUpdatedAt && metaWeRefused) ||
      (remoteMeta < localMetaUpdatedAt && metaTheyRefused);

  var membersIdentical = true;
  final remoteMembers = (remote['members'] as Map? ?? const {});
  for (final entry in localMembers.entries) {
    final r = remoteMembers[entry.key] as Map?;
    final remoteAt = r?['updated_at'] as int? ?? 0;
    final same =
        r != null &&
        r['status'] == entry.value.status &&
        remoteAt == entry.value.updatedAt;
    final agreedToDisagree =
        (r != null &&
            remoteAt > entry.value.updatedAt &&
            weRefused('member', entry.key, remoteAt)) ||
        ((r == null || remoteAt < entry.value.updatedAt) &&
            theyRefused('member', entry.key, entry.value.updatedAt));
    if (!same && !agreedToDisagree) membersIdentical = false;
  }
  for (final MapEntry(:key, :value) in remoteMembers.entries) {
    if (localMembers.containsKey(key)) continue;
    final at = value is Map ? value['updated_at'] as int? ?? 0 : 0;
    if (key is String && weRefused('member', key, at)) continue;
    membersIdentical = false;
  }

  return DigestDiff(
    expenseIdsToSend: expensesToSend,
    settlementIdsToSend: settlementsToSend,
    sendGroupMeta: sendGroupMeta,
    senderHasNewer: senderHasNewer,
    identical:
        !senderHasNewer &&
        expensesToSend.isEmpty &&
        settlementsToSend.isEmpty &&
        !sendGroupMeta &&
        metaMatches &&
        membersIdentical,
  );
}
