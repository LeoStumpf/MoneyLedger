import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import 'expenses_provider.dart';

final ledgerSyncerProvider = Provider.autoDispose<LedgerSyncer>((ref) {
  final syncer = LedgerSyncer(ref);
  syncer.start();
  ref.onDispose(syncer.dispose);
  return syncer;
});

/// Subscribes to the transport's sync stream and mirrors ledger data into Drift
/// (the local source of truth). All Matrix specifics live behind
/// [LedgerTransport]; this class only sees plain-Dart transport DTOs.
class LedgerSyncer {
  final Ref _ref;
  bool _disposed = false;
  LedgerTransport? _transport;
  StreamSubscription<TransportSyncUpdate>? _sub;

  /// Ledger rooms whose full history we've already paged in + replayed, so we
  /// don't re-page (a network round-trip) on every sync.
  final Set<String> _reconciled = {};

  LedgerSyncer(this._ref);

  Future<void> start() async {
    final transport = await _ref.read(ledgerTransportProvider.future);
    if (_disposed) return;
    _transport = transport;
    // Attach the delta listener first so no live updates are missed while we
    // reconcile, then backfill from rooms already known to the transport.
    _sub = transport.onSync.listen(_onSync);
    await _reconcileExistingRooms(transport);
  }

  /// Scans rooms already known (loaded from local store on a hard refresh, or
  /// joined in a prior session) and writes any ledger groups plus their
  /// historical timeline events into Drift. Incremental syncs only carry deltas,
  /// so the group state event — set once at room creation — is never re-sent.
  Future<void> _reconcileExistingRooms(LedgerTransport transport) async {
    final groupDao = _ref.read(groupsDaoProvider);
    final expDao = _ref.read(expensesDaoProvider);
    for (final room in transport.rooms) {
      if (_disposed) return;
      if (room.groupState == null) continue; // not a ledger group
      processGroupState(room.id, room.groupState!, room.displayName, groupDao);
      await _reconcileTimeline(transport, room.id, expDao);
    }
  }

  /// Pages in a room's full history and replays its timeline into Drift so a
  /// freshly-joined user sees the whole ledger, not just events that arrive
  /// after they joined or fall inside the current sync window. Runs at most once
  /// per room (tracked in [_reconciled]).
  Future<void> _reconcileTimeline(
      LedgerTransport transport, String roomId, ExpensesDao expDao) async {
    if (!_reconciled.add(roomId)) return; // already done
    try {
      await transport.loadHistory(roomId);
      if (_disposed) return;
      final events = await transport.timelineEvents(roomId);
      for (final event in events) {
        if (_disposed) return;
        _processEvent(roomId, event, expDao);
      }
    } catch (_) {
      // History unavailable right now — allow a later sync to retry.
      _reconciled.remove(roomId);
    }
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
  }

  void _onSync(TransportSyncUpdate sync) {
    if (_disposed) return;
    final expDao = _ref.read(expensesDaoProvider);
    final groupDao = _ref.read(groupsDaoProvider);

    // Re-scan every known room for ledger-group state on each sync. Group state
    // is only re-sent in full syncs, so relying on the per-sync delta alone
    // misses groups a returning or just-joined user already belongs to.
    final transport = _transport;
    if (transport != null) {
      for (final room in transport.rooms) {
        if (room.groupState != null) {
          processGroupState(
              room.id, room.groupState!, room.displayName, groupDao);
          // Backfill history the first time we see a ledger room live (e.g. one
          // joined after the syncer started). Self-guards against re-running.
          unawaited(_reconcileTimeline(transport, room.id, expDao));
        }
      }
    }

    sync.newTimelineEvents.forEach((roomId, events) {
      for (final event in events) {
        _processEvent(roomId, event, expDao);
      }
    });
  }

  void _processEvent(String roomId, TransportEvent event, ExpensesDao expDao) {
    if (event.type == expenseEventType) {
      processExpense(roomId, event.eventId, event.content,
          event.originServerTs, expDao);
    } else if (event.type == settlementEventType) {
      processSettlement(roomId, event.eventId, event.content,
          event.originServerTs, expDao);
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
