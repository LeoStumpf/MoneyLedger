import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/expenses/expenses_provider.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../database/app_database.dart';
import '../matrix/ledger_transport.dart';
import '../matrix/transport_provider.dart';
import 'ledger_payloads.dart';

/// How often each group's digest is broadcast to its members. Injectable so
/// tests can disable/shorten it.
final syncIntervalProvider =
    Provider<Duration>((ref) => const Duration(minutes: 10));

/// Debounce between receiving a ledger payload and sending the "ack" digest.
final pokeDebounceProvider =
    Provider<Duration>((ref) => const Duration(seconds: 5));

final syncEngineProvider = Provider.autoDispose<SyncEngine>((ref) {
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
///    (group, sender) — this feeds the sync-status UI.
/// 5. A digest for a group we don't know → `resync_request` back to the
///    sender (they bootstrap us if we're a member).
/// 6. A digest from a sender we have as `removed` → reply only with their
///    member-tombstone payload so their device learns of the removal.
class SyncEngine {
  final Ref _ref;
  LedgerTransport? _transport;
  StreamSubscription<TransportMessage>? _sub;
  Timer? _periodic;
  final Map<String, Timer> _pokes = {};
  bool _disposed = false;

  SyncEngine(this._ref);

  Future<void> start() async {
    final LedgerTransport transport;
    try {
      transport = await _ref.read(ledgerTransportProvider.future);
    } catch (e) {
      debugPrint('[sync] engine inactive, no transport: $e');
      return;
    }
    if (_disposed) return;
    _transport = transport;
    _sub = transport.onMessage.listen(_onMessage);
    _periodic = Timer.periodic(
        _ref.read(syncIntervalProvider), (_) => broadcastDigests());
    try {
      // New or reinstalled device (empty local DB): ask our own other devices
      // for everything. Groups shared by peers are additionally recovered
      // organically — their digests name groups we don't know (rule 5).
      final groups = await _ref.read(groupsDaoProvider).getAllGroups();
      if (groups.isEmpty) {
        await transport.sendToUsers({transport.userId}, resyncRequestEventType,
            {'v': protocolVersion, 'scope': 'all'});
        return;
      }
    } catch (e) {
      debugPrint('[sync] self-resync check failed: $e');
    }
    await broadcastDigests();
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _periodic?.cancel();
    for (final t in _pokes.values) {
      t.cancel();
    }
    _pokes.clear();
  }

  /// Sends a digest for every local group to its active members.
  Future<void> broadcastDigests() async {
    if (_disposed) return;
    try {
      final groups = await _ref.read(groupsDaoProvider).getAllGroups();
      for (final g in groups) {
        await _sendDigest(g.roomId);
      }
    } catch (e) {
      debugPrint('[sync] digest broadcast failed: $e');
    }
  }

  /// Debounced "something changed in [groupId]": coalesces a burst of inbound
  /// payloads into one digest, which acts as the delivery ack to the writer.
  void pokeGroup(String groupId) {
    if (_disposed) return;
    _pokes[groupId]?.cancel();
    _pokes[groupId] = Timer(_ref.read(pokeDebounceProvider), () {
      _pokes.remove(groupId);
      _sendDigest(groupId);
    });
  }

  void _onMessage(TransportMessage msg) {
    if (_disposed) return;
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
    }
  }

  Future<void> _sendDigest(String groupId,
      {String? onlyTo, bool reply = false}) async {
    final transport = _transport;
    if (transport == null || _disposed) return;
    try {
      final group = await _ref.read(groupsDaoProvider).getGroup(groupId);
      if (group == null) return;
      final members = await _ref.read(membersDaoProvider).getMembers(groupId);
      // A device that knows itself to be removed stops broadcasting digests —
      // this also bounds the rule-6 exchange (removed member's digest →
      // member-tombstone payload → poke) to a single round.
      final self = _memberOf(members, transport.userId);
      if (self == null || !self.isActive) return;
      final expenses =
          await _ref.read(expensesDaoProvider).getAllExpensesForGroup(groupId);
      final settlements = await _ref
          .read(expensesDaoProvider)
          .getAllSettlementsForGroup(groupId);
      // Self is included (like _replicate): the digest reaches the user's own
      // other devices too, which is what repairs a stale second device.
      final targets = onlyTo != null
          ? {onlyTo}
          : members.where((m) => m.isActive).map((m) => m.userId).toSet();
      if (targets.isEmpty) return;
      await transport.sendToUsers(targets, digestEventType,
          buildDigestContent(group, members, expenses, settlements, reply: reply));
      final now = DateTime.now().millisecondsSinceEpoch;
      final syncStates = _ref.read(syncStatesDaoProvider);
      for (final t in targets) {
        await syncStates.markDigestSent(groupId, t, now);
      }
    } catch (e) {
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
      final group = await _ref.read(groupsDaoProvider).getGroup(groupId);
      if (group == null) {
        // Rule 5: we don't know this group — ask the sender to bootstrap us.
        await transport.sendToUsers({msg.senderId}, resyncRequestEventType,
            {'v': protocolVersion, 'scope': 'group', 'group': groupId});
        return;
      }

      final memberDao = _ref.read(membersDaoProvider);
      final members = await memberDao.getMembers(groupId);
      final senderRec = _memberOf(members, msg.senderId);
      if (senderRec != null && !senderRec.isActive) {
        // Rule 6: the sender was removed — tell their device, nothing else.
        await transport.sendToUsers(
            {msg.senderId}, memberEventType, memberPayload(senderRec));
        return;
      }

      final expDao = _ref.read(expensesDaoProvider);
      final expenses = await expDao.getAllExpensesForGroup(groupId);
      final settlements = await expDao.getAllSettlementsForGroup(groupId);

      // Compare against pre-merge state: "identical" must mean the sender had
      // everything we had at this moment.
      final diff = compareDigest(
        localMetaUpdatedAt: group.updatedAt,
        localMembers: {
          for (final m in members)
            m.userId: (status: m.status, updatedAt: m.updatedAt)
        },
        localExpenses: {for (final e in expenses) e.id: e.updatedAt},
        localSettlements: {for (final s in settlements) s.id: s.updatedAt},
        remote: content,
      );

      // Rule 2: membership gossip, merged LWW (same merge as live member
      // payloads — see LedgerSyncer.processMember).
      for (final entry
          in (content['members'] as Map? ?? const {}).entries) {
        final m = entry.value as Map;
        await memberDao.upsertMemberLww(MembersCompanion(
          groupId: Value(groupId),
          userId: Value(entry.key as String),
          status: Value(m['status'] as String? ?? 'active'),
          updatedAt: Value(m['updated_at'] as int? ?? 0),
        ));
      }

      // Rule 1: targeted repair of records the sender lacks or has stale.
      for (final id in diff.expenseIdsToSend) {
        final e = await expDao.getExpenseById(id);
        if (e != null) {
          await transport.sendToUsers(
              {msg.senderId}, expenseEventType, expensePayload(e));
        }
      }
      for (final id in diff.settlementIdsToSend) {
        final s = await expDao.getSettlementById(id);
        if (s != null) {
          await transport.sendToUsers(
              {msg.senderId}, settlementEventType, settlementPayload(s));
        }
      }
      if (diff.sendGroupMeta) {
        await transport.sendToUsers(
            {msg.senderId}, groupMetaEventType, groupMetaPayload(group));
      }

      // Rule 4: an exact match proves the sender has everything we have.
      if (diff.identical) {
        await _ref.read(syncStatesDaoProvider).markInSync(
            groupId, msg.senderId, DateTime.now().millisecondsSinceEpoch);
      }

      // Rule 3: always answer a primary digest; never answer a reply.
      if (content['reply'] != true) {
        await _sendDigest(groupId, onlyTo: msg.senderId, reply: true);
      }
    } catch (e) {
      debugPrint('[sync] digest handling failed for $groupId: $e');
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
        final groups = await _ref.read(groupsDaoProvider).getAllGroups();
        for (final g in groups) {
          await _sendBootstrap(transport, g.roomId, msg.senderId);
        }
      }
    } catch (e) {
      debugPrint('[sync] resync handling failed: $e');
    }
  }

  Future<void> _sendBootstrapIfMember(
      LedgerTransport transport, String groupId, String requester) async {
    if (requester != transport.userId) {
      final members =
          await _ref.read(membersDaoProvider).getMembers(groupId);
      final rec = _memberOf(members, requester);
      if (rec == null || !rec.isActive) return; // not a member — no data
    }
    await _sendBootstrap(transport, groupId, requester);
  }

  static MemberModel? _memberOf(List<MemberModel> members, String userId) {
    for (final m in members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  Future<void> _sendBootstrap(
      LedgerTransport transport, String groupId, String to) async {
    final expDao = _ref.read(expensesDaoProvider);
    final content = buildBootstrapContent(
      groupId,
      await _ref.read(groupsDaoProvider).getGroup(groupId),
      await _ref.read(membersDaoProvider).getMembers(groupId),
      await expDao.getAllExpensesForGroup(groupId),
      await expDao.getAllSettlementsForGroup(groupId),
    );
    await transport.sendToUsers({to}, bootstrapEventType, content);
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
}) =>
    {
      'v': protocolVersion,
      'group': group.roomId,
      'reply': reply,
      'meta_updated_at': group.updatedAt,
      'members': {
        for (final m in members)
          m.userId: {'status': m.status, 'updated_at': m.updatedAt}
      },
      'expenses': {for (final e in expenses) e.id: e.updatedAt},
      'settlements': {for (final s in settlements) s.id: s.updatedAt},
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
@visibleForTesting
DigestDiff compareDigest({
  required int localMetaUpdatedAt,
  required Map<String, ({String status, int updatedAt})> localMembers,
  required Map<String, int> localExpenses,
  required Map<String, int> localSettlements,
  required Map<String, dynamic> remote,
}) {
  var senderHasNewer = false;

  (List<String>, bool) diffRecords(
      Map<String, int> local, Map<String, dynamic> remoteMap) {
    final toSend = <String>[];
    var theirsNewer = false;
    for (final entry in local.entries) {
      final remoteAt = remoteMap[entry.key] as int?;
      if (remoteAt == null || remoteAt < entry.value) toSend.add(entry.key);
      if (remoteAt != null && remoteAt > entry.value) theirsNewer = true;
    }
    for (final key in remoteMap.keys) {
      if (!local.containsKey(key)) theirsNewer = true;
    }
    return (toSend, theirsNewer);
  }

  final remoteExpenses = (remote['expenses'] as Map? ?? const {});
  final remoteSettlements = (remote['settlements'] as Map? ?? const {});
  final (expensesToSend, expTheirs) =
      diffRecords(localExpenses, Map<String, dynamic>.from(remoteExpenses));
  final (settlementsToSend, setTheirs) = diffRecords(
      localSettlements, Map<String, dynamic>.from(remoteSettlements));
  senderHasNewer = expTheirs || setTheirs;

  final remoteMeta = remote['meta_updated_at'] as int? ?? 0;
  final sendGroupMeta = localMetaUpdatedAt > remoteMeta;
  if (remoteMeta > localMetaUpdatedAt) senderHasNewer = true;

  var membersIdentical = true;
  final remoteMembers = (remote['members'] as Map? ?? const {});
  if (remoteMembers.length != localMembers.length) membersIdentical = false;
  for (final entry in localMembers.entries) {
    final r = remoteMembers[entry.key] as Map?;
    if (r == null ||
        r['status'] != entry.value.status ||
        (r['updated_at'] as int? ?? 0) != entry.value.updatedAt) {
      membersIdentical = false;
    }
  }

  return DigestDiff(
    expenseIdsToSend: expensesToSend,
    settlementIdsToSend: settlementsToSend,
    sendGroupMeta: sendGroupMeta,
    senderHasNewer: senderHasNewer,
    identical: !senderHasNewer &&
        expensesToSend.isEmpty &&
        settlementsToSend.isEmpty &&
        !sendGroupMeta &&
        remoteMeta == localMetaUpdatedAt &&
        membersIdentical,
  );
}
