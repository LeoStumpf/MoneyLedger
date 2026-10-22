import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/account_database.dart';
import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/link_dao.dart';
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
import '../../core/sync/record_validation.dart' show payersProblem;
import '../../core/sync/sync_health.dart';
import '../../models/expense_category.dart' show normalizeNote;
import '../../models/expense_date.dart' show storedExpenseDate;
import '../../models/expense_model.dart';
import '../../models/expense_payers.dart' show payerFields;
import '../../models/member_model.dart' show nextLwwClock;
import '../history/snapshot_store.dart';
import '../receipts/receipt_store.dart' show receiptStoreFactoryProvider;
import 'record_undo.dart' show UndoableWrite;

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
///
/// G48: local mode's on-device snapshots are deleted with it — G78: and
/// its receipt photos (after an adoption they were moved into the account
/// first, `moveReceipts`).
final localDatabaseDeleterProvider = Provider<Future<bool> Function()>((ref) {
  final snapshots = ref.read(snapshotStoreFactoryProvider);
  final receipts = ref.read(receiptStoreFactoryProvider);
  return () => deleteLedgerFilesAndSnapshots(
    deleteLocalDatabase,
    snapshots(localDatabaseName),
    receipts: receipts?.call(localDatabaseName),
  );
});

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

/// G52: device-local link channels / peers of the current ledger DB (and
/// the group policy derived from them, `LinkDao.policyOf`).
final linkDaoProvider = Provider<LinkDao>(
  (ref) => LinkDao(ref.watch(appDatabaseProvider)),
);

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
class LedgerWriteContext {
  LedgerWriteContext(Ref ref)
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
    signer = LocalRecordSigner(transport, policy: LinkDao(db).policyOf);
  }

  /// G6: signs every version this write produces with this device's key —
  /// G52: except in a link-only group, where it is stored unsigned (not
  /// `pendingSign`) with the `by` hint; [replicate] then sends nothing
  /// (no `sig`), so no Matrix relay ever carries a link-only group.
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

/// G60: the record to edit no longer exists (deleted meanwhile, e.g. by a
/// peer) — the edit is not written.
class RecordDeletedException implements Exception {
  const RecordDeletedException();

  @override
  String toString() => 'RecordDeletedException';
}

@riverpod
class ExpenseAdder extends _$ExpenseAdder {
  @override
  FutureOr<void> build() {}

  /// Runs one write: loading → result, with every dependency captured up
  /// front (see [LedgerWriteContext]). The final state is only set while this
  /// notifier is still mounted (the page may have been popped meanwhile).
  ///
  /// G67: returns what the body returned (the [UndoableWrite] of a delete /
  /// a new record), or null when it failed (the error is in [state]).
  Future<T?> _run<T>(Future<T?> Function(LedgerWriteContext w) body) async {
    final w = LedgerWriteContext(ref);
    state = const AsyncLoading();
    T? value;
    final result = await AsyncValue.guard(() async {
      value = await body(w);
    });
    if (ref.mounted) state = result;
    return result.hasError ? null : value;
  }

  /// G76: the payer fields of a write — [paidBy] alone, or (when [payers]
  /// is given) who paid how much: one person left → the single-payer shape,
  /// several → `paid_by` '' + the map. Throws [ArgumentError] when the map
  /// doesn't add up to [amount] (the form never lets that through).
  static ({String paidBy, String? payersJson}) _payers(
    String paidBy,
    Map<String, int>? payers,
    int amount,
  ) {
    if (payers == null) return (paidBy: paidBy, payersJson: null);
    final fields = payerFields(payers);
    final problem = fields == null
        ? 'no payer'
        : fields.payersJson == null
        ? (payers[fields.paidBy] == amount ? null : 'payer amount')
        : payersProblem('', fields.payersJson!, amount);
    if (fields == null || problem != null) {
      throw ArgumentError.value(payers, 'payers', problem);
    }
    return fields;
  }

  /// G67: returns the [UndoableWrite] (undo = delete it again).
  /// G76: [payers] (who paid how much) replaces [paidBy] when given.
  Future<UndoableWrite?> addExpense({
    required String roomId,
    required String description,
    required int amountCents,
    required String currency,
    required String paidBy,
    required Map<String, int> splits,
    Map<String, int>? payers,
    String? category,
    String? note,
    DateTime? day,
  }) => _run((w) async {
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    final who = _payers(paidBy, payers, amountCents);
    final expense = ExpenseModel(
      id: const Uuid().v7(),
      roomId: roomId,
      description: description,
      amountCents: amountCents,
      currency: currency,
      paidBy: who.paidBy,
      payersJson: who.payersJson,
      splitsJson: jsonEncode(splits),
      createdAt: createdAt,
      updatedAt: createdAt,
      category: category,
      note: normalizeNote(note),
      // G49: only a back-dated expense carries a `date` (today → none).
      date: day == null ? null : storedExpenseDate(day, createdAt),
    );
    final signed = await w.signer.expense(expense, creating: true);
    if (w.db.isClosed) return null;
    // Local-first: persist to Drift immediately so the expense is saved
    // and visible even offline. Replication is best-effort afterwards.
    await w.expenses.upsertExpenseLww(expenseCompanion(signed));
    await w.replicate(roomId, expenseEventType, expensePayload(signed));
    return UndoableWrite.expense(writtenExpense: signed);
  });

