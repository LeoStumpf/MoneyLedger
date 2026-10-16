import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/account_database.dart';
import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/database/daos/signing_dao.dart';
import '../../core/database/daos/sync_states_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../core/session/app_session.dart';
import '../../core/sync/delivery_policy.dart';
import '../../core/sync/ledger_payloads.dart';
import '../../core/sync/record_signing.dart';
import '../../core/sync/sync_health.dart';
import '../../models/expense_category.dart' show normalizeNote;
import '../../models/expense_model.dart';
import '../../models/member_model.dart' show nextLwwClock;

part 'expenses_provider.g.dart';

/// Opens the ledger DB for a signed-in MXID. Injectable so tests can back
/// accounts with temp-file / in-memory databases keyed by name.
final accountDatabaseOpenerProvider =
    Provider<AppDatabase Function(String mxid)>((ref) => openAccountDatabase);

/// Opens local mode's device-local ledger DB ([localDatabaseName], G40).
/// Injectable like [accountDatabaseOpenerProvider]; also used to read the
/// local ledger when it is adopted into an account.
final localDatabaseOpenerProvider = Provider<AppDatabase Function()>(
  (ref) => openLocalDatabase,
);

/// Deletes local mode's ledger files once every instance opened by
/// [localDatabaseOpenerProvider] is closed (G41: after "Delete local data"
/// and after an adoption). Returns whether they were deleted. Injectable
/// with the opener.
final localDatabaseDeleterProvider = Provider<Future<bool> Function()>(
  (ref) => deleteLocalDatabase,
);

