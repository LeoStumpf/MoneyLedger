import '../../core/database/daos/history_dao.dart';
import '../../core/sync/ledger_payloads.dart';
import '../../core/sync/record_signing.dart' show RecordKind;
import '../../core/sync/record_validation.dart';
import '../../core/sync/record_version.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart' show nextLwwClock;

/// G48 — "Reset group to an earlier state", the pure part (plain Dart, no
/// DB / Flutter): history entries → change batches (the points a user can go
/// back to) and a reset plan (the new versions that bring the group back).
///
/// **State at a point** = per record the newest history entry (highest id)
/// appended **before** that point on *this* device — "how it looked on my
/// device then". A point is always the start of a change batch: going back
/// "to before these changes" (`beforeId` = the batch's first entry id).
///
/// **What a reset touches:** expenses, payments and the group meta (name,
/// currency, custom categories). **Participants are never reset**: a
/// membership change has rules a revert could break (removing ourselves,
/// re-adding someone who was removed — a removal must stick, G26 — or moving
/// a Matrix claim). Participants are never deleted, only marked removed, so
/// every participant an old expense names still exists.

/// Entries further apart than this start a new change batch.
const kChangeBatchGap = Duration(minutes: 10);

/// G62: how far apart the entries of the group's **arrival** on this device
/// (a bootstrap — possibly in chunked parts, each verified first —, a
/// restore, a CSV import) may be to still count as that arrival.
const kBaseArrivalGap = Duration(seconds: 30);

/// G62: the same for a group that arrived by a **local** write — created
/// here (meta + creator) or adopted from local mode (one transaction): those
/// are stored within milliseconds, and the user's first expense in a new
/// group must not count as part of its creation.
const kLocalArrivalGap = Duration(seconds: 2);

/// One burst of changes (consecutive history entries less than
/// [kChangeBatchGap] apart, by the same author), summarised per record.
class ChangeBatch {
  const ChangeBatch({
    required this.firstId,
    required this.lastId,
    required this.startAt,
    required this.endAt,
    required this.added,
    required this.changed,
    required this.deleted,
    required this.otherChanges,
    required this.editors,
    required this.byMe,
    required this.resettable,
    this.base = false,
  });

  /// First / last history id in the batch (append order).
  final int firstId;
  final int lastId;

  /// When this device stored the first / last version of the batch.
  final int startAt;
  final int endAt;

  /// Expenses + payments that appeared, changed or were deleted (per record:
  /// its state before the batch vs. after it).
  final int added;
  final int changed;
  final int deleted;

  /// Participant / group-settings versions in the batch.
  final int otherChanges;

  /// Accounts that signed versions in the batch (from peers).
  final Set<String> editors;

  /// Some version was written on this device (unsigned local writes count).
  final bool byMe;

  /// The state before the batch is known: the group existed on this device
  /// (its meta has an earlier entry) and the batch starts at or after the
  /// pruning floor (older history keeps only each record's base version).
  final bool resettable;

  /// G62: the group's arrival on this device (see [changeBatches]) — the
  /// earliest state, never a reset target itself.
  final bool base;

  int get total => added + changed + deleted + otherChanges;
}