  /// G67: returns the [UndoableWrite] (undo = delete it again).
  Future<UndoableWrite?> addSettlement({
    required String roomId,
    required int amountCents,
    required String currency,
    required String fromUser,
    required String toUser,
    DateTime? day,
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
      // G60: only a back-dated payment carries a `date` (today → none).
      date: day == null ? null : storedExpenseDate(day, createdAt),
    );
    final signed = await w.signer.settlement(settlement, creating: true);
    if (w.db.isClosed) return null;
    // Local-first: persist before replicating (see addExpense).
    await w.expenses.upsertSettlementLww(settlementCompanion(signed));
    await w.replicate(roomId, settlementEventType, settlementPayload(signed));
    return UndoableWrite.settlement(writtenSettlement: signed);
  });

  /// Edits an existing expense: the full record is re-written with a fresh
  /// LWW clock and replicated whole — concurrent edits of the same expense
  /// converge to the latest writer on every device. [date] (G49): the stored
  /// ISO day (`YYYY-MM-DD`), null = none (the day of [createdAt]).
  Future<UndoableWrite?> updateExpense({
    required String id,
    required String roomId,
    required String description,
    required int amountCents,
    required String currency,
    required String paidBy,
    required Map<String, int> splits,
    Map<String, int>? payers,
    required int createdAt,
    String? category,
    String? note,
    String? date,
  }) => _run((w) async {
    final who = _payers(paidBy, payers, amountCents);
    // The creator's origin ("added by") is carried over unchanged (G6).
    final current = await w.expenses.getExpenseById(id);
    final expense = ExpenseModel(
      id: id,
      roomId: roomId,
      description: description,
      amountCents: amountCents,
      currency: currency,
      paidBy: who.paidBy,
      payersJson: who.payersJson,
      splitsJson: jsonEncode(splits),
      createdAt: createdAt,
      updatedAt: nextLwwClock(current?.updatedAt ?? 0),
      category: category,
      note: normalizeNote(note),
      date: date,
      origin: current?.origin,
    );
    final signed = await w.signer.expense(expense);
    if (w.db.isClosed) return null;
    await w.expenses.upsertExpenseLww(expenseCompanion(signed));
    await w.replicate(roomId, expenseEventType, expensePayload(signed));
    return UndoableWrite.expense(
      writtenExpense: signed,
      beforeExpense: current,
    );
  });

  /// Deletes an expense as a tombstone: the row is kept (deleted = true, fresh
  /// LWW clock) and replicated, so anti-entropy propagates the deletion and a
  /// stale peer can never resurrect it.
  ///
  /// G67: returns the [UndoableWrite] (undo = the content before, as a new
  /// version); null when there was nothing to delete.
  Future<UndoableWrite?> deleteExpense(String id, String roomId) =>
      _run((w) async {
        final current = await w.expenses.getExpenseById(id);
        if (current == null || current.deleted) return null;
        final tombstone = ExpenseModel(
          id: current.id,
          roomId: current.roomId,
          description: current.description,
          amountCents: current.amountCents,
          currency: current.currency,
          paidBy: current.paidBy,
          payersJson: current.payersJson,
          splitsJson: current.splitsJson,
          createdAt: current.createdAt,
          updatedAt: nextLwwClock(current.updatedAt),
          deleted: true,
          category: current.category,
          note: current.note,
          date: current.date,
          origin: current.origin,
        );
        // A delete is a signed version too ("deleted by").
        final signed = await w.signer.expense(tombstone);
        if (w.db.isClosed) return null;
        await w.expenses.upsertExpenseLww(expenseCompanion(signed));
        await w.replicate(roomId, expenseEventType, expensePayload(signed));
        return UndoableWrite.expense(
          writtenExpense: signed,
          beforeExpense: current,
        );
      });

  /// G60: edits an existing payment — like [updateExpense]: the full record
  /// is re-written with `nextLwwClock`, signed by this device as editor (the
  /// creator's `origin` is kept) and replicated whole. [date]: the stored
  /// ISO day, null = the day of `created_at`. Throws
  /// [RecordDeletedException] when the payment is gone / was deleted
  /// meanwhile (an edit must not bring it back).
  Future<UndoableWrite?> updateSettlement({
    required String id,
    required String roomId,
    required int amountCents,
    required String currency,
    required String fromUser,
    required String toUser,
    String? date,
  }) => _run((w) async {
    final current = await w.expenses.getSettlementById(id);
    if (w.db.isClosed) return null;
    if (current == null || current.deleted || current.roomId != roomId) {
      throw const RecordDeletedException();
    }
    final settlement = SettlementModel(
      id: id,
      roomId: roomId,
      amountCents: amountCents,
      currency: currency,
      fromUser: fromUser,
      toUser: toUser,
      createdAt: current.createdAt,
      updatedAt: nextLwwClock(current.updatedAt),
      date: date,
      origin: current.origin,
    );
    final signed = await w.signer.settlement(settlement);
    if (w.db.isClosed) return null;
    await w.expenses.upsertSettlementLww(settlementCompanion(signed));
    await w.replicate(roomId, settlementEventType, settlementPayload(signed));
    return UndoableWrite.settlement(
      writtenSettlement: signed,
      beforeSettlement: current,
    );
  });

  /// Deletes a settlement as a tombstone (see [deleteExpense]). G60: a
  /// payment can also be edited ([updateSettlement]). G67: returns the
  /// [UndoableWrite] like [deleteExpense].
  Future<UndoableWrite?> deleteSettlement(String id, String roomId) => _run((
    w,
  ) async {
    final current = await w.expenses.getSettlementById(id);
    if (current == null || current.deleted) return null;
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
      date: current.date,
      origin: current.origin,
    );
    final signed = await w.signer.settlement(tombstone);
    if (w.db.isClosed) return null;
    await w.expenses.upsertSettlementLww(settlementCompanion(signed));
    await w.replicate(roomId, settlementEventType, settlementPayload(signed));
    return UndoableWrite.settlement(
      writtenSettlement: signed,
      beforeSettlement: current,
    );
  });
}
