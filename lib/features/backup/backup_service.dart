import 'package:flutter/foundation.dart' show debugPrint;
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
import '../../models/member_model.dart';
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

  /// The backup JSON for every local group of this account — or, with
  /// [onlyGroup] (G34 per-group backup from the group menu), for that one
  /// group (same format, a single entry in `groups`).
  Future<String> exportJson({
    required String? account,
    required int now,
    String? onlyGroup,
  }) async {
    final snapshots = <GroupSnapshot>[];
    final all = await groups.getAllGroups();
    for (final g in all.where(
      (g) => onlyGroup == null || g.roomId == onlyGroup,
    )) {
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
          removed: myMxid != null && myMxid.isNotEmpty
              ? backupShowsMeRemoved(
                  g,
                  myMxid: myMxid,
                  local: await members.getMembers(gid),
                )
              : false,
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

  /// Merges [backup] into the local ledger: per group, in **one
  /// transaction**, the same last-writer-wins upserts the syncer applies to a
  /// `bootstrap` (by stable id; tombstones win when newer) — so a restore is
  /// idempotent and never duplicates, and a group is restored completely or
  /// not at all. Restoring is an explicit user intent, so there is no
  /// membership gate, and a group this account had left/deleted here has its
  /// left-group tombstone cleared (otherwise the syncer would keep dropping
  /// its records). Returns the ids of the restored groups.
  ///
  /// G6: every signed version is verified like an inbound record
  /// ([RecordGate]); a tampered one is refused, the rest restore. The file's
  /// `device_keys` are trusted as vouched-for keys (the user chose the
  /// file), and unsigned rows (pre-G6 history in the user's own backup) are
  /// restored as legacy.
  ///
  /// G35: the homeserver lookups verification needs happen **first**, for
  /// every signer in the file ([RecordVerifier.prefetch]); the per-group
  /// transactions then run without network round-trips. A group whose
  /// transaction fails is rolled back and the others still restore; the
  /// failures are reported together at the end ([RestoreIncompleteException]).
  Future<List<String>> restore(LedgerBackup backup) async {
    final restored = <String>[];
    final t = await transport;
    if (!_alive) return restored;
    final verifier = RecordVerifier(
      crypto: t.crypto,
      directory: t.deviceKeys,
      signing: signing,
      // Long enough to cover the whole restore: no lookups mid-transaction.
      refreshInterval: const Duration(minutes: 10),
    );
    final gate = RecordGate(
      verifier: verifier,
      signing: signing,
      groups: groups,
      members: members,
      expenses: expenses,
      acceptUnsigned: true,
      isAlive: () => _alive,
    );
    await verifier.prefetch({
      for (final g in backup.groups) ...payloadSignerUsers(g),
    });
    final failed = <String, Object>{};
    for (final g in backup.groups) {
      if (!_alive) return restored;
      final gid = g['group'] as String;
      try {
        await db.transaction(() async {
          await settings.clearGroupLeft(gid);
          if (!_alive) return;
          await gate.snapshot(
            g,
            relayedBy: backup.account ?? t.userId,
            trustAttestations: true,
          );
        });
      } catch (e) {
        if (!_alive) return restored;
        debugPrint('[backup] restore of $gid failed, rolled back: $e');
        failed[gid] = e;
        continue;
      }
      if (!_alive) return restored;
      if (await groups.getGroup(gid) != null) restored.add(gid);
    }
    if (failed.isNotEmpty) {
      throw RestoreIncompleteException(restored: restored, failed: failed);
    }
    return restored;
  }
}

/// Some groups of a backup couldn't be restored (each was rolled back as a
/// whole); [restored] went through.
class RestoreIncompleteException implements Exception {
  final List<String> restored;
  final Map<String, Object> failed;
  const RestoreIncompleteException({
    required this.restored,
    required this.failed,
  });

  @override
  String toString() =>
      '${failed.length} group(s) not restored: ${failed.values.first}';
}

/// Every account that signed a version in a backed-up group payload (`sig`
/// and `origin` of its meta, members, expenses and settlements).
Set<String> payloadSignerUsers(Map<String, dynamic> group) {
  final users = <String>{};
  void add(Object? record) {
    if (record is! Map) return;
    for (final k in const ['sig', 'origin']) {
      final s = record[k];
      if (s is Map && s['user'] is String) users.add(s['user'] as String);
    }
  }

  add(group['meta']);
  for (final section in const ['members', 'expenses', 'settlements']) {
    for (final r in group[section] as List? ?? const []) {
      add(r);
    }
  }
  return users;
}

/// Whether restoring backed-up [group] leaves this account ([myMxid]) as a
/// **removed** participant — the newer of the backup's and the [local]
/// version of the participant [myMxid] claims says `removed`. Such a group
/// comes back as read-only history (G26); peers that removed us *after* the
/// backup can only tell us at the next sync (then it turns read-only too).
bool backupShowsMeRemoved(
  Map<String, dynamic> group, {
  required String myMxid,
  required List<MemberModel> local,
}) {
  // LWW-merge the local and the backed-up participants, as the restore will.
  final merged = {for (final m in local) m.userId: m};
  for (final raw in group['members'] as List? ?? const []) {
    final m = memberFromPayload(Map<String, dynamic>.from(raw as Map));
    if (m == null) continue;
    final have = merged[m.userId];
    if (have == null || m.updatedAt > have.updatedAt) merged[m.userId] = m;
  }
  final me = claimedBy(merged.values, myMxid);
  return me != null && !me.isActive;
}

class GroupRestorePlan {
  final BackupGroupSummary summary;
  final bool isNew;

  /// This account left / deleted the group on this device (G9 tombstone);
  /// restoring brings it back.
  final bool wasLeft;

  /// Records the restore would add or update (0 = already up to date).
  final int changes;

  /// This account is a removed participant after the restore (backup or
  /// local copy, whichever is newer) — the group comes back read-only.
  final bool removed;
  const GroupRestorePlan({
    required this.summary,
    required this.isNew,
    required this.wasLeft,
    required this.changes,
    this.removed = false,
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
