import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../app_database.dart';
import '../../sync/ledger_payloads.dart';
import '../../sync/record_signing.dart' show RecordKind;
import '../../sync/record_version.dart';
import '../../../models/expense_model.dart';
import '../../../models/group_model.dart';
import '../../../models/member_model.dart';
import '../../../models/record_signature.dart';
import 'groups_dao.dart'
    show
        decodeCategories,
        decodeExchangeRates,
        decodeFieldClocks,
        linkFromColumns;
import 'members_dao.dart' show decodePayment;

part 'history_dao.g.dart';

/// G48: where a stored record version came from (`record_history.source`).
enum HistorySource {
  /// Written on this device (add / edit / delete, group & member changes).
  local('local'),

  /// Received from a peer (live record, bootstrap, digest gossip).
  inbound('inbound'),

  /// A user-started backup / snapshot restore.
  restore('restore'),

  /// A "reset group to an earlier state" on this device.
  revert('revert'),

  /// A CSV import.
  csvImport('import'),

  /// The record's version when history started (schema v12 migration).
  initial('initial');

  const HistorySource(this.wire);
  final String wire;

  static HistorySource fromWire(String s) => values.firstWhere(
    (v) => v.wire == s,
    orElse: () => HistorySource.inbound,
  );
}

/// G48 retention: history older than this is pruned (one base version per
/// record is kept — see [HistoryDao.prune]).
const kHistoryRetention = Duration(days: 90);

/// G48: soft cap on `record_history` rows per account. Over it, the pruning
/// cutoff moves forward until the rows that are *not* a record's base fit;
/// the base versions (≤ one per record ever seen) are always kept.
const kHistoryMaxRows = 20000;

/// G48: the wall clock history entries are stamped with. Tests replace it.
@visibleForTesting
int Function() historyClock = () => DateTime.now().millisecondsSinceEpoch;

/// One stored version of a record (a `record_history` row).
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.groupId,
    required this.kind,
    required this.recordId,
    required this.updatedAt,
    required this.versionHash,
    required this.content,
    required this.source,
    required this.recordedAt,
  });

  /// Append order (autoincrement) — "newest" always means the highest id.
  final int id;
  final String groupId;
  final RecordKind kind;
  final String recordId;
  final int updatedAt;
  final String versionHash;

  /// The record's wire payload as stored (`expensePayload` & co., `sig` /
  /// `origin` included).
  final Map<String, dynamic> content;
  final HistorySource source;
  final int recordedAt;

  /// The stored version as a model (null for another kind / unreadable).
  ExpenseModel? get expense =>
      kind == RecordKind.expense ? expenseFromPayload(content) : null;
  SettlementModel? get settlement =>
      kind == RecordKind.settlement ? settlementFromPayload(content) : null;
  MemberModel? get member =>
      kind == RecordKind.member ? memberFromPayload(content) : null;
  GroupModel? get meta =>
      kind == RecordKind.meta ? groupMetaFromPayload(content) : null;

  /// Whether this version is a tombstone (members / meta: never).
  bool get deleted => content['deleted'] == true;

  /// The account that signed this version, if any.
  String? get signer => RecordSignature.fromJson(content['sig'])?.user;
}

/// Appends a history entry for a version an LWW upsert just stored — called
/// by the DAOs **inside** their upsert transaction, and only when the stored
/// version changed (new record, or another clock / content hash).
Future<void> appendRecordHistory(
  AppDatabase db, {
  required String groupId,
  required RecordKind kind,
  required String recordId,
  required RecordVersion version,
  required Map<String, dynamic> content,
  required HistorySource source,
}) => db
    .into(db.recordHistory)
    .insert(
      RecordHistoryCompanion.insert(
        groupId: groupId,
        kind: kind.wire,
        recordId: recordId,
        updatedAt: version.at,
        versionHash: version.hash,
        content: jsonEncode(content),
        source: source.wire,
        recordedAt: historyClock(),
      ),
    );

