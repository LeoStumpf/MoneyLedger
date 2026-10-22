import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../../models/expense_model.dart';
import '../../../models/record_signature.dart';
import '../../sync/ledger_payloads.dart';
import '../../sync/record_signing.dart' show RecordKind;
import '../../sync/record_version.dart';
import 'history_dao.dart';

part 'expenses_dao.g.dart';

@DriftAccessor(tables: [Expenses, Settlements])
class ExpensesDao extends DatabaseAccessor<AppDatabase>
    with _$ExpensesDaoMixin {
  ExpensesDao(super.db);

  Stream<List<ExpenseModel>> watchExpensesForRoom(String roomId) =>
      (select(expenses)
            ..where((t) => t.roomId.equals(roomId) & t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch()
          .map((rows) => rows.map(_toExpenseModel).toList());

  Stream<List<SettlementModel>> watchSettlementsForRoom(String roomId) =>
      (select(settlements)
            ..where((t) => t.roomId.equals(roomId) & t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch()
          .map((rows) => rows.map(_toSettlementModel).toList());

  /// Last-writer-wins upsert: writes unless the stored row is a **newer
  /// version** — a higher [Expenses.updatedAt], or the same clock with a
  /// higher content hash (G27 tie-break, see `record_version.dart`). The same
  /// version is re-written (idempotent; lets `pendingSign` → signed land at
  /// the same clock). Read + write run in one transaction, so concurrent
  /// inbound versions resolve deterministically. The companion must set
  /// `id` and `updatedAt`. G18 review 2: a row of **another group** with the
  /// same id is left alone (the write is dropped).
  ///
  /// G48: a write that stores a **different** version (new record, other
  /// clock or content hash) is also appended to `record_history` (same
  /// transaction) with [source]; re-writing the same version (e.g. its
  /// signature landing) appends nothing.
  Future<void> upsertExpenseLww(
    ExpensesCompanion expense, {
    HistorySource source = HistorySource.local,
  }) => transaction(() async {
    final old = await (select(
      expenses,
    )..where((t) => t.id.equals(expense.id.value))).getSingleOrNull();
    // G18 review 2 (last guard): an id stored for another group is never
    // moved / overwritten by a version of this group.
    if (old != null &&
        expense.roomId.present &&
        old.roomId != expense.roomId.value) {
      return;
    }
    final incoming = _expenseFromCompanion(expense);
    final hash = computeExpenseVersionHash(incoming);
    final version = (at: incoming.updatedAt, hash: hash);
    final oldVersion = old == null
        ? null
        : expenseVersion(_toExpenseModel(old));
    if (oldVersion != null && compareVersions(version, oldVersion) < 0) {
      return;
    }
    // G37: cache the hash — only when the companion carries the whole
    // content (a partial one keeps stored columns the hash didn't see).
    final complete = _completeExpense(expense);
    await into(expenses).insertOnConflictUpdate(
      expense.copyWith(versionHash: Value(complete ? hash : null)),
    );
    if (oldVersion != null && compareVersions(version, oldVersion) == 0) {
      return;
    }
    // G48: the version as stored (a partial companion merged with the
    // old row → read it back).
    final stored = complete && _signingComplete(expense)
        ? _expenseFromCompanion(expense)
        : _toExpenseModel(
            await (select(
              expenses,
            )..where((t) => t.id.equals(expense.id.value))).getSingle(),
          );
    await appendRecordHistory(
      attachedDatabase,
      groupId: stored.roomId,
      kind: RecordKind.expense,
      recordId: stored.id,
      // A complete companion's content hash is `hash` already.
      version: (
        at: stored.updatedAt,
        hash: complete ? hash : computeExpenseVersionHash(stored),
      ),
      content: expensePayload(stored),
      source: source,
    );
  });

  Future<void> upsertSettlementLww(
    SettlementsCompanion settlement, {
    HistorySource source = HistorySource.local,
  }) => transaction(() async {
    final old = await (select(
      settlements,
    )..where((t) => t.id.equals(settlement.id.value))).getSingleOrNull();
    if (old != null &&
        settlement.roomId.present &&
        old.roomId != settlement.roomId.value) {
      return;
    }
    final incoming = _settlementFromCompanion(settlement);
    final hash = computeSettlementVersionHash(incoming);
    final version = (at: incoming.updatedAt, hash: hash);
    final oldVersion = old == null
        ? null
        : settlementVersion(_toSettlementModel(old));
    if (oldVersion != null && compareVersions(version, oldVersion) < 0) {
      return;
    }
    final complete = _completeSettlement(settlement);
    await into(settlements).insertOnConflictUpdate(
      settlement.copyWith(versionHash: Value(complete ? hash : null)),
    );
    if (oldVersion != null && compareVersions(version, oldVersion) == 0) {
      return;
    }
    final stored = complete && _signingCompleteSettlement(settlement)
        ? _settlementFromCompanion(settlement)
        : _toSettlementModel(
            await (select(
              settlements,
            )..where((t) => t.id.equals(settlement.id.value))).getSingle(),
          );
    await appendRecordHistory(
      attachedDatabase,
      groupId: stored.roomId,
      kind: RecordKind.settlement,
      recordId: stored.id,
      version: (
        at: stored.updatedAt,
        hash: complete ? hash : computeSettlementVersionHash(stored),
      ),
      content: settlementPayload(stored),
      source: source,
    );
  });

  Future<List<ExpenseModel>> getExpensesForRoom(String roomId) =>
      (select(expenses)
            ..where((t) => t.roomId.equals(roomId) & t.deleted.equals(false)))
          .get()
          .then((rows) => rows.map(_toExpenseModel).toList());

  Future<List<SettlementModel>> getSettlementsForRoom(String roomId) =>
      (select(settlements)
            ..where((t) => t.roomId.equals(roomId) & t.deleted.equals(false)))
          .get()
          .then((rows) => rows.map(_toSettlementModel).toList());

  /// Single record incl. tombstones — for edit/delete (the full current row is
  /// needed to build a whole-record LWW payload).
  Future<ExpenseModel?> getExpenseById(String id) =>
      (select(expenses)..where((t) => t.id.equals(id))).getSingleOrNull().then(
        (row) => row == null ? null : _toExpenseModel(row),
      );

  Future<SettlementModel?> getSettlementById(String id) =>
      (select(settlements)..where((t) => t.id.equals(id)))
          .getSingleOrNull()
          .then((row) => row == null ? null : _toSettlementModel(row));

  /// All records including tombstones — for digest/bootstrap building, where
  /// deletions must propagate so peers never resurrect them.
  Future<List<ExpenseModel>> getAllExpensesForGroup(String groupId) =>
      (select(expenses)..where((t) => t.roomId.equals(groupId))).get().then(
        (rows) => rows.map(_toExpenseModel).toList(),
      );

  Future<List<SettlementModel>> getAllSettlementsForGroup(String groupId) =>
      (select(settlements)..where((t) => t.roomId.equals(groupId))).get().then(
        (rows) => rows.map(_toSettlementModel).toList(),
      );

  /// All records including tombstones, reactively — used by the sync-status UI
  /// to track the group's newest `updatedAt` (a delete bumps it too).
  Stream<List<ExpenseModel>> watchAllExpensesForGroup(String groupId) =>
      (select(expenses)..where((t) => t.roomId.equals(groupId))).watch().map(
        (rows) => rows.map(_toExpenseModel).toList(),
      );

  Stream<List<SettlementModel>> watchAllSettlementsForGroup(String groupId) =>
      (select(settlements)..where((t) => t.roomId.equals(groupId))).watch().map(
        (rows) => rows.map(_toSettlementModel).toList(),
      );

  static ExpenseModel _toExpenseModel(Expense e) => ExpenseModel(
    id: e.id,
    roomId: e.roomId,
    matrixEventId: e.matrixEventId,
    description: e.description,
    amountCents: e.amountCents,
    currency: e.currency,
    paidBy: e.paidBy,
    splitsJson: e.splitsJson,
    payersJson: e.payersJson,
    createdAt: e.createdAt,
    updatedAt: e.updatedAt,
    deleted: e.deleted,
    category: e.category,
    note: e.note,
    date: e.expenseDate,
    sig: RecordSignature.decode(e.sig),
    origin: RecordSignature.decode(e.origin),
    pendingSign: e.pendingSign,
    versionHash: e.versionHash,
    linkAuthor: e.linkAuthor,
  );

  static SettlementModel _toSettlementModel(Settlement s) => SettlementModel(
    id: s.id,
    roomId: s.roomId,
    matrixEventId: s.matrixEventId,
    amountCents: s.amountCents,
    currency: s.currency,
    fromUser: s.fromUser,
    toUser: s.toUser,
    createdAt: s.createdAt,
    updatedAt: s.updatedAt,
    deleted: s.deleted,
    date: s.settlementDate,
    sig: RecordSignature.decode(s.sig),
    origin: RecordSignature.decode(s.origin),
    pendingSign: s.pendingSign,
    versionHash: s.versionHash,
    linkAuthor: s.linkAuthor,
  );
}

/// A fully-populated companion for an LWW upsert of [e] (G6 fields included).
ExpensesCompanion expenseCompanion(ExpenseModel e) => ExpensesCompanion(
  id: Value(e.id),
  roomId: Value(e.roomId),
  description: Value(e.description),
  amountCents: Value(e.amountCents),
  currency: Value(e.currency),
  paidBy: Value(e.paidBy),
  splitsJson: Value(e.splitsJson),
  payersJson: Value(e.payersJson),
  createdAt: Value(e.createdAt),
  updatedAt: Value(e.updatedAt),
  deleted: Value(e.deleted),
  category: Value(e.category),
  note: Value(e.note),
  expenseDate: Value(e.date),
  sig: Value(e.sig?.encode()),
  origin: Value(e.origin?.encode()),
  pendingSign: Value(e.pendingSign),
  // G52: always set (also to null) — an absent value would keep the
  // previous version's hint on update.
  linkAuthor: Value(e.linkAuthor),
);

/// A fully-populated companion for an LWW upsert of [s] (G6 fields included).
SettlementsCompanion settlementCompanion(SettlementModel s) =>
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
      settlementDate: Value(s.date),
      sig: Value(s.sig?.encode()),
      origin: Value(s.origin?.encode()),
      pendingSign: Value(s.pendingSign),
      linkAuthor: Value(s.linkAuthor), // G52: always set (see above)
    );

T _v<T>(Value<T> v, T fallback) => v.present ? v.value : fallback;

/// The content fields of a (possibly partial) companion as a model — only
/// what the G27 version hash covers.
ExpenseModel _expenseFromCompanion(ExpensesCompanion c) => ExpenseModel(
  id: c.id.value,
  roomId: _v(c.roomId, ''),
  description: _v(c.description, ''),
  amountCents: _v(c.amountCents, 0),
  currency: _v(c.currency, 'EUR'),
  paidBy: _v(c.paidBy, ''),
  splitsJson: _v(c.splitsJson, '{}'),
  payersJson: _v(c.payersJson, null),
  createdAt: _v(c.createdAt, 0),
  updatedAt: c.updatedAt.value,
  deleted: _v(c.deleted, false),
  category: _v(c.category, null),
  note: _v(c.note, null),
  date: _v(c.expenseDate, null),
  sig: RecordSignature.decode(_v(c.sig, null)),
  origin: RecordSignature.decode(_v(c.origin, null)),
  pendingSign: _v(c.pendingSign, false),
  // G72: not hashed, but part of the stored version (history `by`).
  linkAuthor: _v(c.linkAuthor, null),
);

SettlementModel _settlementFromCompanion(SettlementsCompanion c) =>
    SettlementModel(
      id: c.id.value,
      roomId: _v(c.roomId, ''),
      amountCents: _v(c.amountCents, 0),
      currency: _v(c.currency, 'EUR'),
      fromUser: _v(c.fromUser, ''),
      toUser: _v(c.toUser, ''),
      createdAt: _v(c.createdAt, 0),
      updatedAt: c.updatedAt.value,
      deleted: _v(c.deleted, false),
      date: _v(c.settlementDate, null),
      sig: RecordSignature.decode(_v(c.sig, null)),
      origin: RecordSignature.decode(_v(c.origin, null)),
      pendingSign: _v(c.pendingSign, false),
      linkAuthor: _v(c.linkAuthor, null),
    );

/// G48: whether [c] sets every signing column (with [_completeExpense] the
/// companion then *is* the stored row). G72: and the link author — else
/// the history entry lost a kept `by`.
bool _signingComplete(ExpensesCompanion c) =>
    c.sig.present &&
    c.origin.present &&
    c.pendingSign.present &&
    c.linkAuthor.present;

bool _signingCompleteSettlement(SettlementsCompanion c) =>
    c.sig.present &&
    c.origin.present &&
    c.pendingSign.present &&
    c.linkAuthor.present;

/// G37: whether [c] sets every column the expense content hash covers.
bool _completeExpense(ExpensesCompanion c) =>
    c.roomId.present &&
    c.description.present &&
    c.amountCents.present &&
    c.currency.present &&
    c.paidBy.present &&
    c.splitsJson.present &&
    c.payersJson.present &&
    c.createdAt.present &&
    c.deleted.present &&
    c.category.present &&
    c.note.present &&
    c.expenseDate.present;

bool _completeSettlement(SettlementsCompanion c) =>
    c.roomId.present &&
    c.amountCents.present &&
    c.currency.present &&
    c.fromUser.present &&
    c.toUser.present &&
    c.createdAt.present &&
    c.deleted.present &&
    c.settlementDate.present;

/// G37 (schema v8): stores the content hash of every expense / settlement
/// that has none yet (rows from before v8, or written outside the DAO).
Future<void> backfillVersionHashes(AppDatabase db) async {
  final ex = await (db.select(
    db.expenses,
  )..where((t) => t.versionHash.isNull())).get();
  final st = await (db.select(
    db.settlements,
  )..where((t) => t.versionHash.isNull())).get();
  if (ex.isEmpty && st.isEmpty) return;
  await db.batch((b) {
    for (final e in ex) {
      b.update(
        db.expenses,
        ExpensesCompanion(
          versionHash: Value(
            computeExpenseVersionHash(ExpensesDao._toExpenseModel(e)),
          ),
        ),
        where: (t) => t.id.equals(e.id),
      );
    }
    for (final s in st) {
      b.update(
        db.settlements,
        SettlementsCompanion(
          versionHash: Value(
            computeSettlementVersionHash(ExpensesDao._toSettlementModel(s)),
          ),
        ),
        where: (t) => t.id.equals(s.id),
      );
    }
  });
}
