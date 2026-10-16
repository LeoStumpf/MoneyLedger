/// Per-account ledger databases (Phase G4).
///
/// Every Matrix account signed in on this device gets its **own** Drift
/// database, so two accounts sharing a device/browser never see (or gossip)
/// each other's groups. Logout is non-destructive: signing back in as the same
/// account re-opens the same database.
///
/// Installs from before G4 kept everything in one global `money_ledger_db`.
/// The first account to open its per-account DB that plausibly **owns** that
/// legacy ledger adopts it (rows are copied in; the legacy DB is marked so it
/// is never adopted twice) — see [adoptLegacyLedger]. On a later start it is
/// deleted when no other account could still need it ([cleanupLegacyLedger],
/// G36).
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../session/app_session.dart' show localDatabaseName;
import 'app_database.dart';
import 'probe/database_probe.dart';

/// The pre-G4 single, account-agnostic database name.
const legacyDatabaseName = 'money_ledger_db';

/// AppSettings key in the **legacy** DB: the per-account DB name it was
/// adopted into. Present ⇒ never adopt again.
const legacyAdoptedIntoKey = 'legacy_adopted_into';

/// AppSettings key in a **per-account** DB: the legacy check has completed
/// (adopted, nothing to adopt, or not ours) — don't re-check on every open.
const legacyCheckedKey = 'legacy_checked';

/// AppSettings key in a **per-account** DB (G36): the legacy-DB cleanup is
/// settled — deleted or absent.
const legacyCleanupKey = 'legacy_cleanup_done';

/// AppSettings key prefix in the **legacy** DB (G18 review):
/// `legacy_checked_by:<per-account DB name>` — that account signed in after
/// the legacy ledger was adopted by another one, so it can never adopt it
/// (adoption happens once) and doesn't need it kept.
const legacyCheckedByPrefix = 'legacy_checked_by:';

/// Deterministic, filename-safe database name for [mxid]:
/// `money_ledger_<16 hex chars>`. The raw MXID never appears in a filename /
/// storage key. Uses a hand-rolled 64-bit FNV-1a variant (two seeded 32-bit
/// passes) with arithmetic that stays below 2^53, so it yields identical
/// results on the Dart VM and when compiled to JavaScript — unlike
/// `String.hashCode`, which is not stable across runs.
String accountDatabaseName(String mxid) {
  final bytes = utf8.encode(mxid);
  final h1 = _fnv1a32(bytes, 0x811c9dc5);
  final h2 = _fnv1a32(bytes, h1 ^ 0x9e3779b9);
  String hex(int h) => h.toRadixString(16).padLeft(8, '0');
  return 'money_ledger_${hex(h1)}${hex(h2)}';
}

int _fnv1a32(List<int> bytes, int basis) {
  const prime = 16777619;
  const two16 = 65536;
  const two32 = 4294967296;
  var h = basis % two32;
  for (final b in bytes) {
    h = (h ^ b) % two32;
    // h * prime mod 2^32, split into 16-bit halves so no product exceeds 2^53.
    final lo = (h % two16) * prime;
    final hi = ((h ~/ two16) * prime) % two16;
    h = (lo + hi * two16) % two32;
  }
  return h;
}

/// Whether the account [mxid] should adopt the legacy ledger.
///
/// - Already adopted by some account ([adoptedInto] set) → no.
/// - The legacy ledger has claimed Matrix accounts, but [mxid] isn't one of
///   them → no: it most likely belongs to a *different* account that used this
///   device before the upgrade (adopting it would recreate the G4 leak).
/// - Otherwise (we're a claimed member somewhere, or the ledger only contains
///   local/CSV participants so ownership can't be told) → yes.
@visibleForTesting
bool shouldAdoptLegacy({
  required String mxid,
  required Set<String> legacyClaimedMatrixIds,
  required String? adoptedInto,
}) {
  if (adoptedInto != null) return false;
  return legacyClaimedMatrixIds.isEmpty ||
      legacyClaimedMatrixIds.contains(mxid);
}