/// The change batches of one group's [entries] (any order), **newest
/// first**. [floor]: `HistoryDao.floor` — batches starting before it are
/// marked not resettable. [me]: this device's account (its signed versions
/// count as [ChangeBatch.byMe]).
///
/// G62 — batch boundaries:
/// - **The base batch** is the group's arrival on this device: every entry
///   up to the group meta's first one, plus the entries that came with it —
///   the same source, each at most [kBaseArrivalGap] ([kLocalArrivalGap]
///   for a local write) after the previous, no record twice (a second
///   version is an edit). The schema-v12 `initial` backfill is always base.
///   It is never
///   resettable (nothing came before it) but makes every later batch so —
///   before G62 the arrival chained with every change < 10 min later, and
///   the page had nothing to offer after an update or for a new group.
/// - **After it**, a new batch starts after a pause longer than [gap] or
///   when the **author** changes (this device / our own account, a peer's
///   account, a restore, a CSV import): "undo Bob's changes" never also
///   undoes ours from a few minutes earlier.
List<ChangeBatch> changeBatches(
  List<HistoryEntry> entries, {
  int floor = 0,
  String? me,
  Duration gap = kChangeBatchGap,
}) {
  final sorted = [...entries]..sort((a, b) => a.id.compareTo(b.id));
  final out = <ChangeBatch>[];
  // The latest entry per record seen so far (before the current batch).
  final latest = <String, HistoryEntry>{};
  var metaSeen = false;
  final baseEnd = _baseEnd(sorted);
  var i = 0;
  while (i < sorted.length) {
    final isBase = i < baseEnd;
    var j = i + 1;
    if (isBase) {
      j = baseEnd;
    } else {
      final author = _author(sorted[i], me);
      while (j < sorted.length &&
          sorted[j].recordedAt - sorted[j - 1].recordedAt <=
              gap.inMilliseconds &&
          _author(sorted[j], me) == author) {
        j++;
      }
    }
    final batch = sorted.sublist(i, j);
    final resettable = !isBase && metaSeen && batch.first.recordedAt >= floor;
    // Per record: before (latest so far) vs. after (last in the batch).
    final after = <String, HistoryEntry>{};
    var other = 0;
    final editors = <String>{};
    var byMe = false;
    for (final e in batch) {
      if (e.kind == RecordKind.member || e.kind == RecordKind.meta) {
        other++;
      } else {
        after[_key(e)] = e;
      }
      final signer = e.signer;
      if (e.source == HistorySource.local ||
          e.source == HistorySource.revert ||
          (me != null && signer == me)) {
        byMe = true;
      } else if (signer != null) {
        editors.add(signer);
      }
    }
    var added = 0, changed = 0, deleted = 0;
    for (final MapEntry(:key, value: now) in after.entries) {
      final before = latest[key];
      final wasLive = before != null && !before.deleted;
      if (!wasLive && !now.deleted) {
        added++;
      } else if (wasLive && now.deleted) {
        deleted++;
      } else if (wasLive && !now.deleted) {
        changed++;
      }
    }
    out.add(
      ChangeBatch(
        firstId: batch.first.id,
        lastId: batch.last.id,
        startAt: batch.first.recordedAt,
        endAt: batch.last.recordedAt,
        added: added,
        changed: changed,
        deleted: deleted,
        otherChanges: other,
        editors: editors,
        byMe: byMe,
        resettable: resettable,
        base: isBase,
      ),
    );
    for (final e in batch) {
      latest[_key(e)] = e;
      if (e.kind == RecordKind.meta) metaSeen = true;
    }
    i = j;
  }
  return out.reversed.toList();
}

/// G62: the end (exclusive index into [sorted]) of the base batch — the
/// group's arrival on this device; 0 when the meta never appears (then no
/// batch is resettable, as before).
int _baseEnd(List<HistoryEntry> sorted) {
  final m = sorted.indexWhere((e) => e.kind == RecordKind.meta);
  if (m < 0) return 0;
  final source = sorted[m].source;
  final maxGap =
      (source == HistorySource.local ? kLocalArrivalGap : kBaseArrivalGap)
          .inMilliseconds;
  final seen = {for (final e in sorted.sublist(0, m + 1)) _key(e)};
  var end = m + 1;
  while (end < sorted.length) {
    final e = sorted[end];
    final initial = e.source == HistorySource.initial;
    if (!initial) {
      if (e.source != source) break;
      if (e.recordedAt - sorted[end - 1].recordedAt > maxGap) break;
      if (seen.contains(_key(e))) break;
    }
    seen.add(_key(e));
    end++;
  }
  return end;
}

