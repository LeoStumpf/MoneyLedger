import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/session/app_session.dart' show isLocalAccountId;
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/history_dao.dart' show HistorySource;
import '../../core/database/daos/link_dao.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/database/daos/signing_dao.dart';
import '../../core/database/daos/sync_states_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../core/sync/ledger_payloads.dart';
import '../../core/sync/left_groups.dart';
import '../../core/sync/peer_convergence.dart';
import '../../core/sync/record_gate.dart';
import '../../core/sync/record_signing.dart' show RecordKind;
import '../../core/sync/sync_health.dart';
import '../../core/sync/record_verifier.dart';
import '../../models/expense_category.dart' show parseCustomCategories;
import '../../models/member_model.dart';
import '../../models/record_signature.dart';
import 'expenses_provider.dart';

/// LWW clocks on inbound records are clamped to at most `now + this` so a
/// skewed or hostile future timestamp can't win every merge forever.
const _clockSkewToleranceMs = 5 * 60 * 1000;

/// The to-device record types [LedgerSyncer] mirrors into Drift. Other
/// `com.moneyledger.*` types (digest/resync) are handled by `SyncEngine`.
const _recordTypes = {
  expenseEventType,
  settlementEventType,
  groupMetaEventType,
  memberEventType,
  bootstrapEventType,
};

final ledgerSyncerProvider = Provider.autoDispose<LedgerSyncer>((ref) {
  // Rebuild (dispose + restart) when the signed-in account's ledger DB is
  // swapped (G4), so it never keeps reading/writing a closed or foreign DB.
  ref.watch(appDatabaseProvider);
  final syncer = LedgerSyncer(ref);
  syncer.start();
  ref.onDispose(syncer.dispose);
  return syncer;
});

/// Subscribes to the transport's inbound message stream and mirrors incoming
/// ledger/group/membership payloads into Drift (the local source of truth).
/// All Matrix specifics live behind [LedgerTransport]; this class only sees
/// plain-Dart [TransportMessage]s. Roomless (Phase B).
class LedgerSyncer {
  final Ref _ref;

  /// The account DB + DAOs this syncer was built for, captured once (see
  /// `SyncEngine`): inbound records are never written into another account's
  /// DB after a mid-flight account switch (G4).
  final AppDatabase _db;
  final ExpensesDao _expenses;
  final GroupsDao _groups;
  final MembersDao _members;
  final SettingsDao _settings;
  final SyncStatesDao _syncStates;
  final SigningDao _signing;

  /// G52: link-only groups are never touched from the Matrix path.
  final LinkDao _link;

  /// G6: verifies every inbound version before it is stored (built in
  /// [start] from the transport's crypto + device directory).
  RecordGate? _gate;

  /// Record revisions each peer sent us — feeds the fast in-sync proof (G29).
  final PeerConvergenceTracker _convergence = PeerConvergenceTracker();

  /// This device's MXID, known once [start] has the transport.
  String? _myMxid;

  bool _disposed = false;
  StreamSubscription<TransportMessage>? _sub;

  LedgerSyncer(Ref ref)
    : _ref = ref,
      _db = ref.read(appDatabaseProvider),
      _expenses = ref.read(expensesDaoProvider),
      _groups = ref.read(groupsDaoProvider),
      _members = ref.read(membersDaoProvider),
      _settings = SettingsDao(ref.read(appDatabaseProvider)),
      _syncStates = ref.read(syncStatesDaoProvider),
      _signing = ref.read(signingDaoProvider),
      _link = LinkDao(ref.read(appDatabaseProvider)),
      _health = ref.read(syncHealthProvider.notifier);

  /// G35: where refused unsigned (pre-G6) records are surfaced.
  final SyncHealth _health;

  /// Names of groups whose bootstrap is being applied (from its meta) — for
  /// the legacy-refusal hint when the group itself isn't stored.
  final Map<String, String> _snapshotNames = {};

