/// Full-fidelity account backup (G5): one JSON file holding **every** group of
/// the signed-in account, each as the same snapshot the sync protocol sends as
/// a `bootstrap` ([buildBootstrapContent]) — group meta, all participants with
/// their stable ids, Matrix ids and status, and every expense and settlement
/// **including tombstones**, each with its `updated_at` LWW clock.
///
/// ```json
/// {
///   "format": "moneyledger-backup",
///   "version": 1,
///   "exported_at": 1760000000000,
///   "account": "@alice:example.org",
///   "groups": [ { <bootstrap payload> }, … ]
/// }
/// ```
///
/// Pure Dart (models + JSON only) — no DB, no Flutter — so it is fully
/// unit-testable. The DB seams live in `backup_service.dart`.
library;

import 'dart:convert';

import '../../core/sync/ledger_payloads.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';

/// The `format` marker of a MoneyLedger backup file.
const backupFormat = 'moneyledger-backup';

/// The newest backup file version this build writes and understands. Bump it
/// for incompatible changes; older versions must stay readable.
const backupVersion = 1;

/// Why a file couldn't be read as a backup — the UI maps each to a message.
enum BackupErrorKind {
  /// Not JSON, or JSON without our `format` marker (e.g. a CSV or another
  /// app's file).
  notABackup,

  /// A MoneyLedger backup written by a newer app version.
  newerVersion,

  /// Our marker and a known version, but the content is broken.
  malformed,
}

class BackupFormatException implements Exception {
  final BackupErrorKind kind;
  final String detail;

  /// The file's version, for [BackupErrorKind.newerVersion].
  final int? version;
  const BackupFormatException(this.kind, this.detail, {this.version});

  @override
  String toString() => 'BackupFormatException(${kind.name}): $detail';
}

/// One group's snapshot data, as read from the DB for an export.
class GroupSnapshot {
  final GroupModel group;
  final List<MemberModel> members;
  final List<ExpenseModel> expenses;
  final List<SettlementModel> settlements;

  /// G6: first-hand device keys of the snapshot's signers (user → device →
  /// key), so a restore on a fresh device can still check them.
  final Map<String, Map<String, String>> deviceKeys;
  const GroupSnapshot({
    required this.group,
    required this.members,
    required this.expenses,
    required this.settlements,
    this.deviceKeys = const {},
  });
}

/// Builds the backup JSON text for [groups] (pretty-printed — it is meant to
/// be inspectable). Groups are sorted by name for a stable, diffable file.
String buildBackupJson({
  required String? account,
  required int exportedAt,
  required List<GroupSnapshot> groups,
}) {
  final sorted = [...groups]
    ..sort((a, b) => a.group.name.compareTo(b.group.name));
  return const JsonEncoder.withIndent('  ').convert({
    'format': backupFormat,
    'version': backupVersion,
    'exported_at': exportedAt,
    'account': account,
    'groups': [
      for (final g in sorted)
        buildBootstrapContent(
          g.group.roomId,
          g.group,
          g.members,
          g.expenses,
          g.settlements,
          deviceKeys: g.deviceKeys,
          includePending: true,
        ),
    ],
  });
}

/// A parsed, validated backup. [groups] are bootstrap-shaped payloads, ready
/// for the same merge the syncer applies (`LedgerSyncer.processBootstrap`).
class LedgerBackup {
  final int version;
  final int? exportedAt;
  final String? account;
  final List<Map<String, dynamic>> groups;
  const LedgerBackup({
    required this.version,
    required this.exportedAt,
    required this.account,
    required this.groups,
  });
}

/// Parses and validates a backup file. Throws [BackupFormatException] for a
/// non-backup file, a newer version, or broken content — never anything else.
LedgerBackup parseBackup(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException catch (e) {
    throw BackupFormatException(BackupErrorKind.notABackup, e.message);
  }
  if (root is! Map || root['format'] != backupFormat) {
    throw const BackupFormatException(
      BackupErrorKind.notABackup,
      'missing "format": "$backupFormat"',
    );
  }
  final version = root['version'];
  if (version is! int || version < 1) {
    throw BackupFormatException(
      BackupErrorKind.malformed,
      'invalid version: $version',
    );
  }
  if (version > backupVersion) {
    throw BackupFormatException(
      BackupErrorKind.newerVersion,
      'version $version > $backupVersion',
      version: version,
    );
  }
  final rawGroups = root['groups'];
  if (rawGroups is! List) {
    throw const BackupFormatException(
      BackupErrorKind.malformed,
      '"groups" is not a list',
    );
  }
  final groups = <Map<String, dynamic>>[];
  for (final g in rawGroups) {
    groups.add(_validateGroup(g));
  }
  final exportedAt = root['exported_at'];
  final account = root['account'];
  return LedgerBackup(
    version: version,
    exportedAt: exportedAt is int ? exportedAt : null,
    account: account is String && account.isNotEmpty ? account : null,
    groups: groups,
  );
}