/// G62: who a history entry's change came from, for batch boundaries — this
/// device or our own account (`me`), a peer's account, or the source of an
/// unsigned / bulk write (restore, CSV import, initial backfill).
String _author(HistoryEntry e, String? me) => switch (e.source) {
  HistorySource.local || HistorySource.revert => 'me',
  HistorySource.inbound => switch (e.signer) {
    null => 'inbound',
    final s when s == me => 'me',
    final s => 'user:$s',
  },
  _ => 'source:${e.source.wire}',
};

String _key(HistoryEntry e) => '${e.kind.wire}|${e.recordId}';

/// What a reset does to one record.
enum ResetEffect {
  /// Deleted now, existed then → comes back.
  restored,

  /// Exists now with other content → the earlier content is written again.
  reverted,

  /// Exists now, didn't exist (or was deleted) then → deleted.
  removed,
}

/// One new version a reset writes (unsigned; the clock is already the next
/// LWW clock after the stored version, the creator's `origin` is kept).
class ResetChange {
  const ResetChange.expense(this.effect, ExpenseModel this.expense)
    : settlement = null;
  const ResetChange.settlement(this.effect, SettlementModel this.settlement)
    : expense = null;

  final ResetEffect effect;
  final ExpenseModel? expense;
  final SettlementModel? settlement;

  RecordKind get kind =>
      expense != null ? RecordKind.expense : RecordKind.settlement;
}

/// Everything a reset of one group to the state before history entry
/// [beforeId] (or, G58, to a snapshot's state) would write.
class GroupResetPlan {
  const GroupResetPlan({
    required this.groupId,
    required this.beforeId,
    required this.changes,
    this.meta,
    this.skipped = 0,
    this.arriving = 0,
  });

  final String groupId;

  /// The history point of a G48 reset (0 for a G58 snapshot target).
  final int beforeId;
  final List<ResetChange> changes;

  /// The earlier group meta (name / currency / categories), when it differs.
  final GroupModel? meta;

  /// Earlier versions that break today's content rules — left as they are.
  /// G58: also target versions this device never held ([ResetTarget.held]).
  final int skipped;

  /// G58: live records of the target this device doesn't store at all — the
  /// restore's LWW merge brings them back (verified like any restore), not
  /// this plan; counted in the preview's "come back".
  final int arriving;

  int _count(ResetEffect e) => changes.where((c) => c.effect == e).length;
  int get restored => _count(ResetEffect.restored);
  int get reverted => _count(ResetEffect.reverted);
  int get removed => _count(ResetEffect.removed);
  bool get isEmpty => changes.isEmpty && meta == null;
}

/// G58: the state a reset brings a group back to — per record the target
/// version (a tombstone = deleted then; **absent = didn't exist then**).
/// Built from the version history ([historyResetTarget], G48) or from a
/// snapshot / backup group payload ([snapshotResetTarget]).
class ResetTarget {
  const ResetTarget({
    required this.expenses,
    required this.settlements,
    this.meta,
    this.knows,
    this.held,
  });

  /// Expense / payment id → its target version.
  final Map<String, ExpenseModel> expenses;
  final Map<String, SettlementModel> settlements;

  /// The target group meta; null → the meta is left as it is.
  final GroupModel? meta;

  /// Whether the target says anything about a record at all; one it doesn't
  /// know is left alone ("didn't exist then" can't be concluded). Null =
  /// knows every record.
  final bool Function(RecordKind kind, String id)? knows;

  /// `<kind>|<id>|<version hash>` of every version this device has stored
  /// (its history). When set, a target **content** that isn't in it is not
  /// written (counted as skipped): a reset only ever brings back content
  /// this device itself held — a hand-edited snapshot file can't make it
  /// sign something new. Tombstones need no check (they keep today's
  /// content). Null = every target version is usable (history targets).
  final Set<String>? held;

