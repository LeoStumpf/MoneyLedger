import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/history_dao.dart';
import '../../core/database/daos/link_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/ledger_payloads.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../backup/ledger_backup.dart' show LedgerBackup;
import '../expenses/expenses_provider.dart';
import '../groups/group_provider.dart' show myParticipantIn;
import 'group_history.dart';

/// More reset writes than this are not relayed one by one: the group is
/// poked instead and the digest exchange (anti-entropy) carries them.
const kResetLiveRelayMax = 25;

/// G48: reads a group's version history and applies a reset plan
/// ([planGroupReset]; G58: or a snapshot's state, [planToSnapshot]) as
/// **new versions** — signed by this device like any
/// local edit (`pendingSign` while its key isn't ready), stored in one
/// transaction (history source `revert`) and relayed to the group's members
/// so their devices adopt the reset too.
///
/// Built per account DB; everything is captured at construction (G19), and
/// the UI reads the service before its first await. Every step checks that
/// the DB is still open and bails silently otherwise.
class GroupResetService {
  GroupResetService({
    required this.write,
    required this.groups,
    required this.history,
    required this.poke,
  });

  /// Asks the sync engine for a digest of the group (anti-entropy carries
  /// what wasn't relayed live, and signs `pendingSign` writes first).
  final void Function(String groupId) poke;

  /// The shared write context of local edits (DB, DAOs, signer, relay).
  final LedgerWriteContext write;
  final GroupsDao groups;
  final HistoryDao history;

  ExpensesDao get _expenses => write.expenses;
  bool get _alive => !write.db.isClosed;

  /// The reset of [groupId] to its state before history entry [beforeId].
  Future<GroupResetPlan> plan(String groupId, int beforeId) async {
    final entries = await history.entriesForGroup(groupId);
    final expenses = await _expenses.getAllExpensesForGroup(groupId);
    final settlements = await _expenses.getAllSettlementsForGroup(groupId);
    final meta = await groups.getGroup(groupId);
    return planGroupReset(
      groupId: groupId,
      beforeId: beforeId,
      entries: entries,
      expenses: expenses,
      settlements: settlements,
      meta: meta,
    );
  }

  /// G58 "exactly this state": the reset of backed-up / snapshotted
  /// [group] (a backup group payload) to that content — or null when it
  /// can't be reset here: the group isn't stored on this device (the normal
  /// restore brings it back), or [me] (this device's account, `local:self`
  /// in local mode; in a link group the channel's participant) isn't an
  /// **active** participant of it (removed → read-only history, G26; never
  /// part of it → not ours to rewrite). Participants are never part of a
  /// plan.
  Future<GroupResetPlan?> planToSnapshot(
    Map<String, dynamic> group, {
    required String me,
  }) async {
    final gid = group['group'] as String;
    final meta = await groups.getGroup(gid);
    if (meta == null || !_alive) return null;
    // G52: in a link group "me" is the channel's participant.
    final self = await myParticipantIn(
      write.members,
      LinkDao(write.db),
      gid,
      me,
    );
    if (self == null || !self.isActive || !_alive) return null;
    final entries = await history.entriesForGroup(gid);
    final expenses = await _expenses.getAllExpensesForGroup(gid);
    final settlements = await _expenses.getAllSettlementsForGroup(gid);
    return planGroupResetTo(
      groupId: gid,
      target: snapshotResetTarget(group, history: entries),
      expenses: expenses,
      settlements: settlements,
      meta: meta,
    );
  }

  /// G58: after the normal (LWW) restore of [backup], makes each group in
  /// [groupIds] exactly equal to its content in [backup] — re-planned on
  /// what is stored **now** (the merge may just have brought records back)
  /// and applied like a reset ([apply]: new signed versions, one
  /// transaction per group, relayed, poked). Groups that can't be reset
  /// ([planToSnapshot] null) or need nothing are skipped. Returns the number
  /// of versions written.
  Future<int> resetGroupsToSnapshot(
    LedgerBackup backup,
    Iterable<String> groupIds, {
    required String me,
  }) async {
    final wanted = groupIds.toSet();
    var written = 0;
    for (final g in backup.groups) {
      if (!_alive) return written;
      if (!wanted.contains(g['group'])) continue;
      final plan = await planToSnapshot(g, me: me);
      if (plan == null || plan.isEmpty || !_alive) continue;
      written += await apply(plan);
    }
    return written;
  }

  /// Signs, stores and relays [plan]. Returns the number of versions
  /// written (0 when the DB closed meanwhile). A record that changed after
  /// the preview with an even newer clock keeps that newer version (LWW).
  Future<int> apply(GroupResetPlan plan) async {
    final signer = write.signer;
    final expenses = <ExpenseModel>[];
    final settlements = <SettlementModel>[];
    for (final c in plan.changes) {
      if (!_alive) return 0;
      if (c.expense case final e?) {
        expenses.add(await signer.expense(e));
      } else if (c.settlement case final s?) {
        settlements.add(await signer.settlement(s));
      }
    }
    final GroupModel? meta = plan.meta == null
        ? null
        : await signer.group(plan.meta!);
    if (!_alive) return 0;
    await write.db.transaction(() async {
      for (final e in expenses) {
        await _expenses.upsertExpenseLww(
          expenseCompanion(e),
          source: HistorySource.revert,
        );
      }
      for (final s in settlements) {
        await _expenses.upsertSettlementLww(
          settlementCompanion(s),
          source: HistorySource.revert,
        );
      }
      if (meta != null) {
        await groups.upsertGroupLww(
          groupCompanion(meta),
          source: HistorySource.revert,
        );
      }
    });
    final written =
        expenses.length + settlements.length + (meta == null ? 0 : 1);
    if (written <= kResetLiveRelayMax) {
      final gid = plan.groupId;
      for (final e in expenses) {
        await write.replicate(gid, expenseEventType, expensePayload(e));
      }
      for (final s in settlements) {
        await write.replicate(gid, settlementEventType, settlementPayload(s));
      }
      if (meta != null) {
        await write.replicate(gid, groupMetaEventType, groupMetaPayload(meta));
      }
    }
    poke(plan.groupId);
    return written;
  }
}

/// The [GroupResetService] of the current account's DB.
final groupResetServiceProvider = Provider.autoDispose<GroupResetService>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return GroupResetService(
    write: LedgerWriteContext(ref),
    groups: ref.watch(groupsDaoProvider),
    history: HistoryDao(db),
    poke: ref.read(syncEngineProvider).pokeGroup,
  );
});

/// The version history of [groupId] (reactive), for the change list.
final groupHistoryProvider = StreamProvider.autoDispose
    .family<List<HistoryEntry>, String>(
      (ref, groupId) => HistoryDao(
        ref.watch(appDatabaseProvider),
      ).watchEntriesForGroup(groupId),
    );

/// The pruning floor of the current account's history (reactive).
final historyFloorProvider = StreamProvider.autoDispose<int>(
  (ref) => HistoryDao(ref.watch(appDatabaseProvider)).watchFloor(),
);
