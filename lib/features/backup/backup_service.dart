import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/link_dao.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/database/daos/signing_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../core/link/link_channel.dart';
import '../../core/session/app_session.dart';
import '../../core/session/local_adoption.dart';
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

  /// G52 step 10: this ledger's link channels (export / restore the invite
  /// keys).
  late final LinkDao _link = LinkDao(db);

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
      final channel = await _link.getChannel(g.roomId);
      snapshots.add(
        GroupSnapshot(
          group: g,
          members: ms,
          expenses: es,
          settlements: ss,
          deviceKeys: await signing.attestationsFor(
            snapshotSigners(g, ms, es, ss),
          ),
          link: channel == null
              ? null
              : BackupLink(epoch: channel.epoch, secret: channel.secret),
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
    final takeover = restoreTakeover(backup.account, myMxid);
    // Whose participant becomes "me" (G41), for the removed check too.
    final alias = switch (takeover) {
      RestoreTakeover.localIntoAccount => kLocalAccountId,
      RestoreTakeover.accountIntoLocal => backup.account,
      RestoreTakeover.none => null,
    };
    final plans = <GroupRestorePlan>[];
    var reopenedLinks = 0;
    for (final g in backup.groups) {
      if (!_alive) throw StateError('account switched during preview');
      final gid = g['group'] as String;
      final local = await groups.getGroup(gid);
      // DEV-J: only a link group that isn't here comes back with its key
      // (`reopenLinkChannel`) and needs "who are you?" — one already here
      // keeps its own channel.
      if (local == null && backupGroupLink(g) != null) reopenedLinks++;
      final left = await settings.leftGroup(gid);
      var changes = 0;
      final metaClock = g['updated_at'] as int? ?? 0;
      if (local == null || local.updatedAt < metaClock) changes++;
      final localMembers = await members.getMembers(gid);
      final localMemberClocks = {
        for (final m in localMembers) m.userId: m.updatedAt,
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

      changes += count('members', 'participant_id', localMemberClocks);
      changes += count('expenses', 'id', localExpenses);
      changes += count('settlements', 'id', localSettlements);
      plans.add(
        GroupRestorePlan(
          summary: summarizeBackupGroup(g),
          isNew: local == null,
          wasLeft: local == null && left != null,
          changes: changes,
          removed: [myMxid, alias].any(
            (id) =>
                id != null &&
                id.isNotEmpty &&
                backupShowsMeRemoved(g, myMxid: id, local: localMembers),
          ),
        ),
      );
    }
    return RestorePreview(
      backup: backup,
      groups: plans,
      takeover: takeover,
      myAccount: myMxid,
      linkGroups: reopenedLinks,
      otherAccount:
          takeover == RestoreTakeover.none &&
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
  ///
  /// G41: a backup made in **local mode** (`account` = [kLocalAccountId])
  /// restored into a Matrix account is adopted like "Connect a Matrix
  /// account": in the same transaction the participant claimed by the local
  /// pseudo account becomes claimed by this account and every unsigned row
  /// of the group is marked `pendingSign` ([reclaimGroupInPlace]); after the
  /// transactions this device signs them ([signAdoptedGroups], incl. "added
  /// by") — or, if its key isn't ready, the sync engine does before the
  /// first digest. A Matrix backup restored **in local mode** hands the
  /// backup account's participant to the local pseudo account (the user is
  /// "me" there; nothing can be signed or sent) — connecting that account
  /// later adopts it back.
  ///
  /// G18 review 2: a backup file is not authenticated — anyone can write a
  /// "local" one — so this device only ever signs what can't hurt anyone
  /// else: a local backup's group is adopted (re-claimed + signed) only when
  /// it is **truly local** ([isOwnLocalGroup]: no participant claimed by a
  /// Matrix account in the file or already here, no signature in the file).
  /// Any other group of a local backup is restored as unsigned legacy rows,
  /// its `local:self` claims dropped (a new participant is kept unclaimed),
  /// nothing signed. Restoring a local backup **in local mode** marks a truly
  /// local group's rows `pendingSign` (they are local mode's own, like local
  /// writes; connecting an account signs them). A Matrix backup in local
  /// mode re-claims only a **signed** participant of the backup account. A
  /// normal restore never signs anything.
  Future<List<String>> restore(LedgerBackup backup) async {
    final restored = <String>[];
    final t = await transport;
    if (!_alive) return restored;
    final takeover = restoreTakeover(backup.account, t.userId);
    final localFile = isLocalAccountId(backup.account);
    final inLocalMode = isLocalAccountId(t.userId);
    final adopted = <String>[];
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
    // Local mode's own claims (`local:self`) are only accepted from a truly
    // local group of a local backup (G18 review 2).
    final localGate = RecordGate(
      verifier: verifier,
      signing: signing,
      groups: groups,
      members: members,
      expenses: expenses,
      acceptUnsigned: true,
      allowLocalClaims: true,
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
          // G18 review 2: only a truly local group keeps local mode's claims.
          var payload = g;
          var ownLocal = false;
          if (localFile) {
            final here = await members.getMembers(gid);
            ownLocal = isOwnLocalGroup(g, here);
            if (!ownLocal) payload = withoutLocalClaims(g, here);
          }
          await settings.clearGroupLeft(gid);
          if (!_alive) return;
          // G52 step 10: a link group's channel comes back first, so its
          // records go in as a link-only group (never adopted / signed).
          if (backupGroupLink(g) case final link?) {
            if (await reopenLinkChannel(
              db,
              gid,
              epoch: link.epoch,
              secret: link.secret,
            )) {
              debugPrint('[backup] $gid: link channel re-opened');
            }
            if (!_alive) return;
          }
          await (ownLocal ? localGate : gate).snapshot(
            payload,
            relayedBy: backup.account ?? t.userId,
            trustAttestations: true,
          );
          if (!_alive) return;
          // G18 review: the group's meta was refused → nothing restored; roll
          // the cleared left-group tombstone (and anything else) back.
          if (await groups.getGroup(gid) == null) {
            throw const _GroupNotRestored();
          }
          if (await _takeOver(
            gid,
            takeover,
            backup.account,
            t.userId,
            ownLocal: ownLocal,
            inLocalMode: inLocalMode,
          )) {
            adopted.add(gid);
          }
        });
      } on _GroupNotRestored {
        debugPrint('[backup] $gid not restored: its group meta was refused');
        continue;
      } catch (e) {
        if (!_alive) return restored;
        debugPrint('[backup] restore of $gid failed, rolled back: $e');
        failed[gid] = e;
        continue;
      }
      if (!_alive) return restored;
      if (await groups.getGroup(gid) != null) restored.add(gid);
    }
    if (adopted.isNotEmpty && _alive) {
      final signed = await signAdoptedGroups(
        crypto: t.crypto,
        groups: groups,
        members: members,
        expenses: expenses,
        groupIds: adopted.where(restored.contains),
        isAlive: () => _alive,
      );
      debugPrint(
        '[backup] adopted ${adopted.length} local-mode group(s) into '
        '${t.userId} (${signed ?? 'none yet, key not ready —'} rows signed)',
      );
    }
    if (failed.isNotEmpty) {
      throw RestoreIncompleteException(restored: restored, failed: failed);
    }
    return restored;
  }

  /// G41, inside [gid]'s restore transaction: the [takeover] step. Returns
  /// whether the group now waits for this account's signatures.
  ///
  /// G18 review 2: [ownLocal] = the group is a truly local group of a local
  /// backup ([isOwnLocalGroup]) — the only kind this device may adopt and
  /// sign. [inLocalMode]: the ledger restored into is local mode's.
  Future<bool> _takeOver(
    String gid,
    RestoreTakeover takeover,
    String? backupAccount,
    String me, {
    required bool ownLocal,
    required bool inLocalMode,
  }) async {
    switch (takeover) {
      case RestoreTakeover.accountIntoLocal:
        // Only a claim the backup account really signed becomes "me".
        await reclaimGroupInPlace(
          groups: groups,
          members: members,
          expenses: expenses,
          groupId: gid,
          from: backupAccount!,
          to: kLocalAccountId,
          signLater: false,
          onlySignedClaims: true,
        );
        return false;
      case RestoreTakeover.localIntoAccount:
        if (!ownLocal) return false;
        await reclaimGroupInPlace(
          groups: groups,
          members: members,
          expenses: expenses,
          groupId: gid,
          from: kLocalAccountId,
          to: me,
          signLater: true,
        );
        return true;
      case RestoreTakeover.none:
        // Local mode's own backup in local mode: its truly local groups'
        // rows are local mode's own writes again (signed once an account is
        // connected). Nothing is ever signed here.
        if (inLocalMode && ownLocal) {
          await markUnsignedPending(
            groups: groups,
            members: members,
            expenses: expenses,
            groupId: gid,
          );
        }
        return false;
    }
  }
}