  bool _knows(RecordKind kind, String id) => knows?.call(kind, id) ?? true;

  bool _usable(RecordKind kind, String id, String hash) =>
      held?.contains('${kind.wire}|$id|$hash') ?? true;
}

/// G48: the state of group [groupId] before history entry [beforeId] — per
/// record the newest entry appended before it. Records the history never
/// saw at all (written outside the DAOs, e.g. adopted from the pre-G4
/// legacy ledger) are unknown: their past is unknown, so "didn't exist
/// then" can't be concluded.
ResetTarget historyResetTarget({
  required String groupId,
  required int beforeId,
  required List<HistoryEntry> entries,
}) {
  final latest = <String, HistoryEntry>{};
  final known = <String>{};
  for (final e in entries) {
    if (e.groupId != groupId) continue;
    final k = _key(e);
    known.add(k);
    if (e.id >= beforeId) continue;
    final have = latest[k];
    if (have == null || e.id > have.id) latest[k] = e;
  }
  final expenses = <String, ExpenseModel>{};
  final settlements = <String, SettlementModel>{};
  GroupModel? meta;
  for (final e in latest.values) {
    switch (e.kind) {
      case RecordKind.expense:
        if (e.expense case final x?) expenses[e.recordId] = x;
      case RecordKind.settlement:
        if (e.settlement case final x?) settlements[e.recordId] = x;
      case RecordKind.meta:
        meta = e.meta;
      case RecordKind.member:
        break;
    }
  }
  return ResetTarget(
    expenses: expenses,
    settlements: settlements,
    meta: meta,
    knows: (kind, id) => known.contains('${kind.wire}|$id'),
  );
}

/// G58: the state of a backed-up / snapshotted [group] (a bootstrap-shaped
/// payload: `meta`, `expenses`, `settlements`, tombstones included) as a
/// reset target — "exactly this state": a record the snapshot doesn't list
/// didn't exist then. [history]: this device's version history of the group
/// ([ResetTarget.held] — only content this device stored is written again).
/// A record entry that doesn't parse is unknown (left alone); a missing or
/// unreadable `meta` leaves the meta alone.
ResetTarget snapshotResetTarget(
  Map<String, dynamic> group, {
  required List<HistoryEntry> history,
}) {
  final gid = group['group'] as String;
  final unknown = <String>{};
  Iterable<Map<String, dynamic>> section(String name) sync* {
    for (final r in group[name] as List? ?? const []) {
      if (r is Map) yield Map<String, dynamic>.from(r);
    }
  }

  final expenses = <String, ExpenseModel>{};
  for (final r in section('expenses')) {
    final e = expenseFromPayload(r);
    if (e == null || e.roomId != gid) {
      if (r['id'] is String) {
        unknown.add('${RecordKind.expense.wire}|${r['id']}');
      }
      continue;
    }
    expenses[e.id] = e;
  }
  final settlements = <String, SettlementModel>{};
  for (final r in section('settlements')) {
    final s = settlementFromPayload(r);
    if (s == null || s.roomId != gid) {
      if (r['id'] is String) {
        unknown.add('${RecordKind.settlement.wire}|${r['id']}');
      }
      continue;
    }
    settlements[s.id] = s;
  }
  final rawMeta = group['meta'];
  final meta = rawMeta is Map
      ? groupMetaFromPayload(Map<String, dynamic>.from(rawMeta))
      : null;
  return ResetTarget(
    expenses: expenses,
    settlements: settlements,
    meta: meta != null && meta.roomId == gid ? meta : null,
    knows: (kind, id) => !unknown.contains('${kind.wire}|$id'),
    held: {
      for (final h in history)
        if (h.groupId == gid) '${h.kind.wire}|${h.recordId}|${h.versionHash}',
    },
  );
}