/// Opens local mode's device-local ledger (G40) — no legacy adoption (the
/// pre-G4 ledger belongs to Matrix accounts).
AppDatabase openLocalDatabase() => localLedgerFiles.open();

/// Deletes local mode's ledger files (G41) once every instance is closed —
/// after "Delete local data" and after the local ledger was adopted into an
/// account. See [LocalLedgerFiles.delete].
Future<bool> deleteLocalDatabase() => localLedgerFiles.delete();

/// The production [LocalLedgerFiles] for [localDatabaseName].
final localLedgerFiles = LocalLedgerFiles(
  open: (after) => AppDatabase.named(localDatabaseName, after: after),
  delete: () => deleteDatabase(localDatabaseName),
);

/// Local mode's ledger DB on disk (G41): opens it and deletes its files when
/// local mode ends (data deleted, or adopted into an account) — an empty
/// `money_ledger_local` must not stay behind.
///
/// Deleting is only safe on a **closed** database, so every instance [open]
/// hands out is tracked: [delete] refuses (logs, returns false) while one is
/// still open, else waits until each has finished closing and then removes
/// the files (native: `.sqlite` + `-wal` / `-shm` / `-journal`; web: every
/// stored copy, via drift's probe). An [open] during a deletion connects only
/// once the deletion is done, so starting local mode again right away gets
/// a fresh, empty DB.
class LocalLedgerFiles {
  LocalLedgerFiles({
    required AppDatabase Function(Future<void>? after) open,
    required Future<void> Function() delete,
  }) : _openDb = open,
       _deleteFiles = delete;

  final AppDatabase Function(Future<void>? after) _openDb;
  final Future<void> Function() _deleteFiles;
  final _instances = <AppDatabase>{};
  Future<void>? _deleting;

  AppDatabase open() {
    final db = _openDb(_deleting);
    _instances.add(db);
    return db;
  }

  /// Deletes the files if every instance is closed. True when deleted.
  Future<bool> delete() async {
    if (_instances.any((db) => !db.isClosed)) {
      debugPrint('[local] ledger DB still open — its files are kept');
      return false;
    }
    final closed = _instances.toList();
    _instances.removeAll(closed);
    // An open from here on waits for the deletion.
    final done = Completer<void>();
    final previous = _deleting;
    _deleting = done.future;
    try {
      await previous;
      for (final db in closed) {
        await db.close(); // idempotent: waits for the close in progress
      }
      await _deleteFiles();
      return true;
    } catch (e) {
      debugPrint('[local] deleting the local ledger DB failed: $e');
      return false;
    } finally {
      done.complete();
    }
  }
}

/// Opens the ledger DB for [mxid], adopting the legacy global ledger on first
/// open if applicable. The production `accountDatabaseOpenerProvider`.
AppDatabase openAccountDatabase(String mxid) {
  final name = accountDatabaseName(mxid);
  Future<AppDatabase?> openLegacy() async =>
      await databaseExists(legacyDatabaseName)
      ? AppDatabase.named(legacyDatabaseName)
      : null;
  return AppDatabase.named(
    name,
    onOpen: (db) async {
      // G36: a start *after* the check (adopted or not) may delete the legacy
      // DB; the adopting open itself never does (adopt now, delete next start).
      if (await cleanupLegacyLedger(
        target: db,
        openLegacy: openLegacy,
        deleteLegacy: () => deleteDatabase(legacyDatabaseName),
      )) {
        return;
      }
      await adoptLegacyLedger(
        target: db,
        targetName: name,
        mxid: mxid,
        openLegacy: openLegacy,
      );
    },
  );
}

