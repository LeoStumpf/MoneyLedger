import '../../core/database/daos/history_dao.dart';
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

/// One burst of changes (consecutive history entries less than
/// [kChangeBatchGap] apart), summarised per record.
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

  int get total => added + changed + deleted + otherChanges;
}

/// The change batches of one group's [entries] (any order), **newest
/// first**. [floor]: `HistoryDao.floor` — batches starting before it are
/// marked not resettable. [me]: this device's account (its signed versions
/// count as [ChangeBatch.byMe]).
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
  var i = 0;
  while (i < sorted.length) {
    var j = i + 1;
    while (j < sorted.length &&
        sorted[j].recordedAt - sorted[j - 1].recordedAt <= gap.inMilliseconds) {
      j++;
    }
    final batch = sorted.sublist(i, j);
    final resettable = metaSeen && batch.first.recordedAt >= floor;
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
/// [beforeId] would write.
class GroupResetPlan {
  const GroupResetPlan({
    required this.groupId,
    required this.beforeId,
    required this.changes,
    this.meta,
    this.skipped = 0,
  });

  final String groupId;
  final int beforeId;
  final List<ResetChange> changes;

  /// The earlier group meta (name / currency / categories), when it differs.
  final GroupModel? meta;

  /// Earlier versions that break today's content rules — left as they are.
  final int skipped;

  int _count(ResetEffect e) => changes.where((c) => c.effect == e).length;
  int get restored => _count(ResetEffect.restored);
  int get reverted => _count(ResetEffect.reverted);
  int get removed => _count(ResetEffect.removed);
  bool get isEmpty => changes.isEmpty && meta == null;
}

/// Plans resetting group [groupId] to its state before history entry
/// [beforeId] (see the library doc). [expenses] / [settlements]: every
/// stored record of the group **incl. tombstones**; [meta]: the stored group
/// meta. Records the history only knows from [beforeId] on (created later)
/// are deleted; records it doesn't know at all are left alone; the meta is
/// only reset when the history has an earlier version. [now] stamps the new clocks (`nextLwwClock`).
GroupResetPlan planGroupReset({
  required String groupId,
  required int beforeId,
  required List<HistoryEntry> entries,
  required List<ExpenseModel> expenses,
  required List<SettlementModel> settlements,
  required GroupModel? meta,
  int? now,
}) {
  final target = <String, HistoryEntry>{};
  // Records the history knows at all. One it never saw (written outside the
  // DAOs, e.g. adopted from the pre-G4 legacy ledger) is left alone — its
  // past is unknown, so "didn't exist then" can't be concluded.
  final known = <String>{};
  for (final e in entries) {
    if (e.groupId != groupId) continue;
    known.add(_key(e));
    if (e.id >= beforeId) continue;
    final k = _key(e);
    final have = target[k];
    if (have == null || e.id > have.id) target[k] = e;
  }
  final changes = <ResetChange>[];
  var skipped = 0;

  for (final cur in expenses) {
    if (cur.roomId != groupId) continue;
    if (!known.contains('${RecordKind.expense.wire}|${cur.id}')) continue;
    final then = target['${RecordKind.expense.wire}|${cur.id}'];
    final old = then?.expense;
    final clock = nextLwwClock(cur.updatedAt, now: now);
    if (old == null || old.deleted) {
      if (cur.deleted) continue;
      changes.add(
        ResetChange.expense(
          ResetEffect.removed,
          _expense(cur, clock, deleted: true, origin: cur),
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
    final next = _expense(old, clock, deleted: false, origin: cur);
    if (expenseProblem(next) != null) {
      skipped++;
      continue;
    }
    changes.add(ResetChange.expense(effect, next));
  }

  for (final cur in settlements) {
    if (cur.roomId != groupId) continue;
    if (!known.contains('${RecordKind.settlement.wire}|${cur.id}')) continue;
    final then = target['${RecordKind.settlement.wire}|${cur.id}'];
    final old = then?.settlement;
    final clock = nextLwwClock(cur.updatedAt, now: now);
    if (old == null || old.deleted) {
      if (cur.deleted) continue;
      changes.add(
        ResetChange.settlement(
          ResetEffect.removed,
          _settlement(cur, clock, deleted: true, origin: cur),
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
    final next = _settlement(old, clock, deleted: false, origin: cur);
    if (settlementProblem(next) != null) {
      skipped++;
      continue;
    }
    changes.add(ResetChange.settlement(effect, next));
  }

  GroupModel? metaChange;
  final oldMeta = target['${RecordKind.meta.wire}|$groupId']?.meta;
  if (meta != null && oldMeta != null && !_sameMeta(oldMeta, meta)) {
    final next = GroupModel(
      roomId: groupId,
      name: oldMeta.name,
      currency: oldMeta.currency,
      categories: oldMeta.categories,
      updatedAt: nextLwwClock(meta.updatedAt, now: now),
    );
    if (groupMetaProblem(next) == null) {
      metaChange = next;
    } else {
      skipped++;
    }
  }

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
  );
}

/// [content]'s fields as a new unsigned version at [clock]; the creator's
/// `origin` comes from [origin] (the stored record — origin never changes),
/// falling back to [content]'s.
ExpenseModel _expense(
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

SettlementModel _settlement(
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
  origin: origin.origin ?? content.origin,
);

/// Same content (the G27 hash with the clock and tombstone flag ignored).
bool _sameExpense(ExpenseModel a, ExpenseModel b) =>
    computeExpenseVersionHash(_expense(a, 0, deleted: false, origin: a)) ==
    computeExpenseVersionHash(_expense(b, 0, deleted: false, origin: a));

bool _sameSettlement(SettlementModel a, SettlementModel b) =>
    computeSettlementVersionHash(
      _settlement(a, 0, deleted: false, origin: a),
    ) ==
    computeSettlementVersionHash(_settlement(b, 0, deleted: false, origin: a));

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
