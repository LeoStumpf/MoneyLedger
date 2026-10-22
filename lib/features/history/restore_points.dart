import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/account_database.dart' show accountDatabaseName;
import '../../core/database/app_database.dart';
import '../../core/database/daos/history_dao.dart';
import '../../core/session/app_session.dart';
import '../backup/backup_service.dart';
import '../backup/ledger_backup.dart';
import '../expenses/expenses_provider.dart';
import 'snapshot_policy.dart';
import 'snapshot_store.dart';

/// One on-device snapshot as listed on the restore-points page.
class RestorePoint {
  const RestorePoint({
    required this.name,
    required this.day,
    required this.exportedAt,
    required this.groups,
    required this.records,
  });

  /// The file name in the store (`YYYY-MM-DD.json`).
  final String name;
  final DateTime day;

  /// When it was taken (null if the file doesn't say).
  final int? exportedAt;
  final int groups;

  /// Live expenses + payments in it.
  final int records;
}

/// G48 restore points: the daily maintenance (history pruning + rotating
/// snapshot) and reading the snapshots back.
///
/// Everything is captured at construction (G19); each step checks that the
/// DB is still open.
class RestorePointsService {
  RestorePointsService({
    required this.db,
    required this.history,
    required this.backup,
    required this.store,
    required this.account,
  });

  final AppDatabase db;
  final HistoryDao history;
  final BackupService backup;

  /// Null on web / in the demo: no snapshots.
  final SnapshotStore? store;

  /// The backup's `account` (the MXID, or `local:self` in local mode).
  final String? account;

  bool get _alive => !db.isClosed;

  /// Runs once per app start / DB open: prunes the version history
  /// ([HistoryDao.prune]), then — at most once per day — writes a snapshot
  /// of the whole ledger if it changed since the last one, and rotates the
  /// old ones ([snapshotsToKeep]). Never throws (logged).
  Future<void> maintain({DateTime? now}) async {
    final t = now ?? DateTime.now();
    try {
      final pruned = await history.prune(now: t.millisecondsSinceEpoch);
      if (pruned > 0) debugPrint('[history] pruned $pruned old versions');
      if (!_alive) return;
      await snapshotIfDue(t);
    } catch (e) {
      if (_alive) debugPrint('[history] maintenance failed: $e');
    }
  }

  /// The daily snapshot step of [maintain] (also run at the end of an
  /// Android background round, G58). Returns whether a file was written.
  ///
  /// [cancelled] (G58: the background round was stopped) is checked between
  /// the steps — once it says true nothing more is written. The file itself
  /// is written atomically ([SnapshotStore.write]: temp file + rename), so
  /// an interrupted snapshot never leaves a half-written `YYYY-MM-DD.json`.
  Future<bool> snapshotIfDue(DateTime now, {bool Function()? cancelled}) async {
    final s = store;
    if (s == null) return false;
    bool go() => _alive && !(cancelled?.call() ?? false);
    final day = snapshotDayKey(now);
    if (!snapshotCheckDue(await history.snapshotCheckedDay(), now)) {
      return false;
    }
    if (!go()) return false;
    // A fixed `exported_at` → the text only changes with the ledger.
    final json = await backup.exportJson(account: account, now: 0);
    if (!go()) return false;
    final fingerprint = sha256.convert(utf8.encode(json)).toString();
    if (fingerprint == await history.snapshotFingerprint()) {
      await history.markSnapshotChecked(day);
      return false;
    }
    if (!go()) return false;
    final groups = (jsonDecode(json) as Map<String, dynamic>)['groups'] as List;
    if (groups.isEmpty) {
      // Nothing to protect (yet) — no empty snapshots. The day is NOT
      // marked checked (G58, DEV-J): a group created later today gets its
      // first restore point at the next start / background round today.
      return false;
    }
    await s.write(
      snapshotFileName(now),
      json.replaceFirst(
        '"exported_at": 0,',
        '"exported_at": ${now.millisecondsSinceEpoch},',
      ),
    );
    // Written: rotate + record it even if stopped meanwhile (both quick; an
    // unrecorded file would only be rewritten tomorrow).
    await _rotate(s);
    if (_alive) {
      await history.markSnapshotChecked(day, fingerprint: fingerprint);
    }
    return true;
  }

  Future<void> _rotate(SnapshotStore s) async {
    final days = <DateTime, String>{};
    for (final name in await s.list()) {
      final d = parseSnapshotFileName(name);
      if (d != null) {
        days[d] = name;
      } else if (name.endsWith('.json.tmp')) {
        // G58: a write cut off before its rename (the process was killed).
        // Writers never overlap (app and background round hold the gate),
        // so a temp file seen after our own write is a leftover.
        await s.delete(name);
      }
    }
    final keep = snapshotsToKeep(days.keys);
    for (final MapEntry(key: d, value: name) in days.entries) {
      if (!keep.contains(d)) await s.delete(name);
    }
  }

  /// The snapshots in the store, newest first (unreadable files skipped).
  Future<List<RestorePoint>> list() async {
    final s = store;
    if (s == null) return const [];
    final out = <RestorePoint>[];
    for (final name in await s.list()) {
      final day = parseSnapshotFileName(name);
      if (day == null) continue;
      try {
        final b = parseBackup(await s.read(name));
        var records = 0;
        for (final g in b.groups) {
          final sum = summarizeBackupGroup(g);
          records += sum.expenseCount + sum.settlementCount;
        }
        out.add(
          RestorePoint(
            name: name,
            day: day,
            exportedAt: b.exportedAt,
            groups: b.groups.length,
            records: records,
          ),
        );
      } catch (e) {
        debugPrint('[history] snapshot $name unreadable: $e');
      }
    }
    out.sort((a, b) => b.day.compareTo(a.day));
    return out;
  }

  /// The parsed snapshot [name] — restored through the normal backup path.
  Future<LedgerBackup> read(String name) async =>
      parseBackup(await store!.read(name));
}

/// The ledger DB name of [identity] (an MXID or `local:self`).
String ledgerDatabaseName(String identity) => isLocalAccountId(identity)
    ? localDatabaseName
    : accountDatabaseName(identity);

/// A [RestorePointsService] for [db] (the ledger of [identity]).
RestorePointsService _service(Ref ref, AppDatabase db, String? identity) =>
    RestorePointsService(
      db: db,
      history: HistoryDao(db),
      backup: ref.read(backupServiceProvider),
      store: identity == null || db.isSignedOutPlaceholder
          ? null
          : ref.read(snapshotStoreFactoryProvider)(
              ledgerDatabaseName(identity),
            ),
      account: identity,
    );

/// The [RestorePointsService] of the current ledger DB.
final restorePointsServiceProvider = Provider.autoDispose<RestorePointsService>(
  (ref) => _service(
    ref,
    ref.watch(appDatabaseProvider),
    ref.watch(ledgerIdentityProvider),
  ),
);

/// The snapshots of the current ledger DB (the restore-points page).
final restorePointsProvider = FutureProvider.autoDispose<List<RestorePoint>>(
  (ref) => ref.watch(restorePointsServiceProvider).list(),
);

/// Whether this platform keeps snapshots (false on web / in the demo).
final snapshotsSupportedProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(restorePointsServiceProvider).store != null,
);

/// Runs [RestorePointsService.maintain] once per ledger DB open (watched by
/// `LedgerSyncHost`). Signed out: nothing.
final restorePointsMaintenanceProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  final db = ref.watch(appDatabaseProvider);
  final id = ref.watch(ledgerIdentityProvider);
  if (db.isSignedOutPlaceholder || id == null) return;
  await _service(ref, db, id).maintain();
});
