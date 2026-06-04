import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/members_dao.dart';
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

@Riverpod(keepAlive: true)
MembersDao membersDao(Ref ref) => MembersDao(ref.watch(appDatabaseProvider));

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
      final createdAt = DateTime.now().millisecondsSinceEpoch;
      // Local-first: persist to Drift immediately so the expense is saved and
      // visible even offline. Replication is best-effort afterwards.
      await ref.read(expensesDaoProvider).upsertExpense(ExpensesCompanion(
            id: Value(id),
            roomId: Value(roomId),
            description: Value(description),
            amountCents: Value(amountCents),
            currency: Value(currency),
            paidBy: Value(paidBy),
            splitsJson: Value(jsonEncode(splits)),
            createdAt: Value(createdAt),
          ));
      await _replicate(roomId, expenseEventType, {
        'id': id,
        'group': roomId,
        'description': description,
        'amount': amountCents,
        'currency': currency,
        'paid_by': paidBy,
        'split': splits,
        'created_at': createdAt,
      });
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
      final createdAt = DateTime.now().millisecondsSinceEpoch;
      // Local-first: persist before replicating (see addExpense).
      await ref.read(expensesDaoProvider).upsertSettlement(SettlementsCompanion(
            id: Value(id),
            roomId: Value(roomId),
            amountCents: Value(amountCents),
            currency: Value(currency),
            fromUser: Value(fromUser),
            toUser: Value(toUser),
            createdAt: Value(createdAt),
          ));
      await _replicate(roomId, settlementEventType, {
        'id': id,
        'group': roomId,
        'amount': amountCents,
        'currency': currency,
        'from': fromUser,
        'to': toUser,
        'created_at': createdAt,
      });
    });
  }

  /// Best-effort replication to the group's active members via encrypted
  /// to-device. The record is already saved locally, so a transport failure
  /// (offline) must not fail the user action — the homeserver queues undelivered
  /// to-device messages and the SDK retries. Self is included so the user's
  /// other devices stay in sync (the SDK skips the current device).
  Future<void> _replicate(
      String groupId, String type, Map<String, dynamic> content) async {
    try {
      final members = await ref.read(membersDaoProvider).activeMemberIds(groupId);
      if (members.isEmpty) return;
      final transport = await ref.read(ledgerTransportProvider.future);
      await transport.sendToUsers(members.toSet(), type, content);
    } catch (e) {
      debugPrint('[ledger] saved locally; replication deferred: $e');
    }
  }
}