/// G18 review 2: whether backed-up [group] (from a **local-mode** backup) is
/// a truly local group this device may adopt: no participant — in the file
/// or already [here] — is claimed by a Matrix account (only by local mode's
/// pseudo account, or nobody), and nothing in the file is signed (local mode
/// can't sign: a signature means the group came from somewhere else).
bool isOwnLocalGroup(Map<String, dynamic> group, List<MemberModel> here) {
  bool foreignClaim(String? id) => id != null && !isLocalAccountId(id);
  if (here.any((m) => foreignClaim(m.matrixId))) return false;
  for (final raw in group['members'] as List? ?? const []) {
    if (raw is! Map) continue;
    final m = memberFromPayload(Map<String, dynamic>.from(raw));
    if (m != null && foreignClaim(m.matrixId)) return false;
  }
  if (payloadSignerUsers(group).isNotEmpty) return false;
  final meta = group['meta'];
  if (meta is Map && meta['sig'] != null) return false;
  return true;
}

/// G18 review 2: [group] without local mode's claims — for a local backup's
/// group that isn't truly local ([isOwnLocalGroup]). A participant claimed
/// by `local:self` that is already [here] is left out (the stored version
/// stays); a new one is kept as an unclaimed (local) person.
Map<String, dynamic> withoutLocalClaims(
  Map<String, dynamic> group,
  List<MemberModel> here,
) {
  final known = {for (final m in here) m.userId};
  final out = <Map<String, dynamic>>[];
  for (final raw in group['members'] as List? ?? const []) {
    if (raw is! Map) continue;
    final entry = Map<String, dynamic>.from(raw);
    final m = memberFromPayload(entry);
    if (m == null || !isLocalAccountId(m.matrixId)) {
      out.add(entry);
      continue;
    }
    if (known.contains(m.userId)) continue;
    out.add(
      memberPayload(
        MemberModel(
          groupId: m.groupId,
          userId: m.userId,
          displayName: m.displayName,
          status: m.status,
          updatedAt: m.updatedAt,
        ),
      ),
    );
  }
  return {...group, 'members': out};
}