/// Checks the shape the merge relies on: a group id, and list-typed record
/// sections whose entries are maps carrying that same group id (records are
/// routed by their own `group` field, so a mismatch would land them in the
/// wrong group) and an id.
Map<String, dynamic> _validateGroup(Object? g) {
  Never bad(String why) =>
      throw BackupFormatException(BackupErrorKind.malformed, why);
  if (g is! Map) bad('group entry is not an object');
  final group = Map<String, dynamic>.from(g);
  final gid = group['group'];
  if (gid is! String || gid.isEmpty) bad('group without id');
  for (final (section, idKey) in const [
    ('members', 'participant_id'),
    ('expenses', 'id'),
    ('settlements', 'id'),
  ]) {
    final list = group[section] ?? const [];
    if (list is! List) bad('$gid: "$section" is not a list');
    final records = <Map<String, dynamic>>[];
    for (final r in list) {
      if (r is! Map) bad('$gid: $section entry is not an object');
      final rec = Map<String, dynamic>.from(r);
      if (rec['group'] != gid) bad('$gid: $section entry of another group');
      if (rec[idKey] is! String) bad('$gid: $section entry without $idKey');
      if (rec['updated_at'] is! int) {
        bad('$gid: $section entry without updated_at');
      }
      records.add(rec);
    }
    group[section] = records;
  }
  return group;
}

/// Summary of one backed-up group for the restore preview.
class BackupGroupSummary {
  final String groupId;
  final String name;
  final int expenseCount; // live (non-deleted) expenses
  final int settlementCount; // live (non-deleted) settlements
  final int memberCount; // active participants
  const BackupGroupSummary({
    required this.groupId,
    required this.name,
    required this.expenseCount,
    required this.settlementCount,
    required this.memberCount,
  });
}

BackupGroupSummary summarizeBackupGroup(Map<String, dynamic> g) {
  int live(String section) => (g[section] as List? ?? const [])
      .where((r) => (r as Map)['deleted'] != true)
      .length;
  return BackupGroupSummary(
    groupId: g['group'] as String,
    name: g['name'] as String? ?? g['group'] as String,
    expenseCount: live('expenses'),
    settlementCount: live('settlements'),
    memberCount: (g['members'] as List? ?? const [])
        .where((m) => (m as Map)['status'] != 'removed')
        .length,
  );
}

/// File name for a backup taken on [at] (local date):
/// `moneyledger-backup-YYYY-MM-DD.json`.
String backupFileName(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'moneyledger-backup-${at.year}-${two(at.month)}-${two(at.day)}.json';
}

// ── backup nudge (G5) ────────────────────────────────────────────────────────

/// How long a backup counts as "recent", and how long "Later" snoozes the
/// nudge.
const kBackupNudgeInterval = Duration(days: 30);

/// The groups nobody else could restore: no **active claimed** participant
/// other than [myMxid] (solo groups, or only local people). If this device is
/// lost, these are gone unless backed up. (A second device of the same
/// account would also help, but its existence isn't known here.)
List<GroupModel> unprotectedGroups({
  required List<GroupModel> groups,
  required List<MemberModel> members,
  required String myMxid,
}) {
  final protectedIds = {
    for (final m in members)
      if (m.isActive && m.matrixId != null && m.matrixId != myMxid) m.groupId,
  };
  return [
    for (final g in groups)
      if (!protectedIds.contains(g.roomId)) g,
  ];
}

/// Whether to show the backup nudge: there is an [unprotected] group, no
/// backup within [kBackupNudgeInterval] (or never), and it isn't snoozed.
bool shouldShowBackupNudge({
  required int unprotectedCount,
  required int? lastBackupAt,
  required int? snoozedUntil,
  required int now,
}) {
  if (unprotectedCount == 0) return false;
  if (snoozedUntil != null && now < snoozedUntil) return false;
  if (lastBackupAt == null) return true;
  return now - lastBackupAt >= kBackupNudgeInterval.inMilliseconds;
}