/// Plans resetting group [groupId] to its state before history entry
/// [beforeId] (see the library doc) — [planGroupResetTo] with
/// [historyResetTarget]. [expenses] / [settlements]: every stored record of
/// the group **incl. tombstones**; [meta]: the stored group meta. Records the
/// history only knows from [beforeId] on (created later) are deleted;
/// records it doesn't know at all are left alone; the meta is only reset
/// when the history has an earlier version. [now] stamps the new clocks
/// (`nextLwwClock`).
GroupResetPlan planGroupReset({
  required String groupId,
  required int beforeId,
  required List<HistoryEntry> entries,
  required List<ExpenseModel> expenses,
  required List<SettlementModel> settlements,
  required GroupModel? meta,
  int? now,
}) => planGroupResetTo(
  groupId: groupId,
  beforeId: beforeId,
  target: historyResetTarget(
    groupId: groupId,
    beforeId: beforeId,
    entries: entries,
  ),
  expenses: expenses,
  settlements: settlements,
  meta: meta,
  now: now,
);

/// The one reset planner (G48 history reset, G58 "exactly this state"
/// snapshot restore): the new versions that make group [groupId]'s stored
/// [expenses] / [settlements] (incl. tombstones) and [meta] equal to
/// [target]. Per record the target knows: live now, absent or a tombstone
/// in the target → *removed* (a tombstone of today's content); deleted now,
/// live in the target → *restored*; other content → *reverted*. A target
/// version breaking today's content rules (or not [ResetTarget.held]) is
/// skipped. Participants are never touched.
GroupResetPlan planGroupResetTo({
  required String groupId,
  required ResetTarget target,
  required List<ExpenseModel> expenses,
  required List<SettlementModel> settlements,
  required GroupModel? meta,
  int beforeId = 0,
  int? now,
}) {
  final changes = <ResetChange>[];
  var skipped = 0;
  final storedExpenses = <String>{};
  final storedSettlements = <String>{};

  for (final cur in expenses) {
    if (cur.roomId != groupId) continue;
    storedExpenses.add(cur.id);
    if (!target._knows(RecordKind.expense, cur.id)) continue;
    final old = target.expenses[cur.id];
    final clock = nextLwwClock(cur.updatedAt, now: now);
    if (old == null || old.deleted) {
      if (cur.deleted) continue;
      changes.add(
        ResetChange.expense(
          ResetEffect.removed,
          resetExpenseVersion(cur, clock, deleted: true, origin: cur),
        ),
      );
      continue;
    }
    final effect = cur.deleted
        ? ResetEffect.restored
        : _sameExpense(old, cur)
        ? null
        : ResetEffect.reverted;
    if (effect == null) continue;
    final next = resetExpenseVersion(old, clock, deleted: false, origin: cur);
    if (!target._usable(
          RecordKind.expense,
          cur.id,
          computeExpenseVersionHash(old),
        ) ||
        expenseProblem(next) != null) {
      skipped++;
      continue;
    }
    changes.add(ResetChange.expense(effect, next));
  }

  for (final cur in settlements) {
    if (cur.roomId != groupId) continue;
    storedSettlements.add(cur.id);
    if (!target._knows(RecordKind.settlement, cur.id)) continue;
    final old = target.settlements[cur.id];
    final clock = nextLwwClock(cur.updatedAt, now: now);
    if (old == null || old.deleted) {
      if (cur.deleted) continue;
      changes.add(
        ResetChange.settlement(
          ResetEffect.removed,
          resetSettlementVersion(cur, clock, deleted: true, origin: cur),
        ),
      );
      continue;
    }
    final effect = cur.deleted
        ? ResetEffect.restored
        : _sameSettlement(old, cur)
        ? null
        : ResetEffect.reverted;
    if (effect == null) continue;
    final next = resetSettlementVersion(
      old,
      clock,
      deleted: false,
      origin: cur,
    );
    if (!target._usable(
          RecordKind.settlement,
          cur.id,
          computeSettlementVersionHash(old),
        ) ||
        settlementProblem(next) != null) {
      skipped++;
      continue;
    }
    changes.add(ResetChange.settlement(effect, next));
  }

  GroupModel? metaChange;
  final oldMeta = target.meta;
  if (meta != null && oldMeta != null && !_sameMeta(oldMeta, meta)) {
    // G53: a reset never changes the link state — the current meta's open
    // link / lock is kept (only name, currency and categories go back).
    final next = meta.nextVersion(
      updatedAt: nextLwwClock(meta.updatedAt, now: now),
      name: oldMeta.name,
      currency: oldMeta.currency,
      categories: oldMeta.categories,
    );
    if (target._usable(
          RecordKind.meta,
          groupId,
          groupMetaVersionHash(oldMeta),
        ) &&
        groupMetaProblem(next) == null) {
      metaChange = next;
    } else {
      skipped++;
    }
  }

  final arriving =
      target.expenses.values
          .where((e) => !e.deleted && !storedExpenses.contains(e.id))
          .length +
      target.settlements.values
          .where((s) => !s.deleted && !storedSettlements.contains(s.id))
          .length;

  // Newest first in the preview (by creation time).
  int createdOf(ResetChange c) =>
      c.expense?.createdAt ?? c.settlement!.createdAt;
  changes.sort((a, b) => createdOf(b).compareTo(createdOf(a)));
  return GroupResetPlan(
    groupId: groupId,
    beforeId: beforeId,
    changes: changes,
    meta: metaChange,
    skipped: skipped,
    arriving: arriving,
  );
}