/// G48 (schema v12): one `initial` history entry per stored record — the
/// base the first reset can go back to.
Future<void> backfillRecordHistory(AppDatabase db) async {
  final now = historyClock();
  final groups = await db.select(db.groups).get();
  final members = await db.select(db.members).get();
  final expenses = await db.select(db.expenses).get();
  final settlements = await db.select(db.settlements).get();
  RecordHistoryCompanion entry(
    String group,
    RecordKind kind,
    String id,
    RecordVersion v,
    Map<String, dynamic> content,
  ) => RecordHistoryCompanion.insert(
    groupId: group,
    kind: kind.wire,
    recordId: id,
    updatedAt: v.at,
    versionHash: v.hash,
    content: jsonEncode(content),
    source: HistorySource.initial.wire,
    recordedAt: now,
  );
  await db.batch((b) {
    for (final g in groups) {
      final m = GroupModel(
        roomId: g.roomId,
        name: g.name,
        currency: g.currency,
        updatedAt: g.updatedAt,
        categories: decodeCategories(g.categoriesJson),
        link: linkFromColumns(g.linkEpoch, g.linkSecret),
        lockedAt: g.lockedAt,
        exchangeRates: decodeExchangeRates(g.exchangeRatesJson),
        sig: RecordSignature.decode(g.sig),
        fieldClocks: decodeFieldClocks(g.fieldClocksJson),
      );
      b.insert(
        db.recordHistory,
        entry(
          g.roomId,
          RecordKind.meta,
          g.roomId,
          groupMetaVersion(m),
          groupMetaPayload(m),
        ),
      );
    }
    for (final r in members) {
      final m = MemberModel(
        groupId: r.groupId,
        userId: r.userId,
        displayName: r.displayName,
        matrixId: r.matrixId,
        status: r.status,
        updatedAt: r.updatedAt,
        sig: RecordSignature.decode(r.sig),
        payment: decodePayment(r.paymentJson),
      );
      b.insert(
        db.recordHistory,
        entry(
          r.groupId,
          RecordKind.member,
          r.userId,
          memberVersion(m),
          memberPayload(m),
        ),
      );
    }
    for (final r in expenses) {
      final e = ExpenseModel(
        id: r.id,
        roomId: r.roomId,
        description: r.description,
        amountCents: r.amountCents,
        currency: r.currency,
        paidBy: r.paidBy,
        splitsJson: r.splitsJson,
        payersJson: r.payersJson,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        deleted: r.deleted,
        category: r.category,
        note: r.note,
        date: r.expenseDate,
        sig: RecordSignature.decode(r.sig),
        origin: RecordSignature.decode(r.origin),
      );
      b.insert(
        db.recordHistory,
        entry(r.roomId, RecordKind.expense, r.id, (
          at: e.updatedAt,
          hash: computeExpenseVersionHash(e),
        ), expensePayload(e)),
      );
    }
    for (final r in settlements) {
      final s = SettlementModel(
        id: r.id,
        roomId: r.roomId,
        amountCents: r.amountCents,
        currency: r.currency,
        fromUser: r.fromUser,
        toUser: r.toUser,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        deleted: r.deleted,
        date: r.settlementDate,
        sig: RecordSignature.decode(r.sig),
        origin: RecordSignature.decode(r.origin),
      );
      b.insert(
        db.recordHistory,
        entry(r.roomId, RecordKind.settlement, r.id, (
          at: s.updatedAt,
          hash: computeSettlementVersionHash(s),
        ), settlementPayload(s)),
      );
    }
  });
}

/// G48: reads and prunes the device-local version history.
@DriftAccessor(tables: [RecordHistory, AppSettings])
class HistoryDao extends DatabaseAccessor<AppDatabase> with _$HistoryDaoMixin {
  HistoryDao(super.db);

  static const _floorKey = 'history_floor';

