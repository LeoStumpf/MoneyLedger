/// G40: moving local mode's ledger into a Matrix account ("Connect a Matrix
/// account").
///
/// Like the G4 legacy adoption, the rows are copied from one ledger DB into
/// the account's — but by **LWW upsert** (the DAOs' merge), so an account that
/// already holds some of these groups (e.g. from a restored backup) merges
/// instead of duplicating. On the way:
///  * the user's own participant in each group — claimed by local mode's
///    pseudo account [kLocalAccountId] — is re-claimed by the new MXID (a new
///    LWW version), so the user is that group's active, claimed member and
///    the group syncs to their other devices / can invite members (G18);
///  * every row local mode couldn't sign (no device key) is marked
///    `pendingSign` and then **signed by the account's device** (expenses and
///    payments also get their creation statement, "added by") — peers refuse
///    unsigned versions (G6), so without this an adopted group could never
///    be relayed.
///
/// Afterwards the local DB is wiped and (G41) its files deleted — local mode
/// would start empty again — and the device preferences say where the data
/// went. A backup made in local mode gets the same treatment when it is
/// restored into an account ([reclaimGroupInPlace], `BackupService.restore`).
library;

import 'dart:async';

import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/expenses/expenses_provider.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../database/app_database.dart';
import '../database/daos/expenses_dao.dart';
import '../database/daos/groups_dao.dart';
import '../database/daos/members_dao.dart';
import '../database/daos/settings_dao.dart';
import '../matrix/record_crypto.dart';
import '../matrix/transport_provider.dart';
import '../sync/pending_signer.dart';
import '../sync/sync_engine.dart';
import 'app_session.dart';
import 'device_prefs.dart';

/// What one adoption did.
class LocalAdoptionResult {
  /// The adopted group ids.
  final List<String> groupIds;

  /// Rows signed by the account's device right away.
  final int signed;

  /// Whether every adopted row is signed now. False when the device key
  /// wasn't ready in time — the sync engine signs the rest before the first
  /// digest (without "added by" for records edited in local mode).
  final bool allSigned;

  const LocalAdoptionResult({
    required this.groupIds,
    required this.signed,
    required this.allSigned,
  });

  static const nothing = LocalAdoptionResult(
    groupIds: [],
    signed: 0,
    allSigned: true,
  );
}

/// Copies every group of [local] into [target] (LWW merge), re-claims the
/// local pseudo account's participants for [mxid], marks unsigned rows
/// `pendingSign`, signs them with [crypto] (when it has an identity) and
/// wipes [local]. Idempotent: re-running after a crash merges the same
/// versions again. [isAlive] stops it when [target] closes (account switch).
Future<LocalAdoptionResult> adoptLocalLedger({
  required AppDatabase target,
  required AppDatabase local,
  required String mxid,
  required RecordCrypto? crypto,
  bool Function()? isAlive,
}) async {
  bool alive() => !target.isClosed && (isAlive?.call() ?? true);
  final from = (
    groups: GroupsDao(local),
    members: MembersDao(local),
    expenses: ExpensesDao(local),
    settings: SettingsDao(local),
  );
  final to = (
    groups: GroupsDao(target),
    members: MembersDao(target),
    expenses: ExpensesDao(target),
    settings: SettingsDao(target),
  );
  final groups = await from.groups.getAllGroups();
  final archives = await from.settings.watchArchivedGroups().first;
  final keys = await local.select(local.knownDeviceKeys).get();
  if (!alive()) return LocalAdoptionResult.nothing;

  await target.transaction(() async {
    for (final g in groups) {
      await to.groups.upsertGroupLww(groupCompanion(_groupToSign(g)));
      for (final m in await from.members.getMembers(g.roomId)) {
        await to.members.upsertMemberLww(
          memberCompanion(adoptedMember(m, mxid)),
        );
      }
      for (final e in await from.expenses.getAllExpensesForGroup(g.roomId)) {
        await to.expenses.upsertExpenseLww(expenseCompanion(_expenseToSign(e)));
      }
      for (final s in await from.expenses.getAllSettlementsForGroup(g.roomId)) {
        await to.expenses.upsertSettlementLww(
          settlementCompanion(_settlementToSign(s)),
        );
      }
      final archive = archives[g.roomId];
      if (archive != null) await to.settings.archiveGroup(g.roomId, archive);
    }
    // Device keys vouched for by backups restored in local mode.
    await target.batch(
      (b) => b.insertAll(
        target.knownDeviceKeys,
        keys,
        mode: InsertMode.insertOrIgnore,
      ),
    );
  });

  final ids = [for (final g in groups) g.roomId];
  final signed = await signAdoptedGroups(
    crypto: crypto,
    groups: to.groups,
    members: to.members,
    expenses: to.expenses,
    groupIds: ids,
    isAlive: alive,
  );
  if (!alive()) return LocalAdoptionResult.nothing;
  // Everything lives in the account DB now — local mode starts empty again.
  await local.wipeAll();
  return LocalAdoptionResult(
    groupIds: ids,
    signed: signed ?? 0,
    allSigned: signed != null || ids.isEmpty,
  );
}

