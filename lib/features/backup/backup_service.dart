import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/database/daos/signing_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../core/sync/ledger_payloads.dart';
import '../../core/sync/record_gate.dart';
import '../../core/sync/record_verifier.dart';
import '../expenses/expenses_provider.dart';
import '../onboarding/onboarding_provider.dart';
import 'ledger_backup.dart';

/// The DB side of the full backup (G5): export every group of the account,
/// preview a backup file against the local ledger, and restore it.
///
/// Built per account DB ([backupServiceProvider] watches the DB), and the UI
/// reads it **before** its first await — so an export/restore always targets
/// the account that was active when the user acted (G19). Every step checks
/// that the DB is still open and bails silently otherwise.
class BackupService {
  final AppDatabase db;
  final GroupsDao groups;
  final MembersDao members;
  final ExpensesDao expenses;
  final SettingsDao settings;

  /// G6: device-key history (export attestations, restore verification).
  final SigningDao signing;

  /// G6: the relay identity — its crypto verifies restored signatures.
  final Future<LedgerTransport> transport;

  BackupService({
    required this.db,
    required this.groups,
    required this.members,
    required this.expenses,
    required this.settings,
    required this.signing,
    required this.transport,
  });

  bool get _alive => !db.isClosed;

  /// The backup JSON for every local group of this account.
  Future<String> exportJson({
    required String? account,
    required int now,
  }) async {
    final snapshots = <GroupSnapshot>[];
    for (final g in await groups.getAllGroups()) {
      if (!_alive) throw StateError('account switched during export');
      final ms = await members.getMembers(g.roomId);
      final es = await expenses.getAllExpensesForGroup(g.roomId);
      final ss = await expenses.getAllSettlementsForGroup(g.roomId);
      snapshots.add(
        GroupSnapshot(
          group: g,
          members: ms,
          expenses: es,
          settlements: ss,
          deviceKeys: await signing.attestationsFor(
            snapshotSigners(g, ms, es, ss),
          ),
        ),
      );
    }
    return buildBackupJson(
      account: account,
      exportedAt: now,
      groups: snapshots,
    );
  }

  /// Records a successful backup (device-local, per account).
  Future<void> markBackedUp(int at) async {
    if (_alive) await settings.setLastBackupAt(at);
  }

  /// What restoring [backup] would do: per group whether it is new here, was
  /// left/deleted on this device, and how many records would change (absent
  /// locally, or older locally than in the backup).
  Future<RestorePreview> preview(
    LedgerBackup backup, {
    required String? myMxid,
  }) async {
    final plans = <GroupRestorePlan>[];
    for (final g in backup.groups) {
      if (!_alive) throw StateError('account switched during preview');
      final gid = g['group'] as String;
      final local = await groups.getGroup(gid);
      final left = await settings.leftGroup(gid);
      var changes = 0;
      final metaClock = g['updated_at'] as int? ?? 0;
      if (local == null || local.updatedAt < metaClock) changes++;
      final localMembers = {
        for (final m in await members.getMembers(gid)) m.userId: m.updatedAt,
      };
      final localExpenses = {
        for (final e in await expenses.getAllExpensesForGroup(gid))
          e.id: e.updatedAt,
      };
      final localSettlements = {
        for (final s in await expenses.getAllSettlementsForGroup(gid))
          s.id: s.updatedAt,
      };
      int count(String section, String idKey, Map<String, int> localClocks) {
        var n = 0;
        for (final r in g[section] as List) {
          final rec = r as Map<String, dynamic>;
          final have = localClocks[rec[idKey] as String];
          if (have == null || have < (rec['updated_at'] as int)) n++;
        }
        return n;
      }

      changes += count('members', 'participant_id', localMembers);
      changes += count('expenses', 'id', localExpenses);
      changes += count('settlements', 'id', localSettlements);
      plans.add(
        GroupRestorePlan(
          summary: summarizeBackupGroup(g),
          isNew: local == null,
          wasLeft: local == null && left != null,
          changes: changes,
        ),
      );
    }
    return RestorePreview(
      backup: backup,
      groups: plans,
      otherAccount:
          backup.account != null &&
          myMxid != null &&
          myMxid.isNotEmpty &&
          backup.account != myMxid,
    );
  }

  /// Merges [backup] into the local ledger: per group, in one transaction,
  /// the same last-writer-wins upserts the syncer applies to a `bootstrap`
  /// (by stable id; tombstones win when newer) — so a restore is idempotent
  /// and never duplicates. Restoring is an explicit user intent, so there is
  /// no membership gate, and a group this account had left/deleted here has
  /// its left-group tombstone cleared first (otherwise the syncer would keep
  /// dropping its records). Returns the ids of the restored groups.
  ///
  /// G6: every signed version is verified like an inbound record
  /// ([RecordGate]); a tampered one is refused, the rest restore. The file's
  /// `device_keys` are trusted as vouched-for keys (the user chose the
  /// file), and unsigned rows (pre-G6 history in the user's own backup) are
  /// restored as legacy. (Not in one transaction: verifying may look up
  /// device keys on the homeserver.)
  Future<List<String>> restore(LedgerBackup backup) async {
    final restored = <String>[];
    final t = await transport;
    if (!_alive) return restored;
    final gate = RecordGate(
      verifier: RecordVerifier(
        crypto: t.crypto,
        directory: t.deviceKeys,
        signing: signing,
      ),
      signing: signing,
      groups: groups,
      members: members,
      expenses: expenses,
      acceptUnsigned: true,
      isAlive: () => _alive,
    );
    for (final g in backup.groups) {
      if (!_alive) return restored;
      final gid = g['group'] as String;
      await settings.clearGroupLeft(gid);
      if (!_alive) return restored;
      await gate.snapshot(
        g,
        relayedBy: backup.account ?? t.userId,
        trustAttestations: true,
      );
      if (await groups.getGroup(gid) != null) restored.add(gid);
    }
    return restored;
  }
}

class GroupRestorePlan {
  final BackupGroupSummary summary;
  final bool isNew;

  /// This account left / deleted the group on this device (G9 tombstone);
  /// restoring brings it back.
  final bool wasLeft;

  /// Records the restore would add or update (0 = already up to date).
  final int changes;
  const GroupRestorePlan({
    required this.summary,
    required this.isNew,
    required this.wasLeft,
    required this.changes,
  });
}

class RestorePreview {
  final LedgerBackup backup;
  final List<GroupRestorePlan> groups;

  /// The backup was taken by a different Matrix account.
  final bool otherAccount;
  const RestorePreview({
    required this.backup,
    required this.groups,
    required this.otherAccount,
  });

  int get newGroups => groups.where((g) => g.isNew).length;
  int get changes => groups.fold(0, (n, g) => n + g.changes);
  int get expenses => groups.fold(0, (n, g) => n + g.summary.expenseCount);
  int get settlements =>
      groups.fold(0, (n, g) => n + g.summary.settlementCount);
}

/// The [BackupService] for the signed-in account's DB.
final backupServiceProvider = Provider.autoDispose<BackupService>(
  (ref) => BackupService(
    db: ref.watch(appDatabaseProvider),
    groups: ref.watch(groupsDaoProvider),
    members: ref.watch(membersDaoProvider),
    expenses: ref.watch(expensesDaoProvider),
    settings: ref.watch(settingsDaoProvider),
    signing: ref.watch(signingDaoProvider),
    transport: ref.watch(ledgerTransportProvider.future),
  ),
);
