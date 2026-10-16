import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/history_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/ledger_payloads.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../expenses/expenses_provider.dart';
import 'group_history.dart';

/// More reset writes than this are not relayed one by one: the group is
/// poked instead and the digest exchange (anti-entropy) carries them.
const kResetLiveRelayMax = 25;

/// G48: reads a group's version history and applies a reset plan
/// ([planGroupReset]) as **new versions** — signed by this device like any
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