/// Signs the adopted groups' `pendingSign` rows with [crypto] — creation
/// statements included ("added by", `originIfMissing`): local mode never
/// signed anything. Returns the number of rows signed, or null when
/// [crypto] has no device key yet (the sync engine signs them before the
/// first digest, without "added by" for records edited in local mode).
/// Shared by "Connect a Matrix account" and restoring a local-mode backup
/// into an account (G41).
Future<int?> signAdoptedGroups({
  required RecordCrypto? crypto,
  required GroupsDao groups,
  required MembersDao members,
  required ExpensesDao expenses,
  required Iterable<String> groupIds,
  required bool Function() isAlive,
}) async {
  if (crypto == null || crypto.identity == null) return null;
  var signed = 0;
  for (final id in groupIds) {
    if (!isAlive()) break;
    signed += await signPendingRows(
      crypto: crypto,
      groups: groups,
      members: members,
      expenses: expenses,
      groupId: id,
      isAlive: isAlive,
      originIfMissing: true,
    );
  }
  return signed;
}

/// G41: the adoption step for a group that is **already** in the DB behind
/// the DAOs — restored from a backup — instead of copied from the local
/// ledger: every participant claimed by [from] becomes claimed by [to]
/// ([reclaimedMember]); with [signLater], every unsigned row of the group is
/// marked `pendingSign` as well (for [signAdoptedGroups]).
///
/// * Restoring a **local-mode backup into a Matrix account**: [from] =
///   [kLocalAccountId], [to] = the MXID, [signLater] — the same result as
///   "Connect a Matrix account" ([adoptLocalLedger]).
/// * Restoring a **Matrix backup in local mode**: [from] = the backup's
///   account, [to] = [kLocalAccountId], no [signLater] (nothing can be
///   signed here; connecting an account later adopts as usual).
///
/// A participant isn't re-claimed when [to] already claims an active one in
/// the group (no second "me"). Run it inside the restore's transaction.
/// Returns whether a participant was re-claimed.
Future<bool> reclaimGroupInPlace({
  required GroupsDao groups,
  required MembersDao members,
  required ExpensesDao expenses,
  required String groupId,
  required String from,
  required String to,
  required bool signLater,
}) async {
  var reclaimed = false;
  final all = await members.getMembers(groupId);
  final mine = claimedBy(all, to);
  final mayReclaim = mine == null || !mine.isActive;
  for (final m in all) {
    if (mayReclaim && m.matrixId == from) {
      await members.upsertMemberLww(
        memberCompanion(reclaimedMember(m, from: from, to: to)),
      );
      reclaimed = true;
    } else if (signLater && m.sig == null && !m.pendingSign) {
      await members.upsertMemberLww(
        memberCompanion(m.withSigning(pendingSign: true)),
      );
    }
  }
  if (!signLater) return reclaimed;
  final g = await groups.getGroup(groupId);
  if (g != null && g.sig == null && !g.pendingSign) {
    await groups.upsertGroupLww(groupCompanion(_groupToSign(g)));
  }
  for (final e in await expenses.getAllExpensesForGroup(groupId)) {
    if (e.sig == null && !e.pendingSign) {
      await expenses.upsertExpenseLww(expenseCompanion(_expenseToSign(e)));
    }
  }
  for (final st in await expenses.getAllSettlementsForGroup(groupId)) {
    if (st.sig == null && !st.pendingSign) {
      await expenses.upsertSettlementLww(
        settlementCompanion(_settlementToSign(st)),
      );
    }
  }
  return reclaimed;
}

// Unsigned versions wait for the adopting account's signature (same clock:
// the signed copy is the same G27 version).
GroupModel _groupToSign(GroupModel g) =>
    g.sig == null ? g.withSigning(pendingSign: true) : g;

ExpenseModel _expenseToSign(ExpenseModel e) =>
    e.sig == null ? e.withSigning(origin: e.origin, pendingSign: true) : e;

SettlementModel _settlementToSign(SettlementModel s) =>
    s.sig == null ? s.withSigning(origin: s.origin, pendingSign: true) : s;