  void _onRefused(
    String groupId,
    RecordKind kind,
    RejectReason reason,
    String relayedBy,
  ) {
    if (reason != RejectReason.unsigned || !_alive) return;
    debugPrint(
      '[g6] refused unsigned (pre-G6) ${kind.wire} of $groupId from '
      '$relayedBy — legacy rows can\'t be relayed; re-save or recreate the '
      'group',
    );
    _health.reportLegacyRefused(
      groupId,
      relayedBy: relayedBy,
      groupName: _snapshotNames[groupId],
    );
  }

  /// False once disposed or once the captured DB is closed (on an account
  /// switch the old DB closes before this syncer's `onDispose` runs).
  bool get _alive => !_disposed && !_db.isClosed;

  final Completer<void> _ready = Completer<void>();

  /// Completes once [start] has subscribed to the transport (or gave up).
  Future<void> get ready => _ready.future;

  Future<void> start() async {
    try {
      await _start();
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  Future<void> _start() async {
    // Signed out: nothing to sync into. Not subscribing also lets the
    // transport buffer inbound messages until the account's syncer attaches.
    if (_db.isSignedOutPlaceholder) return;
    final LedgerTransport transport;
    try {
      transport = await _ref.read(ledgerTransportProvider.future);
    } catch (e) {
      if (_alive) debugPrint('[ledger] syncer inactive, no transport: $e');
      return;
    }
    if (!_alive) return;
    if (isLocalAccountId(transport.userId)) return; // G40: local mode
    _myMxid = transport.userId;
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
      onRefused: _onRefused,
    );
    _sub = transport.onMessage.listen(_onMessage);
    _ready.complete();
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
  }

  Future<void> _onMessage(TransportMessage msg) async {
    if (!_alive || !_recordTypes.contains(msg.type)) return;
    // G18 review: only end-to-end encrypted payloads carry an authenticated
    // sender — a plaintext to-device event could claim any `sender`.
    if (!msg.encrypted) {
      debugPrint('[ledger] dropped unencrypted ${msg.type} (${msg.senderId})');
      return;
    }
    final group = msg.content['group'] as String?;
    if (group == null) return;

    try {
      // G52 (§6.4): a link-only group has no Matrix side — whatever arrives
      // for it over to-device is dropped (Matrix sends never target it).
      if (await _link.isLinkOnly(group)) {
        debugPrint('[ledger] dropped ${msg.type} for link-only group $group');
        return;
      }
      if (!_alive) return;
      // Inbound to-device messages are E2EE, so `msg.senderId` is authenticated;
      // the only missing trust check is that the sender belongs to the group
      // they are writing to. Fetch the group's current members + existence and
      // gate the record before applying it.
      final members = await _members.getMembers(group);
      if (!_alive) return;
      final groupKnown = (await _groups.getGroup(group)) != null;
      if (!_alive) return;

      if (!groupKnown) {
        // G9: a group we left / deleted is only re-accepted via a bootstrap
        // that re-adds us; every other record for it is dropped (it would
        // otherwise leave orphan rows, e.g. a peer's self-member payload).
        final left = await _settings.leftGroup(group);
        if (!_alive) return;
        if (left != null) {
          if (!acceptsForLeftGroup(
            type: msg.type,
            content: msg.content,
            myMxid: _myMxid,
            tombstone: left,
          )) {
            debugPrint('[ledger] dropped ${msg.type} for left group $group');
            return;
          }
          await _settings.clearGroupLeft(group);
          if (!_alive) return;
        }
      }

      final linkOpen =
          msg.type == memberEventType &&
          groupKnown &&
          (await _link.policyOf(group)).isMixed;
      if (!_alive) return;
      if (!isSenderAuthorized(
        type: msg.type,
        senderId: msg.senderId,
        content: msg.content,
        members: members,
        groupKnown: groupKnown,
        linkOpen: linkOpen,
      )) {
        debugPrint(
          '[ledger] dropped ${msg.type} from non-member '
          '${msg.senderId} for group $group',
        );
        return;
      }

      // G6: every version must carry a valid signature by its editor's
      // device (RecordGate → RecordVerifier); refused ones are recorded.
      final gate = _gate!;
      final via = msg.senderId;
      switch (msg.type) {
        case expenseEventType:
          await gate.expense(msg.content, relayedBy: via);
        case settlementEventType:
          await gate.settlement(msg.content, relayedBy: via);
        case groupMetaEventType:
          await gate.meta(msg.content, relayedBy: via);
        case memberEventType:
          // A non-member may only touch the participant assigned to it (gate
          // above) — and that version must be signed by that very account.
          final senderIsMember = members.any(
            (m) => m.isActive && m.matrixId == msg.senderId,
          );
          await gate.member(
            msg.content,
            relayedBy: via,
            requiredSigner: senderIsMember ? null : msg.senderId,
          );
          if (isOwnLeaveFromOtherDevice(
            senderId: msg.senderId,
            content: msg.content,
            myMxid: _myMxid,
          )) {
            await _applyOwnLeave(group);
          }
        case bootstrapEventType:
          // Key attestations are trusted only from a sender we trust with the
          // whole group anyway: the inviter of a group new to us (TOFU), or
          // one of our own devices.
          final meta = msg.content['meta'];
          final name = meta is Map ? meta['name'] : msg.content['name'];
          if (name is String) _snapshotNames[group] = name;
          await gate.snapshot(
            msg.content,
            relayedBy: via,
            trustAttestations: !groupKnown || msg.senderId == _myMxid,
          );
      }
      if (!_alive) return;
      await _proveConvergence(group, msg);
    } catch (e) {
      // After dispose / DB close a failure is expected, not worth logging.
      if (_alive) debugPrint('[ledger] failed to process ${msg.type}: $e');
    }
  }

  /// G29: an inbound record from a peer may prove that peer now holds
  /// everything we hold (see `peer_convergence.dart`) — then mark it in sync
  /// right away instead of waiting for the digest round-trip, so the sync
  /// icon turns "Synced" as soon as the peer's own change has arrived.
  Future<void> _proveConvergence(String groupId, TransportMessage msg) async {
    final peer = msg.senderId;
    if (peer == _myMxid) return; // own devices don't show in the sync status
    final rev = inboundRecordRevision(msg.type, msg.content);
    if (rev == null) return;
    _convergence.noteHeld(groupId, peer, rev.key, rev.updatedAt);

    final group = await _groups.getGroup(groupId);
    if (!_alive || group == null) return;
    final members = await _members.getMembers(groupId);
    if (!_alive) return;
    // Only a claimed, active peer has a sync status worth proving.
    if (!members.any((m) => m.isActive && m.matrixId == peer)) return;
    final expenses = await _expenses.getAllExpensesForGroup(groupId);
    if (!_alive) return;
    final settlements = await _expenses.getAllSettlementsForGroup(groupId);
    if (!_alive) return;
    final states = await _syncStates.getSyncStates(groupId);
    if (!_alive) return;
    final inSyncAt =
        states
            .where((s) => s.userId == peer)
            .map((s) => s.lastInSyncAt)
            .firstOrNull ??
        0;
    final local = localRecordClocks(
      group: group,
      members: members,
      expenses: expenses,
      settlements: settlements,
    );
    if (!peerHoldsEverything(
      local: local,
      inSyncAt: inSyncAt,
      heldByPeer: _convergence.heldBy(groupId, peer),
    )) {
      return;
    }
    // Our wall clock, like rule 4 — not the newest record's clock, which may
    // be a peer's skewed (up to +5 min clamped) clock: claiming that would
    // show our own next writes as replicated before they are.
    final at = DateTime.now().millisecondsSinceEpoch;
    if (at <= inSyncAt) return;
    await _syncStates.markInSync(groupId, peer, at);
    _convergence.prune(groupId, peer, at);
  }

  /// G26: we left [groupId] on another of our devices — that device relayed
  /// our `removed` record to us too. If it won LWW (we're now removed here),
  /// leave exactly like `GroupExiter.leave` did there: purge the group and
  /// keep the tombstone (with our removal notice for rule 7) — but send
  /// nothing, the leaving device already told everyone.
  Future<void> _applyOwnLeave(String groupId) async {
    if (!_alive) return;
    final me = await _members.memberByMatrixId(groupId, _myMxid!);
    if (!_alive || me == null || me.isActive) return;
    await _settings.purgeGroupAsLeft(
      groupId,
      LeftGroupTombstone(
        leftAt: me.updatedAt,
        removalNotice: memberPayload(me),
      ),
    );
  }

  /// Whether an inbound `member` payload is **our own leave relayed from
  /// another of our devices**: sent by our own MXID, about our own MXID, with
  /// status `removed`. (Removal by *another* member is sent by them — the
  /// group then stays, read-only, see `ExpensesPage`.)
  @visibleForTesting
  static bool isOwnLeaveFromOtherDevice({
    required String senderId,
    required Map<String, dynamic> content,
    required String? myMxid,
  }) =>
      myMxid != null &&
      senderId == myMxid &&
      content['matrix_id'] == myMxid &&
      content['status'] == 'removed';

  // ── inbound authorization (plain-Dart, unit-testable) ───────────────────────

  /// Whether an inbound record of [type] from the E2EE-authenticated [senderId]
  /// may be applied to its group, given that group's current [members] and
  /// whether the group is already known locally ([groupKnown]).
  ///
  /// - **expense / settlement / group meta:** sender must be an active claimed
  ///   member of the group.
  /// - **bootstrap:** an **unknown** group is TOFU-accepted (an inviter or one of
  ///   your own devices defines it); a **known** group is re-snapshotted only by
  ///   an active member, so a stranger can't rewrite it wholesale.
  /// - **member:** an active member may gossip any membership change. A
  ///   non-member (never added, or **removed** — removal must stick) may only
  ///   update the participant an active member already **assigned to its own
  ///   account**: an existing participant with `matrixId == senderId` whose
  ///   latest status is `active` (in practice that makes it a member, so this
  ///   never lets anyone in). It can **never** create a participant, reactivate
  ///   a `removed` one, or claim an unclaimed local participant — joining a
  ///   group (and claiming a local person) is done by an active member
  ///   (`MemberAdder.add` / `invite` / `claim`, G18 review).
  @visibleForTesting
  static bool isSenderAuthorized({
    required String type,
    required String senderId,
    required Map<String, dynamic> content,
    required List<MemberModel> members,
    required bool groupKnown,
    bool linkOpen = false,
  }) {
    final senderIsActiveMember = members.any(
      (m) => m.isActive && m.matrixId == senderId,
    );

    switch (type) {
      case bootstrapEventType:
        return !groupKnown || senderIsActiveMember;
      case memberEventType:
        if (senderIsActiveMember) return true;
        final participantId =
            content['participant_id'] as String? ?? content['user'] as String?;
        if (content['matrix_id'] != senderId ||
            content['status'] != 'active' ||
            participantId == null) {
          return false;
        }
        final existing = members.where((m) => m.userId == participantId);
        if (existing.isEmpty || !existing.first.isActive) return false;
        // G53 (§10.1): while the group's link is open (mixed), a link
        // participant may claim itself — an active participant nobody
        // claims yet; the record gate requires the sender's own signature.
        if (linkOpen && existing.first.matrixId == null) return true;
        return existing.first.matrixId == senderId;
      case expenseEventType:
      case settlementEventType:
      case groupMetaEventType:
        return senderIsActiveMember;
      default:
        return false;
    }
  }

  /// Whether an inbound record for a group we **left / deleted** (G9) may be
  /// applied: only a `bootstrap` whose members list our MXID `active` with a
  /// clock newer than the tombstone — i.e. we were re-added. A stale snapshot
  /// (a peer that missed our leave, or our own other device answering a
  /// resync) still lists us with the old clock and is ignored.
  @visibleForTesting
  static bool acceptsForLeftGroup({
    required String type,
    required Map<String, dynamic> content,
    required String? myMxid,
    required LeftGroupTombstone tombstone,
  }) {
    if (type != bootstrapEventType || myMxid == null) return false;
    // Only the snapshot's own member entries count (G18 review): an entry of
    // another group must not lift this group's tombstone.
    final snap = snapshotEntries(content);
    if (snap == null) return false;
    return classifyPeerViewOfMe(
          memberRecords: snap.members,
          myMxid: myMxid,
          leftAt: tombstone.leftAt,
        ) ==
        PeerViewOfMe.readded;
  }

  /// Clamps an inbound LWW clock to at most `now + tolerance` so a future-dated
  /// record can't dominate every merge. [now] defaults to the wall clock.
  @visibleForTesting
  static int clampInboundClock(int updatedAt, {int? now}) {
    final ceiling =
        (now ?? DateTime.now().millisecondsSinceEpoch) + _clockSkewToleranceMs;
    return updatedAt > ceiling ? ceiling : updatedAt;
  }

  // ── payload processors (plain-Dart, unit-testable) ──────────────────────────
  // Each payload carries its `group` id (the local Groups.roomId value) so the
  // receiver can route it without any room context. Merge is idempotent on the
  // record `id`; membership uses last-writer-wins via [MembersDao].

  @visibleForTesting
  static Future<void> processExpense(
    Map<String, dynamic> content,
    ExpensesDao dao,
  ) {
    final id = content['id'] as String?;
    final group = content['group'] as String?;
    if (id == null || group == null) return Future.value();
    final createdAt =
        content['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    return dao.upsertExpenseLww(
      ExpensesCompanion(
        id: Value(id),
        roomId: Value(group),
        description: Value(content['description'] as String? ?? ''),
        amountCents: Value(content['amount'] as int? ?? 0),
        currency: Value(content['currency'] as String? ?? 'EUR'),
        paidBy: Value(content['paid_by'] as String? ?? ''),
        splitsJson: Value(jsonEncode(content['split'] ?? {})),
        createdAt: Value(createdAt),
        updatedAt: Value(
          clampInboundClock(content['updated_at'] as int? ?? createdAt),
        ),
        deleted: Value(content['deleted'] as bool? ?? false),
        category: Value(_optString(content['category'])),
        note: Value(_optString(content['note'])),
        expenseDate: Value(_optString(content['date'])),
        sig: Value(RecordSignature.fromJson(content['sig'])?.encode()),
        origin: Value(RecordSignature.fromJson(content['origin'])?.encode()),
        // G52: the Matrix path never keeps a `by` hint — set it explicitly
        // (an absent value would keep the previous version's on update).
        linkAuthor: const Value(null),
      ),
      source: HistorySource.inbound,
    );
  }

  static String? _optString(Object? v) =>
      v is String && v.isNotEmpty ? v : null;

  @visibleForTesting
  static Future<void> processSettlement(
    Map<String, dynamic> content,
    ExpensesDao dao,
  ) {
    final id = content['id'] as String?;
    final group = content['group'] as String?;
    if (id == null || group == null) return Future.value();
    final createdAt =
        content['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    return dao.upsertSettlementLww(
      SettlementsCompanion(
        id: Value(id),
        roomId: Value(group),
        amountCents: Value(content['amount'] as int? ?? 0),
        currency: Value(content['currency'] as String? ?? 'EUR'),
        fromUser: Value(content['from'] as String? ?? ''),
        toUser: Value(content['to'] as String? ?? ''),
        createdAt: Value(createdAt),
        updatedAt: Value(
          clampInboundClock(content['updated_at'] as int? ?? createdAt),
        ),
        deleted: Value(content['deleted'] as bool? ?? false),
        settlementDate: Value(_optString(content['date'])),
        sig: Value(RecordSignature.fromJson(content['sig'])?.encode()),
        origin: Value(RecordSignature.fromJson(content['origin'])?.encode()),
        // G52: the Matrix path never keeps a `by` hint — set it explicitly
        // (an absent value would keep the previous version's on update).
        linkAuthor: const Value(null),
      ),
      source: HistorySource.inbound,
    );
  }

  @visibleForTesting
  static Future<void> processGroupMeta(
    Map<String, dynamic> content,
    GroupsDao dao,
  ) {
    final group = content['group'] as String?;
    if (group == null) return Future.value();
    // Missing clock means a pre-v1 payload: treat as oldest (0) so it can
    // create the group but never overwrite a newer local rename.
    return dao.upsertGroupLww(
      GroupsCompanion(
        roomId: Value(group),
        name: Value(content['name'] as String? ?? group),
        currency: Value(content['currency'] as String? ?? 'EUR'),
        updatedAt: Value(clampInboundClock(content['updated_at'] as int? ?? 0)),
        categoriesJson: Value(
          encodeCategories(parseCustomCategories(content['categories'])),
        ),
        sig: Value(RecordSignature.fromJson(content['sig'])?.encode()),
        linkAuthor: const Value(null), // G52: see processExpense
      ),
      source: HistorySource.inbound,
    );
  }

  @visibleForTesting
  static Future<void> processMember(
    Map<String, dynamic> content,
    MembersDao dao,
  ) {
    final group = content['group'] as String?;
    // `participant_id` is the virtual-users key; `user` is the older key.
    final participantId =
        content['participant_id'] as String? ?? content['user'] as String?;
    if (group == null || participantId == null) return Future.value();
    return dao.upsertMemberLww(
      MembersCompanion(
        groupId: Value(group),
        userId: Value(participantId),
        displayName: Value(content['name'] as String? ?? ''),
        matrixId: Value(content['matrix_id'] as String?),
        status: Value(content['status'] as String? ?? 'active'),
        updatedAt: Value(
          clampInboundClock(
            content['updated_at'] as int? ??
                DateTime.now().millisecondsSinceEpoch,
          ),
        ),
        sig: Value(RecordSignature.fromJson(content['sig'])?.encode()),
        linkAuthor: const Value(null), // G52: see processExpense
      ),
      source: HistorySource.inbound,
    );
  }

  /// New-member bootstrap: a single payload carrying the group meta, full member
  /// list, and the whole ledger. Each nested record carries its own `group` id.
  ///
  /// **Unverified** low-level merge (tests / tooling). The live syncer and the
  /// backup restore go through `RecordGate.snapshot`, which verifies every
  /// version's signature first (G6).
  @visibleForTesting
  static Future<void> processBootstrap(
    Map<String, dynamic> content,
    GroupsDao groupDao,
    MembersDao memberDao,
    ExpensesDao expDao, {
    bool Function()? isAlive,
  }) async {
    // [isAlive] lets the live syncer stop mid-snapshot when it's disposed or
    // its DB closes (account switch) instead of writing into a closed DB.
    bool stop() => isAlive != null && !isAlive();
    // Only entries of the snapshot's own group (G18 review).
    final snap = snapshotEntries(content);
    if (snap == null) return;
    await processGroupMeta(snap.meta, groupDao);
    for (final m in snap.members) {
      if (stop()) return;
      await processMember(m, memberDao);
    }
    for (final e in snap.expenses) {
      if (stop()) return;
      await processExpense(e, expDao);
    }
    for (final s in snap.settlements) {
      if (stop()) return;
      await processSettlement(s, expDao);
    }
  }
}