/// [content]'s fields as a new unsigned version at [clock]; the creator's
/// `origin` comes from [origin] (the stored record — origin never changes),
/// falling back to [content]'s.
ExpenseModel resetExpenseVersion(
  ExpenseModel content,
  int clock, {
  required bool deleted,
  required ExpenseModel origin,
}) => ExpenseModel(
  id: origin.id,
  roomId: origin.roomId,
  description: content.description,
  amountCents: content.amountCents,
  currency: content.currency,
  paidBy: content.paidBy,
  splitsJson: content.splitsJson,
  createdAt: origin.createdAt,
  updatedAt: clock,
  deleted: deleted,
  category: content.category,
  note: content.note,
  date: content.date,
  origin: origin.origin ?? content.origin,
);

SettlementModel resetSettlementVersion(
  SettlementModel content,
  int clock, {
  required bool deleted,
  required SettlementModel origin,
}) => SettlementModel(
  id: origin.id,
  roomId: origin.roomId,
  amountCents: content.amountCents,
  currency: content.currency,
  fromUser: content.fromUser,
  toUser: content.toUser,
  createdAt: origin.createdAt,
  updatedAt: clock,
  deleted: deleted,
  date: content.date,
  origin: origin.origin ?? content.origin,
);

/// Same content (the G27 hash with the clock and tombstone flag ignored).
bool _sameExpense(ExpenseModel a, ExpenseModel b) =>
    computeExpenseVersionHash(
      resetExpenseVersion(a, 0, deleted: false, origin: a),
    ) ==
    computeExpenseVersionHash(
      resetExpenseVersion(b, 0, deleted: false, origin: a),
    );

bool _sameSettlement(SettlementModel a, SettlementModel b) =>
    computeSettlementVersionHash(
      resetSettlementVersion(a, 0, deleted: false, origin: a),
    ) ==
    computeSettlementVersionHash(
      resetSettlementVersion(b, 0, deleted: false, origin: a),
    );

bool _sameMeta(GroupModel a, GroupModel b) =>
    groupMetaVersionHash(
      GroupModel(
        roomId: b.roomId,
        name: a.name,
        currency: a.currency,
        categories: a.categories,
      ),
    ) ==
    groupMetaVersionHash(
      GroupModel(
        roomId: b.roomId,
        name: b.name,
        currency: b.currency,
        categories: b.categories,
      ),
    );
