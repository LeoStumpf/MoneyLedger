import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import 'expenses_provider.dart';

final ledgerSyncerProvider = Provider.autoDispose<LedgerSyncer>((ref) {
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

  void _onMessage(TransportMessage msg) {
    if (_disposed) return;
    final expDao = _ref.read(expensesDaoProvider);
    final groupDao = _ref.read(groupsDaoProvider);
    final memberDao = _ref.read(membersDaoProvider);
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
      updatedAt: Value(content['updated_at'] as int? ?? createdAt),
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
      updatedAt: Value(content['updated_at'] as int? ?? createdAt),
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
      updatedAt: Value(content['updated_at'] as int? ?? 0),
    ));
  }

  @visibleForTesting
  static void processMember(Map<String, dynamic> content, MembersDao dao) {
    final group = content['group'] as String?;
    final userId = content['user'] as String?;
    if (group == null || userId == null) return;
    dao.upsertMemberLww(MembersCompanion(
      groupId: Value(group),
      userId: Value(userId),
      status: Value(content['status'] as String? ?? 'active'),
      updatedAt: Value(
          content['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
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