/// The **current account's** ledger database (Phase G4: one DB per Matrix
/// account, see `account_database.dart`). Rebuilds when the signed-in account
/// changes: the previous account's DB is closed and every DAO / stream /
/// SyncEngine / LedgerSyncer that watches it rebuilds against the new one.
///
/// While signed out no database is opened: a [SignedOutExecutor] placeholder
/// (reads → no rows, writes → error) keeps the provider non-nullable for the
/// many synchronous consumers; a widget still mounted during the logout
/// transition sees an empty ledger, never another account's data.
///
/// G40: in local mode the device-local ledger ([localDatabaseName]) opens.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final id = ref.watch(ledgerIdentityProvider);
  final db = id == null
      ? AppDatabase.signedOut(SignedOutExecutor())
      : isLocalAccountId(id)
      ? ref.read(localDatabaseOpenerProvider)()
      : ref.read(accountDatabaseOpenerProvider)(id);
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
ExpensesDao expensesDao(Ref ref) => ExpensesDao(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
GroupsDao groupsDao(Ref ref) => GroupsDao(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
MembersDao membersDao(Ref ref) => MembersDao(ref.watch(appDatabaseProvider));

/// G6 device-key history + refused versions of the current account.
@Riverpod(keepAlive: true)
SigningDao signingDao(Ref ref) => SigningDao(ref.watch(appDatabaseProvider));

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

/// Everything one ExpenseAdder write needs, captured **before the first
/// await**: the account DB + DAOs, the transport and the health notifier. The
/// write and its replication therefore always target the account that was
/// active when the user acted, even if the account switches (G4) or the
/// autoDispose notifier is disposed mid-flight — and `ref` is never touched
/// after an await.
class _WriteContext {
  _WriteContext(Ref ref)
    : db = ref.read(appDatabaseProvider),
      expenses = ref.read(expensesDaoProvider),
      members = ref.read(membersDaoProvider),
      health = ref.read(syncHealthProvider.notifier),
      transport = withDeliveryPolicy(
        ref.read(ledgerTransportProvider.future),
        SettingsDao(ref.read(appDatabaseProvider)),
      ) {
    // Only awaited when there are replication targets; don't let an unused
    // transport failure surface as an unhandled async error.
    transport.ignore();
    signer = LocalRecordSigner(transport);
  }

  /// G6: signs every version this write produces with this device's key.
  late final LocalRecordSigner signer;

  final AppDatabase db;
  final ExpensesDao expenses;
  final MembersDao members;
  final SyncHealth health;
  final Future<LedgerTransport> transport;

  /// Best-effort replication to the group's active members via encrypted
  /// to-device. The record is already saved locally, so a transport failure
  /// (offline) must not fail the user action — the homeserver queues
  /// undelivered to-device messages and the SDK retries. Self is included so
  /// the user's other devices stay in sync (the SDK skips the current device).
  /// Skipped silently once [db] is closed (signed out / switched account).
  /// A version still waiting for its signature (G6, `sig` absent) isn't
  /// sent: peers would refuse it; the sync engine signs it and anti-entropy
  /// delivers it.
  Future<void> replicate(
    String groupId,
    String type,
    Map<String, dynamic> content,
  ) async {
    if (db.isClosed || content['sig'] == null) return;
    try {
      // Targets are the claimed participants' Matrix accounts; pure-local
      // participants have no account to send to.
      final targets = await members.activeClaimedMatrixIds(groupId);
      if (targets.isEmpty || db.isClosed) return;
      final t = await transport;
      if (db.isClosed) return;
      final result = await t.sendToUsers(targets.toSet(), type, content);
      if (!db.isClosed) health.reportDelivery(targets.toSet(), result);
    } catch (e) {
      if (db.isClosed) return;
      health.reportFailure(e);
      debugPrint('[ledger] saved locally; replication deferred: $e');
    }
  }
}

@riverpod
class ExpenseAdder extends _$ExpenseAdder {
  @override
  FutureOr<void> build() {}

  /// Runs one write: loading → result, with every dependency captured up
  /// front (see [_WriteContext]). The final state is only set while this
  /// notifier is still mounted (the page may have been popped meanwhile).
  Future<void> _run(Future<void> Function(_WriteContext w) body) async {
    final w = _WriteContext(ref);
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() => body(w));
    if (ref.mounted) state = result;
  }

  Future<void> addExpense({
    required String roomId,
    required String description,
    required int amountCents,
    required String currency,
    required String paidBy,
    required Map<String, int> splits,
    String? category,
    String? note,
  }) => _run((w) async {
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
      category: category,
      note: normalizeNote(note),
    );
    final signed = await w.signer.expense(expense, creating: true);
    if (w.db.isClosed) return;
    // Local-first: persist to Drift immediately so the expense is saved
    // and visible even offline. Replication is best-effort afterwards.
    await w.expenses.upsertExpenseLww(expenseCompanion(signed));
    await w.replicate(roomId, expenseEventType, expensePayload(signed));
  });

  Future<void> addSettlement({
    required String roomId,
    required int amountCents,
    required String currency,
    required String fromUser,
    required String toUser,
  }) => _run((w) async {
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
    final signed = await w.signer.settlement(settlement, creating: true);
    if (w.db.isClosed) return;
    // Local-first: persist before replicating (see addExpense).
    await w.expenses.upsertSettlementLww(settlementCompanion(signed));
    await w.replicate(roomId, settlementEventType, settlementPayload(signed));
  });

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
    String? category,
    String? note,
  }) => _run((w) async {
    // The creator's origin ("added by") is carried over unchanged (G6).
    final current = await w.expenses.getExpenseById(id);
    final expense = ExpenseModel(
      id: id,
      roomId: roomId,
      description: description,
      amountCents: amountCents,
      currency: currency,
      paidBy: paidBy,
      splitsJson: jsonEncode(splits),
      createdAt: createdAt,
      updatedAt: nextLwwClock(current?.updatedAt ?? 0),
      category: category,
      note: normalizeNote(note),
      origin: current?.origin,
    );
    final signed = await w.signer.expense(expense);
    if (w.db.isClosed) return;
    await w.expenses.upsertExpenseLww(expenseCompanion(signed));
    await w.replicate(roomId, expenseEventType, expensePayload(signed));
  });

  /// Deletes an expense as a tombstone: the row is kept (deleted = true, fresh
  /// LWW clock) and replicated, so anti-entropy propagates the deletion and a
  /// stale peer can never resurrect it.
  Future<void> deleteExpense(String id, String roomId) => _run((w) async {
    final current = await w.expenses.getExpenseById(id);
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
      updatedAt: nextLwwClock(current.updatedAt),
      deleted: true,
      category: current.category,
      note: current.note,
      origin: current.origin,
    );
    // A delete is a signed version too ("deleted by").
    final signed = await w.signer.expense(tombstone);
    if (w.db.isClosed) return;
    await w.expenses.upsertExpenseLww(expenseCompanion(signed));
    await w.replicate(roomId, expenseEventType, expensePayload(signed));
  });

  /// Deletes a settlement as a tombstone (see [deleteExpense]). Settlements
  /// have no edit — correcting one is delete + re-create.
  Future<void> deleteSettlement(String id, String roomId) => _run((w) async {
    final current = await w.expenses.getSettlementById(id);
    if (current == null) return;
    final tombstone = SettlementModel(
      id: current.id,
      roomId: current.roomId,
      amountCents: current.amountCents,
      currency: current.currency,
      fromUser: current.fromUser,
      toUser: current.toUser,
      createdAt: current.createdAt,
      updatedAt: nextLwwClock(current.updatedAt),
      deleted: true,
      origin: current.origin,
    );
    final signed = await w.signer.settlement(tombstone);
    if (w.db.isClosed) return;
    await w.expenses.upsertSettlementLww(settlementCompanion(signed));
    await w.replicate(roomId, settlementEventType, settlementPayload(signed));
  });
}
