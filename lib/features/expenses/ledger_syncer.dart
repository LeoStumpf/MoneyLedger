import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/matrix/matrix_service.dart';
import '../auth/auth_provider.dart';
import 'expenses_provider.dart';

final ledgerSyncerProvider = Provider.autoDispose<LedgerSyncer>((ref) {
  final syncer = LedgerSyncer(ref);
  syncer.start();
  ref.onDispose(syncer.dispose);
  return syncer;
});

class LedgerSyncer {
  final Ref _ref;
  bool _disposed = false;
  Client? _client;

  LedgerSyncer(this._ref);

  Future<void> start() async {
    final client = await _ref.read(matrixClientProvider.future);
    if (_disposed) return;
    _client = client;
    // Attach the delta listener first so no live updates are missed while we
    // reconcile, then backfill from rooms already known to the client.
    client.onSync.stream.listen(_onSync);
    await _reconcileExistingRooms(client);
  }

  /// Scans rooms already known to the client (loaded from the local store on a
  /// hard refresh, or joined in a prior session) and writes any ledger groups
  /// plus their historical timeline events into Drift.
  ///
  /// Without this, a user who joined a group before the onSync listener was
  /// attached would never see it: incremental syncs only carry deltas, so the
  /// `app.moneyledger.group` state event — set once when the room was created —
  /// is never re-sent on later syncs.
  Future<void> _reconcileExistingRooms(Client client) async {
    final groupDao = _ref.read(groupsDaoProvider);
    final expDao = _ref.read(expensesDaoProvider);
    for (final room in client.rooms) {
      if (_disposed) return;
      final groupState = room.getState(groupStateEventType);
      if (groupState == null) continue; // not a ledger group
      processGroupState(
        room.id,
        groupState.content,
        room.name.isNotEmpty ? room.name : room.id,
        groupDao,
      );
      await _reconcileTimeline(room, expDao);
    }
  }

  /// Loads a room's timeline and replays any expense/settlement events into
  /// Drift, so a freshly-joined user sees the full history, not just events
  /// that arrive after they joined.
  Future<void> _reconcileTimeline(Room room, ExpensesDao expDao) async {
    try {
      final timeline = await room.getTimeline();
      for (final event in timeline.events) {
        if (_disposed) return;
        if (event.type == expenseEventType) {
          processExpense(room.id, event.eventId, event.content,
              event.originServerTs.millisecondsSinceEpoch, expDao);
        } else if (event.type == settlementEventType) {
          processSettlement(room.id, event.eventId, event.content,
              event.originServerTs.millisecondsSinceEpoch, expDao);
        }
      }
    } catch (_) {
      // Timeline unavailable right now — live sync will fill it in.
    }
  }

  void dispose() {
    _disposed = true;
  }

  void _onSync(SyncUpdate sync) {
    if (_disposed) return;
    final expDao = _ref.read(expensesDaoProvider);
    final groupDao = _ref.read(groupsDaoProvider);

    // Re-scan every known room for ledger-group state on each sync. Group state
    // is only re-sent in full syncs, so relying on the per-sync state delta
    // alone misses groups a returning or just-joined user already belongs to.
    final client = _client;
    if (client != null) {
      for (final room in client.rooms) {
        final groupState = room.getState(groupStateEventType);
        if (groupState != null) {
          processGroupState(room.id, groupState.content,
              room.name.isNotEmpty ? room.name : room.id, groupDao);
        }
      }
    }

    final rooms = sync.rooms;
    if (rooms == null) return;

    for (final entry in (rooms.join ?? {}).entries) {
      final roomId = entry.key;
      final roomUpdate = entry.value;

      for (final event in roomUpdate.timeline?.events ?? []) {
        if (event.type == expenseEventType) {
          processExpense(
              roomId, event.eventId, event.content,
              event.originServerTs.millisecondsSinceEpoch, expDao);
        } else if (event.type == settlementEventType) {
          processSettlement(
              roomId, event.eventId, event.content,
              event.originServerTs.millisecondsSinceEpoch, expDao);
        }
      }
    }
  }

  @visibleForTesting
  static void processExpense(
    String roomId,
    String? eventId,
    Map<String, dynamic> content,
    int tsMs,
    ExpensesDao dao,
  ) {
    final id = content['id'] as String?;
    if (id == null) return;
    dao.upsertExpense(ExpensesCompanion(
      id: Value(id),
      roomId: Value(roomId),
      matrixEventId: Value(eventId),
      description: Value(content['description'] as String? ?? ''),
      amountCents: Value(content['amount'] as int? ?? 0),
      currency: Value(content['currency'] as String? ?? 'EUR'),
      paidBy: Value(content['paid_by'] as String? ?? ''),
      splitsJson: Value(jsonEncode(content['split'] ?? {})),
      createdAt: Value(tsMs),
    ));
  }

  @visibleForTesting
  static void processSettlement(
    String roomId,
    String? eventId,
    Map<String, dynamic> content,
    int tsMs,
    ExpensesDao dao,
  ) {
    final id = content['id'] as String?;
    if (id == null) return;
    dao.upsertSettlement(SettlementsCompanion(
      id: Value(id),
      roomId: Value(roomId),
      matrixEventId: Value(eventId),
      amountCents: Value(content['amount'] as int? ?? 0),
      currency: Value(content['currency'] as String? ?? 'EUR'),
      fromUser: Value(content['from'] as String? ?? ''),
      toUser: Value(content['to'] as String? ?? ''),
      createdAt: Value(tsMs),
    ));
  }

  @visibleForTesting
  static void processGroupState(
    String roomId,
    Map<String, dynamic> content,
    String roomName,
    GroupsDao dao,
  ) {
    final currency = content['currency'] as String? ?? 'EUR';
    dao.upsertGroup(GroupsCompanion(
      roomId: Value(roomId),
      name: Value(roomName),
      currency: Value(currency),
    ));
  }
}
