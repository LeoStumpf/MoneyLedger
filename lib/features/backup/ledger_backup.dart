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
///   "groups": [ { <bootstrap payload>, "link"?: {"epoch", "secret"} }, … ]
/// }
/// ```
///
/// G52 step 10: a **link group**'s entry also carries `link` — the invite
/// key (`secret`, the link's `k`, base64url) and its `epoch` — so a restore
/// can re-open the channel (design doc §7.2, §14 Q7). It sits next to the
/// bootstrap content, not in the (signed / hashed) meta, so nothing on the
/// wire changes; older builds ignore it. This device's Nostr key and "who
/// am I" are **not** in the file (a restore asks again).
///
/// Pure Dart (models + JSON only) — no DB, no Flutter — so it is fully
/// unit-testable. The DB seams live in `backup_service.dart`.
library;

import 'dart:convert';

import '../../core/link/group_policy.dart';
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

  /// G52 step 10: the group's link channel on this device (null = not a
  /// link group here).
  final BackupLink? link;
  const GroupSnapshot({
    required this.group,
    required this.members,
    required this.expenses,
    required this.settlements,
    this.deviceKeys = const {},
    this.link,
  });
}

/// G52 step 10: a link group's invite key as the backup file carries it.
class BackupLink {
  final int epoch;

  /// The link secret, base64url without padding (the link's `k`).
  final String secret;
  const BackupLink({required this.epoch, required this.secret});

  Map<String, Object> toJson() => {'epoch': epoch, 'secret': secret};

  @override
  String toString() => 'BackupLink(epoch: $epoch)'; // never the secret
}

/// G52 step 10: the invite key of backed-up [group] (its `link` entry), or
/// null — also for a malformed one (the group then restores without a
/// channel, like any other group).
BackupLink? backupGroupLink(Map<String, dynamic> group) {
  final raw = group['link'];
  if (raw is! Map) return null;
  final epoch = raw['epoch'];
  final secret = raw['secret'];
  if (epoch is! int || epoch < 1 || secret is! String || secret.isEmpty) {
    return null;
  }
  return BackupLink(epoch: epoch, secret: secret);
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
        {
          ...buildBootstrapContent(
            g.group.roomId,
            g.group,
            g.members,
            g.expenses,
            g.settlements,
            deviceKeys: g.deviceKeys,
            includePending: true,
          ),
          if (g.link case final link?) 'link': link.toJson(),
        },
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
/// `moneyledger-backup-YYYY-MM-DD.json`, or for a single group (G34)
/// `moneyledger-backup-<group-slug>-YYYY-MM-DD.json`.
String backupFileName(DateTime at, {String? groupName}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final slug = groupName == null ? '' : '${fileNameSlug(groupName)}-';
  return 'moneyledger-backup-$slug${at.year}-${two(at.month)}-${two(at.day)}'
      '.json';
}

/// A short, filesystem-safe slug of [name]: lower case, letters (incl.
/// non-ASCII ones like "ü") and digits kept, everything else collapsed to
/// `-`, at most 40 characters; `group` when nothing is left.
String fileNameSlug(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) return 'group';
  final cut = slug.length > 40 ? slug.substring(0, 40) : slug;
  return cut.replaceAll(RegExp(r'-+$'), '');
}

/// The file name to show after a save (G34). On Android the save dialog may
/// store the file under another name (`… (1).json`, or one the user typed);
/// file_picker returns the saved document's path, whose last segment is the
/// real name only for some providers (`…/primary:Download/x (1).json`, but
/// `…/document/msf:1000000033` for the Downloads provider). Returns that
/// name when it looks like a file of [extension], else null — the UI then
/// says "Backup saved" without a (possibly wrong) name.
String? savedFileDisplayName(String? savedPath, String extension) {
  if (savedPath == null || savedPath.isEmpty) return null;
  var last = savedPath;
  try {
    last = Uri.decodeFull(savedPath);
  } on ArgumentError {
    // keep it raw
  }
  last = last.split('/').last.split(':').last.trim();
  if (last.isEmpty || !last.toLowerCase().endsWith('.$extension')) return null;
  if (last.length == extension.length + 1) return null; // just ".json"
  return last;
}

// ── backup nudge (G5) ────────────────────────────────────────────────────────

/// How long a backup counts as "recent", and how long "Later" snoozes the
/// nudge.
const kBackupNudgeInterval = Duration(days: 30);

/// The groups nobody else could restore: no **active claimed** participant
/// other than [myMxid] (solo groups, or only local people). If this device is
/// lost, these are gone unless backed up — or unless a second device of the
/// same account holds them ([secondOwnDeviceProtects]).
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

/// Leo 2026-10-22: the groups shared by an open link (link-only or mixed —
/// a locked group no longer is) — anyone with the link can change or empty
/// them, so the nudge counts them whoever else holds a copy (another
/// member's or our own other device's copy would be emptied just the same).
/// [channelGroupIds]: the groups this device has a link channel for.
List<GroupModel> linkSharedGroups({
  required List<GroupModel> groups,
  required Set<String> channelGroupIds,
}) => [
  for (final g in groups)
    if (deriveGroupPolicyFor(
          hasChannel: channelGroupIds.contains(g.roomId),
          meta: g,
        ) !=
        GroupPolicy.matrix)
      g,
];

/// What the backup nudge says: [onlyHere] groups nobody else could restore
/// ([unprotectedGroups], not shared by link) and [link] groups shared by
/// link ([linkSharedGroups]). Both 0 = no nudge.
class BackupNudgeCounts {
  final int onlyHere;
  final int link;
  const BackupNudgeCounts({this.onlyHere = 0, this.link = 0});

  static const none = BackupNudgeCounts();

  bool get show => onlyHere > 0 || link > 0;

  @override
  bool operator ==(Object other) =>
      other is BackupNudgeCounts &&
      other.onlyHere == onlyHere &&
      other.link == link;

  @override
  int get hashCode => Object.hash(onlyHere, link);

  @override
  String toString() => 'BackupNudgeCounts(onlyHere: $onlyHere, link: $link)';
}

/// How recently another device of our own account must have proven it holds
/// our groups (a matching digest / record from our own MXID) to count as a
/// second copy for the nudge.
const kOwnDeviceSeenWindow = Duration(days: 30);

/// Whether another device of this account protects the solo groups too, so
/// the backup nudge isn't needed (G34): one of our other current devices is
/// **verified** ([otherVerifiedOwnDevice] — a device the user confirmed is
/// theirs; it keeps every group in sync), or one of them proved within
/// [kOwnDeviceSeenWindow] that it holds our state ([lastOwnDeviceInSyncAt]:
/// the newest `lastInSyncAt` recorded for our own MXID — set when a digest
/// from another own device matched ours).
bool secondOwnDeviceProtects({
  required bool otherVerifiedOwnDevice,
  required int? lastOwnDeviceInSyncAt,
  required int now,
}) {
  if (otherVerifiedOwnDevice) return true;
  final seen = lastOwnDeviceInSyncAt;
  return seen != null &&
      seen > 0 &&
      now - seen < kOwnDeviceSeenWindow.inMilliseconds;
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
