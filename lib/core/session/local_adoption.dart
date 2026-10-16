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
/// Afterwards the local DB is wiped (local mode would start empty again) and
/// the device preferences say where the data went.
library;

import 'dart:async';

import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/expenses/expenses_provider.dart';
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
      await to.groups.upsertGroupLww(
        groupCompanion(g.sig == null ? g.withSigning(pendingSign: true) : g),
      );
      for (final m in await from.members.getMembers(g.roomId)) {
        await to.members.upsertMemberLww(
          memberCompanion(adoptedMember(m, mxid)),
        );
      }
      for (final e in await from.expenses.getAllExpensesForGroup(g.roomId)) {
        await to.expenses.upsertExpenseLww(
          expenseCompanion(
            e.sig == null
                ? e.withSigning(origin: e.origin, pendingSign: true)
                : e,
          ),
        );
      }
      for (final s in await from.expenses.getAllSettlementsForGroup(g.roomId)) {
        await to.expenses.upsertSettlementLww(
          settlementCompanion(
            s.sig == null
                ? s.withSigning(origin: s.origin, pendingSign: true)
                : s,
          ),
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

  var signed = 0;
  var allSigned = true;
  final ids = [for (final g in groups) g.roomId];
  if (crypto != null && crypto.identity != null) {
    for (final id in ids) {
      if (!alive()) break;
      signed += await signPendingRows(
        crypto: crypto,
        groups: to.groups,
        members: to.members,
        expenses: to.expenses,
        groupId: id,
        isAlive: alive,
        originIfMissing: true,
      );
    }
  } else {
    allSigned = ids.isEmpty;
  }
  if (!alive()) return LocalAdoptionResult.nothing;
  // Everything lives in the account DB now — local mode starts empty again.
  await local.wipeAll();
  return LocalAdoptionResult(
    groupIds: ids,
    signed: signed,
    allSigned: allSigned,
  );
}

/// [m] as adopted into [mxid]'s account: the participant claimed by local
/// mode's pseudo account becomes claimed by [mxid] (a new LWW version — it
/// beats the local one everywhere); unsigned versions wait for the account's
/// signature.
@visibleForTesting
MemberModel adoptedMember(MemberModel m, String mxid) {
  if (isLocalAccountId(m.matrixId)) {
    return MemberModel(
      groupId: m.groupId,
      userId: m.userId,
      displayName: m.displayName,
      matrixId: mxid,
      status: m.status,
      updatedAt: nextLwwClock(m.updatedAt),
      pendingSign: true,
    );
  }
  return m.sig == null ? m.withSigning(pendingSign: true) : m;
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
  }

  unawaited(run());
});
