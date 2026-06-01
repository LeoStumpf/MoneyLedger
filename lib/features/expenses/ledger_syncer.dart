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
    client.onSync.stream.listen(_onSync);
  }

  void dispose() {
    _disposed = true;
  }

  void _onSync(SyncUpdate sync) {
    if (_disposed) return;
    final expDao = _ref.read(expensesDaoProvider);
    final groupDao = _ref.read(groupsDaoProvider);
    final rooms = sync.rooms;
    if (rooms == null) return;

    for (final entry in (rooms.join ?? {}).entries) {
      final roomId = entry.key;
      final roomUpdate = entry.value;

      for (final stateEvent in roomUpdate.state ?? []) {
        if (stateEvent.type == groupStateEventType) {
          final name = _client?.getRoomById(roomId)?.name ?? roomId;
          processGroupState(roomId, stateEvent.content, name, groupDao);
        }
      }

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