/// G36 / G18 review: whether the legacy ledger may be deleted — it was
/// adopted ([adoptedInto] set; its rows live on in that account DB) and
/// **every** account it claimed is either the adopting one or one that has
/// signed in here since and found it already adopted ([checkedBy], the DB
/// names recorded by [adoptLegacyLedger]) — such an account can never adopt
/// it any more. An account that hasn't signed in on this device since the
/// upgrade keeps the file alive (the only copy of data it may want to
/// recover by hand); it is deleted on a later start once that account has
/// signed in once (or never, if it never does — the conservative choice).
@visibleForTesting
bool canDeleteLegacy({
  required String? adoptedInto,
  required Set<String> legacyClaimedMatrixIds,
  Set<String> checkedBy = const {},
}) =>
    adoptedInto != null &&
    legacyClaimedMatrixIds.every((m) {
      final name = accountDatabaseName(m);
      return name == adoptedInto || checkedBy.contains(name);
    });

/// G36: on an open of [target] whose legacy check already completed
/// ([legacyCheckedKey]) on an earlier start, deletes the legacy DB if
/// [canDeleteLegacy]. Marks [target] [legacyCleanupKey] once settled for good
/// (deleted or absent); a legacy DB that has to be kept for now is re-checked
/// on later starts (another account may adopt it / sign in meanwhile).
/// Returns whether [target] had completed its legacy check before (then
/// there is nothing to adopt). Never throws.
Future<bool> cleanupLegacyLedger({
  required AppDatabase target,
  required Future<AppDatabase?> Function() openLegacy,
  required Future<void> Function() deleteLegacy,
}) async {
  try {
    if (await _getSetting(target, legacyCheckedKey) == null) return false;
    if (await _getSetting(target, legacyCleanupKey) != null) return true;
    final legacy = await openLegacy();
    if (legacy == null) {
      await _setSetting(target, legacyCleanupKey, 'absent');
      return true;
    }
    final String? adoptedInto;
    final Set<String> claimed;
    final Set<String> checkedBy;
    try {
      adoptedInto = await _getSetting(legacy, legacyAdoptedIntoKey);
      claimed = await _claimedMatrixIds(legacy);
      checkedBy = await _checkedBy(legacy);
    } finally {
      await legacy.close();
    }
    if (adoptedInto == null) return true; // another account may adopt it
    if (canDeleteLegacy(
      adoptedInto: adoptedInto,
      legacyClaimedMatrixIds: claimed,
      checkedBy: checkedBy,
    )) {
      await deleteLegacy();
      debugPrint('[db] deleted the adopted legacy ledger');
      await _setSetting(target, legacyCleanupKey, 'deleted');
    } else {
      // Re-checked on the next start (an account claimed in it may sign in).
      debugPrint('[db] legacy ledger kept: other accounts are claimed in it');
    }
    return true;
  } catch (e) {
    debugPrint('[db] legacy ledger cleanup failed (will retry): $e');
    return true;
  }
}

Future<Set<String>> _checkedBy(AppDatabase db) async =>
    (await (db.select(
          db.appSettings,
        )..where((t) => t.key.like('$legacyCheckedByPrefix%'))).get())
        .map((r) => r.key.substring(legacyCheckedByPrefix.length))
        .toSet();

Future<Set<String>> _claimedMatrixIds(AppDatabase db) async =>
    (await db
            .customSelect(
              'SELECT DISTINCT matrix_id FROM members '
              'WHERE matrix_id IS NOT NULL',
            )
            .get())
        .map((r) => r.read<String>('matrix_id'))
        .toSet();