  /// Every history entry of [groupId] in append order (oldest first).
  Future<List<HistoryEntry>> entriesForGroup(String groupId) =>
      (select(recordHistory)
            ..where((t) => t.groupId.equals(groupId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get()
          .then((rows) => [for (final r in rows) ?_toEntry(r)]);

  /// G53 hardening: every entry of [kind] in [groupId], append order (the
  /// participant versions a lock's eligibility is judged by).
  Future<List<HistoryEntry>> entriesForGroupKind(
    String groupId,
    RecordKind kind,
  ) =>
      (select(recordHistory)
            ..where((t) => t.groupId.equals(groupId) & t.kind.equals(kind.wire))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get()
          .then((rows) => [for (final r in rows) ?_toEntry(r)]);

  /// G74: every entry of one record ([kind] + [recordId] in [groupId]),
  /// append order.
  Future<List<HistoryEntry>> entriesForRecord(
    String groupId,
    RecordKind kind,
    String recordId,
  ) =>
      (select(recordHistory)
            ..where(
              (t) =>
                  t.groupId.equals(groupId) &
                  t.kind.equals(kind.wire) &
                  t.recordId.equals(recordId),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get()
          .then((rows) => [for (final r in rows) ?_toEntry(r)]);

  /// [entriesForGroup], reactively (the reset page's change list).
  Stream<List<HistoryEntry>> watchEntriesForGroup(String groupId) =>
      (select(recordHistory)
            ..where((t) => t.groupId.equals(groupId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .watch()
          .map((rows) => [for (final r in rows) ?_toEntry(r)]);

  /// G72: every entry appended after [afterId] (append order) — what a
  /// background round stored.
  Future<List<HistoryEntry>> entriesAfter(int afterId) =>
      (select(recordHistory)
            ..where((t) => t.id.isBiggerThanValue(afterId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get()
          .then((rows) => [for (final r in rows) ?_toEntry(r)]);

  /// G72: the groups with at least one entry up to [upToId] (held before).
  Future<Set<String>> groupsWithEntriesUpTo(int upToId) async {
    final q = selectOnly(recordHistory, distinct: true)
      ..addColumns([recordHistory.groupId])
      ..where(recordHistory.id.isSmallerOrEqualValue(upToId));
    final rows = await q.get();
    return {for (final r in rows) r.read(recordHistory.groupId)!};
  }

  /// G72: which of [recordIds] have an entry up to [upToId], as
  /// `"<kind wire>:<record id>"` keys (the record was held before).
  Future<Set<String>> recordsWithEntriesUpTo(
    int upToId,
    Iterable<String> recordIds,
  ) async {
    final ids = recordIds.toSet().toList();
    final out = <String>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final q = selectOnly(recordHistory, distinct: true)
        ..addColumns([recordHistory.kind, recordHistory.recordId])
        ..where(
          recordHistory.id.isSmallerOrEqualValue(upToId) &
              recordHistory.recordId.isIn(chunk),
        );
      for (final r in await q.get()) {
        out.add(
          '${r.read(recordHistory.kind)}:${r.read(recordHistory.recordId)}',
        );
      }
    }
    return out;
  }

  /// Number of history rows of this account.
  Future<int> rowCount() async {
    final c = recordHistory.id.count();
    final row = await (selectOnly(recordHistory)..addColumns([c])).getSingle();
    return row.read(c) ?? 0;
  }

  /// The earliest moment a reset may go back to: history before it was
  /// pruned (only each record's base version is left). 0 = never pruned.
  Future<int> floor() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.key.equals(_floorKey))).getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  /// [floor], reactively.
  Stream<int> watchFloor() =>
      (select(appSettings)..where((t) => t.key.equals(_floorKey)))
          .watchSingleOrNull()
          .map((row) => int.tryParse(row?.value ?? '') ?? 0);

  /// Retention (G48): drops entries recorded before `now - retention` —
  /// except, per record, the **newest** entry before that cutoff (its base:
  /// the state at the cutoff stays exact, so every reset target at or after
  /// the cutoff is still correct). Over [maxRows], the cutoff moves forward
  /// to the entry that leaves at most [maxRows] newer rows and the same rule
  /// applies. The cutoff becomes the new [floor]. Returns the rows deleted.
  Future<int> prune({
    required int now,
    Duration retention = kHistoryRetention,
    int maxRows = kHistoryMaxRows,
  }) => transaction(() async {
    var cutoff = now - retention.inMilliseconds;
    final total = await rowCount();
    if (total > maxRows) {
      // The recorded_at of the row with exactly maxRows rows after it.
      final row =
          await (select(recordHistory)
                ..orderBy([(t) => OrderingTerm.desc(t.id)])
                ..limit(1, offset: maxRows))
              .getSingleOrNull();
      if (row != null && row.recordedAt + 1 > cutoff) {
        cutoff = row.recordedAt + 1;
      }
    }
    final deleted = await customUpdate(
      'DELETE FROM record_history WHERE recorded_at < ?1 AND id NOT IN '
      '(SELECT MAX(id) FROM record_history WHERE recorded_at < ?1 '
      'GROUP BY group_id, kind, record_id)',
      variables: [Variable.withInt(cutoff)],
      updates: {recordHistory},
      updateKind: UpdateKind.delete,
    );
    if (cutoff > await floor()) {
      await into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(
          key: const Value(_floorKey),
          value: Value('$cutoff'),
        ),
      );
    }
    return deleted;
  });

  /// The newest history id of this account (0 = none) — changes with every
  /// stored version.
  Future<int> latestId() async {
    final c = recordHistory.id.max();
    final row = await (selectOnly(recordHistory)..addColumns([c])).getSingle();
    return row.read(c) ?? 0;
  }

  // ── G48 snapshot bookkeeping (device-local, per account) ────────────────

  static const _snapshotDayKey = 'snapshot_checked_day';
  static const _snapshotFingerprintKey = 'snapshot_fingerprint';

  Future<String?> _get(String key) => (select(
    appSettings,
  )..where((t) => t.key.equals(key))).getSingleOrNull().then((r) => r?.value);

  Future<void> _set(String key, String value) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(key: Value(key), value: Value(value)),
      );

  /// The day (`YYYY-MM-DD`) the daily snapshot check last ran.
  Future<String?> snapshotCheckedDay() => _get(_snapshotDayKey);

  /// The fingerprint of the ledger in the newest snapshot.
  Future<String?> snapshotFingerprint() => _get(_snapshotFingerprintKey);

  /// Records a snapshot check on [day]; [fingerprint] when one was written.
  Future<void> markSnapshotChecked(String day, {String? fingerprint}) =>
      transaction(() async {
        await _set(_snapshotDayKey, day);
        if (fingerprint != null) {
          await _set(_snapshotFingerprintKey, fingerprint);
        }
      });

  static HistoryEntry? _toEntry(HistoryRow r) {
    final kind = RecordKind.fromWire(r.kind);
    if (kind == null) return null;
    Map<String, dynamic> content;
    try {
      content = jsonDecode(r.content) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    return HistoryEntry(
      id: r.id,
      groupId: r.groupId,
      kind: kind,
      recordId: r.recordId,
      updatedAt: r.updatedAt,
      versionHash: r.versionHash,
      content: content,
      source: HistorySource.fromWire(r.source),
      recordedAt: r.recordedAt,
    );
  }
}
