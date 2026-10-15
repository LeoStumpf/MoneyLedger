import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../models/member_model.dart';
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
  bool _disposed = false;
  StreamSubscription<TransportMessage>? _sub;

  LedgerSyncer(this._ref);

  Future<void> start() async {
    final transport = await _ref.read(ledgerTransportProvider.future);
    if (_disposed) return;
    _sub = transport.onMessage.listen(_onMessage);
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
  }

  Future<void> _onMessage(TransportMessage msg) async {
    if (_disposed || !_recordTypes.contains(msg.type)) return;
    final group = msg.content['group'] as String?;
    if (group == null) return;

    final expDao = _ref.read(expensesDaoProvider);
    final groupDao = _ref.read(groupsDaoProvider);
    final memberDao = _ref.read(membersDaoProvider);

    try {
      // Inbound to-device messages are E2EE, so `msg.senderId` is authenticated;
      // the only missing trust check is that the sender belongs to the group
      // they are writing to. Fetch the group's current members + existence and
      // gate the record before applying it.
      final members = await memberDao.getMembers(group);
      if (_disposed) return;
      final groupKnown = (await groupDao.getGroup(group)) != null;
      if (_disposed) return;

      if (!isSenderAuthorized(
        type: msg.type,
        senderId: msg.senderId,
        content: msg.content,
        members: members,
        groupKnown: groupKnown,
      )) {
        debugPrint('[ledger] dropped ${msg.type} from non-member '
            '${msg.senderId} for group $group');
        return;
      }

      switch (msg.type) {
        case expenseEventType:
          processExpense(msg.content, expDao);
        case settlementEventType:
          processSettlement(msg.content, expDao);
        case groupMetaEventType:
          processGroupMeta(msg.content, groupDao);
        case memberEventType:
          processMember(msg.content, memberDao);
        case bootstrapEventType:
          processBootstrap(msg.content, groupDao, memberDao, expDao);
      }
    } catch (e) {
      debugPrint('[ledger] failed to process ${msg.type}: $e');
    }
  }

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
  /// - **member:** an active member may gossip any membership change; otherwise
  ///   the sender may only speak for **its own MXID** — claiming itself
  ///   (`matrix_id == senderId`) onto a new participant (join-as-new) or one that
  ///   is unclaimed / already its own (self-claim). It can never forge another
  ///   account's membership or **hijack** a participant already linked to someone
  ///   else.
  @visibleForTesting
  static bool isSenderAuthorized({
    required String type,
    required String senderId,
    required Map<String, dynamic> content,
    required List<MemberModel> members,
    required bool groupKnown,
  }) {
    final senderIsActiveMember = members.any(
        (m) => m.isActive && m.matrixId == senderId);

    switch (type) {
      case bootstrapEventType:
        return !groupKnown || senderIsActiveMember;
      case memberEventType:
        if (senderIsActiveMember) return true;
        // Non-members may only assert membership for their own account.
        final claimedMxid = content['matrix_id'] as String?;
        final participantId = content['participant_id'] as String? ??
            content['user'] as String?;
        if (claimedMxid == null || claimedMxid != senderId ||
            participantId == null) {
          return false;
        }
        // Allow a new participant (join-as-new) or one that is unclaimed / their
        // own — but never overwrite a participant another account already owns.
        final existing =
            members.where((m) => m.userId == participantId).toList();
        return existing.isEmpty ||
            existing.first.matrixId == null ||
            existing.first.matrixId == senderId;
      case expenseEventType:
      case settlementEventType:
      case groupMetaEventType:
        return senderIsActiveMember;
      default:
        return false;
    }
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
  static void processExpense(Map<String, dynamic> content, ExpensesDao dao) {
    final id = content['id'] as String?;
    final group = content['group'] as String?;
    if (id == null || group == null) return;
    final createdAt =
        content['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    dao.upsertExpenseLww(ExpensesCompanion(
      id: Value(id),
      roomId: Value(group),
      description: Value(content['description'] as String? ?? ''),
      amountCents: Value(content['amount'] as int? ?? 0),
      currency: Value(content['currency'] as String? ?? 'EUR'),
      paidBy: Value(content['paid_by'] as String? ?? ''),
      splitsJson: Value(jsonEncode(content['split'] ?? {})),
      createdAt: Value(createdAt),
      updatedAt: Value(clampInboundClock(content['updated_at'] as int? ?? createdAt)),
      deleted: Value(content['deleted'] as bool? ?? false),
    ));
  }

  @visibleForTesting
  static void processSettlement(Map<String, dynamic> content, ExpensesDao dao) {
    final id = content['id'] as String?;
    final group = content['group'] as String?;
    if (id == null || group == null) return;
    final createdAt =
        content['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    dao.upsertSettlementLww(SettlementsCompanion(
      id: Value(id),
      roomId: Value(group),
      amountCents: Value(content['amount'] as int? ?? 0),
      currency: Value(content['currency'] as String? ?? 'EUR'),
      fromUser: Value(content['from'] as String? ?? ''),
      toUser: Value(content['to'] as String? ?? ''),
      createdAt: Value(createdAt),
      updatedAt: Value(clampInboundClock(content['updated_at'] as int? ?? createdAt)),
      deleted: Value(content['deleted'] as bool? ?? false),
    ));
  }

  @visibleForTesting
  static void processGroupMeta(Map<String, dynamic> content, GroupsDao dao) {
    final group = content['group'] as String?;
    if (group == null) return;
    // Missing clock means a pre-v1 payload: treat as oldest (0) so it can
    // create the group but never overwrite a newer local rename.
    dao.upsertGroupLww(GroupsCompanion(
      roomId: Value(group),
      name: Value(content['name'] as String? ?? group),
      currency: Value(content['currency'] as String? ?? 'EUR'),
      updatedAt: Value(clampInboundClock(content['updated_at'] as int? ?? 0)),
    ));
  }

  @visibleForTesting
  static void processMember(Map<String, dynamic> content, MembersDao dao) {
    final group = content['group'] as String?;
    // `participant_id` is the virtual-users key; `user` is the older key.
    final participantId =
        content['participant_id'] as String? ?? content['user'] as String?;
    if (group == null || participantId == null) return;
    dao.upsertMemberLww(MembersCompanion(
      groupId: Value(group),
      userId: Value(participantId),
      displayName: Value(content['name'] as String? ?? ''),
      matrixId: Value(content['matrix_id'] as String?),
      status: Value(content['status'] as String? ?? 'active'),
      updatedAt: Value(clampInboundClock(
          content['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch)),
    ));
  }

  /// New-member bootstrap: a single payload carrying the group meta, full member
  /// list, and the whole ledger. Each nested record carries its own `group` id.
  @visibleForTesting
  static void processBootstrap(
    Map<String, dynamic> content,
    GroupsDao groupDao,
    MembersDao memberDao,
    ExpensesDao expDao,
  ) {
    processGroupMeta(content, groupDao);
    for (final m in (content['members'] as List? ?? const [])) {
      processMember(Map<String, dynamic>.from(m as Map), memberDao);
    }
    for (final e in (content['expenses'] as List? ?? const [])) {
      processExpense(Map<String, dynamic>.from(e as Map), expDao);
    }
    for (final s in (content['settlements'] as List? ?? const [])) {
      processSettlement(Map<String, dynamic>.from(s as Map), expDao);
    }
  }
}