/// G41: whose participant a restore hands to whom.
enum RestoreTakeover {
  /// A normal restore (same account, another account's backup, or a local
  /// backup in local mode).
  none,

  /// A local-mode backup restored into a Matrix account: adopted by it.
  localIntoAccount,

  /// A Matrix account's backup restored in local mode: the user becomes that
  /// account's participant here.
  accountIntoLocal,
}

/// Which [RestoreTakeover] restoring a backup of [backupAccount] into
/// [me]'s ledger (an MXID, or [kLocalAccountId] in local mode) means.
RestoreTakeover restoreTakeover(String? backupAccount, String? me) {
  bool isMxid(String? id) => id != null && id.startsWith('@');
  if (isLocalAccountId(backupAccount) && isMxid(me)) {
    return RestoreTakeover.localIntoAccount;
  }
  if (isMxid(backupAccount) && isLocalAccountId(me)) {
    return RestoreTakeover.accountIntoLocal;
  }
  return RestoreTakeover.none;
}

/// Aborts (rolls back) a group's restore transaction whose group meta was
/// refused — e.g. so its left-group tombstone isn't cleared for nothing.
class _GroupNotRestored implements Exception {
  const _GroupNotRestored();
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

  /// G41: the backup's "me" moves to this ledger's (local backup into an
  /// account, or an account's backup in local mode).
  final RestoreTakeover takeover;

  /// The ledger restored into: the signed-in MXID, or [kLocalAccountId].
  final String? myAccount;

  /// G52 step 10: link groups of the file whose invite key the restore
  /// brings back (not held here yet — DEV-J: a group already here keeps its
  /// own channel, so its key in the file changes nothing).
  final int linkGroups;
  const RestorePreview({
    required this.backup,
    required this.groups,
    required this.otherAccount,
    this.takeover = RestoreTakeover.none,
    this.myAccount,
    this.linkGroups = 0,
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
