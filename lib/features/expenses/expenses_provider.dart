import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../models/expense_model.dart';

part 'expenses_provider.g.dart';

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) => AppDatabase();

@Riverpod(keepAlive: true)
ExpensesDao expensesDao(Ref ref) =>
    ExpensesDao(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
GroupsDao groupsDao(Ref ref) => GroupsDao(ref.watch(appDatabaseProvider));

@riverpod
Stream<List<ExpenseModel>> expensesForRoom(Ref ref, String roomId) {
  return ref.watch(expensesDaoProvider).watchExpensesForRoom(roomId);
}

@riverpod
Stream<List<SettlementModel>> settlementsForRoom(Ref ref, String roomId) {
  return ref.watch(expensesDaoProvider).watchSettlementsForRoom(roomId);
}

@riverpod
class ExpenseAdder extends _$ExpenseAdder {
  @override
  FutureOr<void> build() {}

  Future<void> addExpense({
    required String roomId,
    required String description,
    required int amountCents,
    required String currency,
    required String paidBy,
    required Map<String, int> splits,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final id = const Uuid().v7();
      // Local-first: persist to Drift immediately so the expense is saved and
      // visible even offline. matrixEventId stays null until replication
      // confirms it; the eventual sync echo re-upserts the same id.
      await ref.read(expensesDaoProvider).upsertExpense(ExpensesCompanion(
            id: Value(id),
            roomId: Value(roomId),
            description: Value(description),
            amountCents: Value(amountCents),
            currency: Value(currency),
            paidBy: Value(paidBy),
            splitsJson: Value(jsonEncode(splits)),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ));
      await _replicate((t) => t.sendExpense(roomId, {
            'id': id,
            'description': description,
            'amount': amountCents,
            'currency': currency,
            'paid_by': paidBy,
            'split': splits,
          }));
    });
  }

  Future<void> addSettlement({
    required String roomId,
    required int amountCents,
    required String currency,
    required String fromUser,
    required String toUser,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final id = const Uuid().v7();
      // Local-first: persist before replicating (see addExpense).
      await ref.read(expensesDaoProvider).upsertSettlement(SettlementsCompanion(
            id: Value(id),
            roomId: Value(roomId),
            amountCents: Value(amountCents),
            currency: Value(currency),
            fromUser: Value(fromUser),
            toUser: Value(toUser),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ));
      await _replicate((t) => t.sendSettlement(roomId, {
            'id': id,
            'amount': amountCents,
            'currency': currency,
            'from': fromUser,
            'to': toUser,
          }));
    });
  }

  /// Best-effort replication to group members. The record is already saved
  /// locally, so a transport failure (offline) must not fail the user action —
  /// the real Matrix transport queues + retries the send, and Phase B's
  /// to-device dispatcher will flush anything still unreplicated.
  Future<void> _replicate(
      Future<void> Function(LedgerTransport) send) async {
    try {
      final transport = await ref.read(ledgerTransportProvider.future);
      await send(transport);
    } catch (e) {
      debugPrint('[ledger] saved locally; replication deferred: $e');
    }
  }
}