/// [m] as adopted into [mxid]'s account: the participant claimed by local
/// mode's pseudo account becomes claimed by [mxid] (a new LWW version — it
/// beats the local one everywhere); unsigned versions wait for the account's
/// signature.
@visibleForTesting
MemberModel adoptedMember(MemberModel m, String mxid) {
  if (isLocalAccountId(m.matrixId)) {
    return reclaimedMember(m, from: kLocalAccountId, to: mxid);
  }
  return m.sig == null ? m.withSigning(pendingSign: true) : m;
}

/// [m] with its claim moved from account [from] to [to] (G40 / G41): the same
/// participant (id, name, status — history untouched), a new LWW version
/// ([nextLwwClock], it beats the old claim everywhere) that waits for a
/// signature. Any other participant is returned unchanged.
MemberModel reclaimedMember(
  MemberModel m, {
  required String from,
  required String to,
}) {
  if (m.matrixId != from) return m;
  return MemberModel(
    groupId: m.groupId,
    userId: m.userId,
    displayName: m.displayName,
    matrixId: to,
    status: m.status,
    updatedAt: nextLwwClock(m.updatedAt),
    pendingSign: true,
  );
}

/// How long the adoption waits for the new device's signing key (normally
/// ready right after sign-in) before leaving the signing to the sync engine.
final localAdoptionKeyWaitProvider = Provider<Duration>(
  (_) => const Duration(seconds: 30),
);

/// The last finished adoption on this device (for the groups page notice);
/// null = none in this run.
final localAdoptionResultProvider =
    NotifierProvider<LocalAdoptionResultNotifier, LocalAdoptionResult?>(
      LocalAdoptionResultNotifier.new,
    );

class LocalAdoptionResultNotifier extends Notifier<LocalAdoptionResult?> {
  @override
  LocalAdoptionResult? build() => null;

  void report(LocalAdoptionResult? r) {
    if (ref.mounted) state = r;
  }
}

/// Runs the pending adoption (device prefs `adoptInto` == the signed-in
/// account) once that account's DB is open. Watched app-wide by
/// `LedgerSyncHost`. Never throws; a failure is logged and retried on the
/// next start (the preference stays).
final localLedgerAdoptionProvider = Provider<void>((ref) {
  final adoptInto = ref.watch(
    devicePrefsProvider.select((p) => p.value?.adoptInto),
  );
  final mxid = ref.watch(accountUserIdProvider);
  if (adoptInto == null || mxid == null || adoptInto != mxid) return;
  if (ref.watch(localModeActiveProvider)) return;
  final db = ref.watch(appDatabaseProvider);
  if (db.isSignedOutPlaceholder || db.isClosed) return;

  // Captured before the first await (G19).
  final openLocal = ref.read(localDatabaseOpenerProvider);
  final deleteLocal = ref.read(localDatabaseDeleterProvider);
  final transport = ref.read(ledgerTransportProvider.future)..ignore();
  final keyWait = ref.read(localAdoptionKeyWaitProvider);
  final prefs = ref.read(devicePrefsProvider.notifier);
  final results = ref.read(localAdoptionResultProvider.notifier);
  final engine = ref.read(syncEngineProvider);
  var disposed = false;
  ref.onDispose(() => disposed = true);
  bool alive() => !disposed && !db.isClosed;

  Future<RecordCrypto?> waitForKey() async {
    final deadline = DateTime.now().add(keyWait);
    try {
      final c = (await transport.timeout(keyWait)).crypto;
      while (c.identity == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!alive()) return null;
      }
      return c.identity == null ? null : c;
    } catch (_) {
      return null;
    }
  }

  Future<void> run() async {
    final local = openLocal();
    var adopted = false;
    try {
      final crypto = await waitForKey();
      if (!alive()) return;
      final r = await adoptLocalLedger(
        target: db,
        local: local,
        mxid: mxid,
        crypto: crypto,
        isAlive: alive,
      );
      if (!alive()) return;
      debugPrint(
        '[local] adopted ${r.groupIds.length} local group(s) into $mxid '
        '(${r.signed} rows signed${r.allSigned ? '' : ', rest pending'})',
      );
      await prefs.finishLocalAdoption(mxid);
      adopted = true;
      results.report(r);
      // Our other devices learn the groups from the digest (unknown group →
      // resync), invitees later through the normal invite flow.
      for (final id in r.groupIds) {
        engine.pokeGroup(id);
      }
    } catch (e, st) {
      if (alive()) debugPrint('[local] adoption failed (will retry): $e\n$st');
    } finally {
      await local.close();
    }
    // G41: the (now empty) local ledger's files go too — once closed.
    if (adopted) await deleteLocal();
  }

  unawaited(run());
});
