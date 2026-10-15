import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/account_database.dart';
import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/database/daos/sync_states_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../core/sync/ledger_payloads.dart';
import '../../core/sync/sync_health.dart';
import '../auth/auth_provider.dart';
import '../../models/expense_model.dart';

part 'expenses_provider.g.dart';

/// Opens the ledger DB for a signed-in MXID. Injectable so tests can back
/// accounts with temp-file / in-memory databases keyed by name.
final accountDatabaseOpenerProvider =
    Provider<AppDatabase Function(String mxid)>((ref) => openAccountDatabase);

/// The **current account's** ledger database (Phase G4: one DB per Matrix
/// account, see `account_database.dart`). Rebuilds when the signed-in account
/// changes: the previous account's DB is closed and every DAO / stream /
/// SyncEngine / LedgerSyncer that watches it rebuilds against the new one.
///
/// While signed out no database is opened: a [SignedOutExecutor] placeholder
/// (reads → no rows, writes → error) keeps the provider non-nullable for the
/// many synchronous consumers; a widget still mounted during the logout
/// transition sees an empty ledger, never another account's data.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final mxid = ref.watch(accountUserIdProvider);
  final db = mxid == null
      ? AppDatabase.forTesting(SignedOutExecutor())
      : ref.read(accountDatabaseOpenerProvider)(mxid);
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
ExpensesDao expensesDao(Ref ref) =>
    ExpensesDao(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
GroupsDao groupsDao(Ref ref) => GroupsDao(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
MembersDao membersDao(Ref ref) => MembersDao(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
SyncStatesDao syncStatesDao(Ref ref) =>
    SyncStatesDao(ref.watch(appDatabaseProvider));

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
      final createdAt = DateTime.now().millisecondsSinceEpoch;
      final expense = ExpenseModel(
        id: const Uuid().v7(),
        roomId: roomId,
        description: description,
        amountCents: amountCents,
        currency: currency,
        paidBy: paidBy,
        splitsJson: jsonEncode(splits),
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      // Local-first: persist to Drift immediately so the expense is saved and
      // visible even offline. Replication is best-effort afterwards.
      await ref
          .read(expensesDaoProvider)
          .upsertExpenseLww(_toCompanion(expense));
      await _replicate(roomId, expenseEventType, expensePayload(expense));
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
      final createdAt = DateTime.now().millisecondsSinceEpoch;
      final settlement = SettlementModel(
        id: const Uuid().v7(),
        roomId: roomId,
        amountCents: amountCents,
        currency: currency,
        fromUser: fromUser,
        toUser: toUser,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      // Local-first: persist before replicating (see addExpense).
      await ref
          .read(expensesDaoProvider)
          .upsertSettlementLww(_toSettlementCompanion(settlement));
      await _replicate(
          roomId, settlementEventType, settlementPayload(settlement));
    });
  }

  /// Edits an existing expense: the full record is re-written with a fresh
  /// LWW clock and replicated whole — concurrent edits of the same expense
  /// converge to the latest writer on every device.
  Future<void> updateExpense({
    required String id,
    required String roomId,
    required String description,
    required int amountCents,
    required String currency,
    required String paidBy,
    required Map<String, int> splits,
    required int createdAt,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final expense = ExpenseModel(
        id: id,
        roomId: roomId,
        description: description,
        amountCents: amountCents,
        currency: currency,
        paidBy: paidBy,
        splitsJson: jsonEncode(splits),
        createdAt: createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await ref
          .read(expensesDaoProvider)
          .upsertExpenseLww(_toCompanion(expense));
      await _replicate(roomId, expenseEventType, expensePayload(expense));
    });
  }

  /// Deletes an expense as a tombstone: the row is kept (deleted = true, fresh
  /// LWW clock) and replicated, so anti-entropy propagates the deletion and a
  /// stale peer can never resurrect it.
  Future<void> deleteExpense(String id, String roomId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(expensesDaoProvider);
      final current = await dao.getExpenseById(id);
      if (current == null) return;
      final tombstone = ExpenseModel(
        id: current.id,
        roomId: current.roomId,
        description: current.description,
        amountCents: current.amountCents,
        currency: current.currency,
        paidBy: current.paidBy,
        splitsJson: current.splitsJson,
        createdAt: current.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        deleted: true,
      );
      await dao.upsertExpenseLww(_toCompanion(tombstone));
      await _replicate(roomId, expenseEventType, expensePayload(tombstone));
    });
  }

  /// Deletes a settlement as a tombstone (see [deleteExpense]). Settlements
  /// have no edit — correcting one is delete + re-create.
  Future<void> deleteSettlement(String id, String roomId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(expensesDaoProvider);
      final current = await dao.getSettlementById(id);
      if (current == null) return;
      final tombstone = SettlementModel(
        id: current.id,
        roomId: current.roomId,
        amountCents: current.amountCents,
        currency: current.currency,
        fromUser: current.fromUser,
        toUser: current.toUser,
        createdAt: current.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        deleted: true,
      );
      await dao.upsertSettlementLww(_toSettlementCompanion(tombstone));
      await _replicate(
          roomId, settlementEventType, settlementPayload(tombstone));
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
      // Targets are the claimed participants' Matrix accounts; pure-local
      // participants have no account to send to.
      final targets =
          await ref.read(membersDaoProvider).activeClaimedMatrixIds(groupId);
      if (targets.isEmpty) return;
      final transport = await ref.read(ledgerTransportProvider.future);
      await transport.sendToUsers(targets.toSet(), type, content);
      ref.read(syncHealthProvider.notifier).reportSuccess();
    } catch (e) {
      ref.read(syncHealthProvider.notifier).reportFailure(e);
      debugPrint('[ledger] saved locally; replication deferred: $e');
    }
  }

  static ExpensesCompanion _toCompanion(ExpenseModel e) => ExpensesCompanion(
        id: Value(e.id),
        roomId: Value(e.roomId),
        description: Value(e.description),
        amountCents: Value(e.amountCents),
        currency: Value(e.currency),
        paidBy: Value(e.paidBy),
        splitsJson: Value(e.splitsJson),
        createdAt: Value(e.createdAt),
        updatedAt: Value(e.updatedAt),
        deleted: Value(e.deleted),
      );

  static SettlementsCompanion _toSettlementCompanion(SettlementModel s) =>
      SettlementsCompanion(
        id: Value(s.id),
        roomId: Value(s.roomId),
        amountCents: Value(s.amountCents),
        currency: Value(s.currency),
        fromUser: Value(s.fromUser),
        toUser: Value(s.toUser),
        createdAt: Value(s.createdAt),
        updatedAt: Value(s.updatedAt),
        deleted: Value(s.deleted),
      );
}