/// One-time migration of the pre-G4 global ledger into [target] (the freshly
/// opened per-account DB for [mxid]). Runs from `beforeOpen`, so [target] is
/// usable but the call must not throw (a failure is logged and retried on the
/// next open, because [legacyCheckedKey] is only written on completion).
///
/// Idempotent and crash-safe: rows are copied with `INSERT OR IGNORE` inside a
/// transaction (never clobbering anything already in [target]), then the legacy
/// DB is marked [legacyAdoptedIntoKey], then [target] is marked
/// [legacyCheckedKey]. The legacy DB itself is left in place here — it is
/// deleted on a **later** start by [cleanupLegacyLedger] (G36) once no other
/// account could need it; it's never adopted again.
///
/// [openLegacy] returns `null` when no legacy DB exists (checked without
/// creating one). Returns whether rows were adopted.
Future<bool> adoptLegacyLedger({
  required AppDatabase target,
  required String targetName,
  required String mxid,
  required Future<AppDatabase?> Function() openLegacy,
}) async {
  try {
    if (await _getSetting(target, legacyCheckedKey) != null) return false;

    final legacy = await openLegacy();
    var adopted = false;
    if (legacy != null) {
      try {
        final claimed = await _claimedMatrixIds(legacy);
        final adoptedInto = await _getSetting(legacy, legacyAdoptedIntoKey);
        if (shouldAdoptLegacy(
          mxid: mxid,
          legacyClaimedMatrixIds: claimed,
          adoptedInto: adoptedInto,
        )) {
          await _copyAll(from: legacy, to: target);
          await _setSetting(legacy, legacyAdoptedIntoKey, targetName);
          adopted = true;
          debugPrint('[db] adopted legacy ledger into $targetName');
        } else if (adoptedInto != null) {
          // G18 review: we can never adopt it (adopted once already) — tell
          // the cleanup this account doesn't need it kept.
          await _setSetting(legacy, '$legacyCheckedByPrefix$targetName', '1');
        }
      } finally {
        await legacy.close();
      }
    }
    await _setSetting(target, legacyCheckedKey, 'true');
    return adopted;
  } catch (e, st) {
    debugPrint('[db] legacy ledger adoption failed (will retry): $e\n$st');
    return false;
  }
}

Future<void> _copyAll({
  required AppDatabase from,
  required AppDatabase to,
}) async {
  final groups = await from.select(from.groups).get();
  final members = await from.select(from.members).get();
  final expenses = await from.select(from.expenses).get();
  final settlements = await from.select(from.settlements).get();
  final syncStates = await from.select(from.peerSyncStates).get();
  final settings = (await from.select(from.appSettings).get())
      .where(
        (s) =>
            s.key != legacyAdoptedIntoKey &&
            s.key != legacyCheckedKey &&
            !s.key.startsWith(legacyCheckedByPrefix),
      )
      .toList();
  await to.transaction(() async {
    await to.batch((b) {
      const mode = InsertMode.insertOrIgnore;
      b.insertAll(to.groups, groups, mode: mode);
      b.insertAll(to.members, members, mode: mode);
      b.insertAll(to.expenses, expenses, mode: mode);
      b.insertAll(to.settlements, settlements, mode: mode);
      b.insertAll(to.peerSyncStates, syncStates, mode: mode);
      b.insertAll(to.appSettings, settings, mode: mode);
    });
  });
}

Future<String?> _getSetting(AppDatabase db, String key) async =>
    (await (db.select(
      db.appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

Future<void> _setSetting(AppDatabase db, String key, String value) => db
    .into(db.appSettings)
    .insertOnConflictUpdate(
      AppSettingsCompanion(key: Value(key), value: Value(value)),
    );

/// Executor behind `appDatabaseProvider` while **signed out**: opens no
/// storage at all, every read returns no rows, every write fails. Keeps the
/// provider non-nullable for its many synchronous consumers; a widget still
/// mounted during the logout transition simply sees an empty ledger, never
/// another account's data.
class SignedOutExecutor extends QueryExecutor {
  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => true;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) async => const [];

  Never _deny() =>
      throw StateError('No Matrix account signed in: no ledger database');

  @override
  Future<int> runInsert(String statement, List<Object?> args) async => _deny();
  @override
  Future<int> runUpdate(String statement, List<Object?> args) async => _deny();
  @override
  Future<int> runDelete(String statement, List<Object?> args) async => _deny();
  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) async =>
      _deny();
  @override
  Future<void> runBatched(BatchedStatements statements) async => _deny();
  @override
  TransactionExecutor beginTransaction() => _deny();
  @override
  QueryExecutor beginExclusive() => _deny();
}
