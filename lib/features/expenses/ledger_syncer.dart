import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/matrix/matrix_service.dart';
import '../auth/auth_provider.dart';
import 'expenses_provider.dart';

final ledgerSyncerProvider = Provider.autoDispose<_LedgerSyncer>((ref) {
  final syncer = _LedgerSyncer(ref);
  syncer.start();
  ref.onDispose(syncer.dispose);
  return syncer;
});

class _LedgerSyncer {
  final Ref _ref;
  bool _disposed = false;

  _LedgerSyncer(this._ref);

  Future<void> start() async {
    final client = await _ref.read(matrixClientProvider.future);
    if (_disposed) return;
    client.onSync.stream.listen(_onSync);
  }

  void dispose() {
    _disposed = true;
  }

  void _onSync(SyncUpdate sync) {
    if (_disposed) return;
    final expDao = _ref.read(expensesDaoProvider);
    final rooms = sync.rooms;
    if (rooms == null) return;

    for (final entry in (rooms.join ?? {}).entries) {
      final roomId = entry.key;
      final roomUpdate = entry.value;
      for (final event in roomUpdate.timeline?.events ?? []) {
        _handleEvent(roomId, event, expDao);
      }
    }
  }

  void _handleEvent(String roomId, MatrixEvent event, ExpensesDao expDao) {
    if (event.type == expenseEventType) {
      final c = event.content;
      final id = c['id'] as String?;
      if (id == null) return;
      expDao.upsertExpense(ExpensesCompanion(
        id: Value(id),
        roomId: Value(roomId),
        matrixEventId: Value(event.eventId),
        description: Value(c['description'] as String? ?? ''),
        amountCents: Value(c['amount'] as int? ?? 0),
        currency: Value(c['currency'] as String? ?? 'EUR'),
        paidBy: Value(c['paid_by'] as String? ?? ''),
        splitsJson: Value(jsonEncode(c['split'] ?? {})),
        createdAt: Value(
          event.originServerTs.millisecondsSinceEpoch,
        ),
      ));
    } else if (event.type == settlementEventType) {
      final c = event.content;
      final id = c['id'] as String?;
      if (id == null) return;
      expDao.upsertSettlement(SettlementsCompanion(
        id: Value(id),
        roomId: Value(roomId),
        matrixEventId: Value(event.eventId),
        amountCents: Value(c['amount'] as int? ?? 0),
        currency: Value(c['currency'] as String? ?? 'EUR'),
        fromUser: Value(c['from'] as String? ?? ''),
        toUser: Value(c['to'] as String? ?? ''),
        createdAt: Value(
          event.originServerTs.millisecondsSinceEpoch,
        ),
      ));
    }
  }
}
