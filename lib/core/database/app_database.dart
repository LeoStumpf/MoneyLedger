import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

part 'app_database.g.dart';

class Groups extends Table {
  TextColumn get roomId => text()();
  TextColumn get name => text()();
  TextColumn get currency => text().withDefault(const Constant('EUR'))();
  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0))(); // ms epoch, LWW clock

  @override
  Set<Column> get primaryKey => {roomId};
}

class Expenses extends Table {
  TextColumn get id => text()(); // UUIDv7
  TextColumn get roomId => text()();
  TextColumn get matrixEventId => text().nullable()();
  TextColumn get description => text()();
  IntColumn get amountCents => integer()();
  TextColumn get currency => text()();
  TextColumn get paidBy => text()(); // Matrix user ID (@user:server)
  TextColumn get splitsJson => text()(); // JSON: {"@user:server": cents}
  IntColumn get createdAt => integer()(); // ms epoch
  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0))(); // ms epoch, LWW clock
  // Tombstone: deleted records are kept forever so anti-entropy can never
  // resurrect them on another device.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Settlements extends Table {
  TextColumn get id => text()(); // UUIDv7
  TextColumn get roomId => text()();
  TextColumn get matrixEventId => text().nullable()();
  IntColumn get amountCents => integer()();
  TextColumn get currency => text()();
  TextColumn get fromUser => text()();
  TextColumn get toUser => text()();
  IntColumn get createdAt => integer()(); // ms epoch
  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0))(); // ms epoch, LWW clock
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Group membership / participants, owned locally and replicated peer-to-peer
/// (Phase B roomless; virtual users in this phase). [groupId] is the local group
/// id (the Groups.roomId value). [status] is `active` or `removed`; [updatedAt]
/// is a logical clock used for last-writer-wins so concurrent add/remove of the
/// same participant resolves deterministically.
///
/// [userId] is the **stable participant id** — a per-group identity that is NOT
/// necessarily a Matrix ID. For participants migrated from before virtual users
/// (and for participants created from a real account) it equals the MXID; for a
/// Tricount-style local participant it is a fresh UUID. The Matrix account a
/// participant is "claimed" by, if any, lives in [matrixId] (null = pure-local).
/// Replication targets only participants with a non-null [matrixId].
class Members extends Table {
  TextColumn get groupId => text()();
  TextColumn get userId => text()(); // stable participant id (see class doc)
  TextColumn get displayName => text().withDefault(const Constant(''))();
  TextColumn get matrixId => text().nullable()(); // claimed account, or null
  TextColumn get status => text().withDefault(const Constant('active'))();
  IntColumn get updatedAt => integer()(); // ms epoch, LWW clock

  @override
  Set<Column> get primaryKey => {groupId, userId};
}

/// Per-peer sync bookkeeping for the anti-entropy digest exchange (Phase C).
/// [lastInSyncAt] is the last time a digest from [userId] matched our local
/// state exactly for [groupId]; it backs the sync-status UI.
class PeerSyncStates extends Table {
  TextColumn get groupId => text()();
  TextColumn get userId => text()(); // Matrix ID (@user:server)
  IntColumn get lastInSyncAt => integer().withDefault(const Constant(0))();
  IntColumn get lastDigestSentAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {groupId, userId};
}

/// Device-local key/value flags (e.g. whether onboarding has been seen). Purely
/// local — never replicated; only the ledger record types sync over to-device.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [Groups, Expenses, Settlements, Members, PeerSyncStates, AppSettings],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the on-device database file/store called [name] (per-account ledger
  /// DBs are named via `accountDatabaseName` — see `account_database.dart`).
  /// [onOpen] runs once per open, after migrations, inside drift's
  /// `beforeOpen` (used to adopt the pre-per-account legacy ledger).
  AppDatabase.named(String name, {this.onOpen})
    : isSignedOutPlaceholder = false,
      super(openNamedConnection(name));

  /// Wraps an arbitrary executor (in-memory / temp-file DBs in tests).
  AppDatabase.forTesting(super.e, {this.onOpen})
    : isSignedOutPlaceholder = false;

  /// The storage-less placeholder behind `appDatabaseProvider` while signed
  /// out (executor: `SignedOutExecutor`).
  AppDatabase.signedOut(super.e) : onOpen = null, isSignedOutPlaceholder = true;

  /// True for the signed-out placeholder: there is no account, so sync
  /// components (SyncEngine / LedgerSyncer) must not start against it — an
  /// engine on the always-empty placeholder would e.g. send a spurious
  /// "new device" `resync_request` (G24).
  final bool isSignedOutPlaceholder;

  /// Hook run after migrations on every open — see [AppDatabase.named].
  final Future<void> Function(AppDatabase db)? onOpen;

  bool _closed = false;

  /// Whether [close] has been called. Long-running async work (SyncEngine,
  /// LedgerSyncer, replication) checks this after each await: on an account
  /// switch (G4) the previous account's DB is closed *before* the providers
  /// that captured it are disposed, and any further query on it would throw
  /// "Can't re-open a database after closing it".
  bool get isClosed => _closed;

  @override
  Future<void> close() {
    _closed = true;
    return super.close();
  }

  /// Removes every local row of [groupId] — group meta, participants,
  /// expenses, settlements (tombstones included) and peer sync bookkeeping —
  /// in one transaction (G9 leave / delete). Device-local: nothing is sent.
  Future<void> purgeGroup(String groupId) => transaction(() async {
    await (delete(groups)..where((t) => t.roomId.equals(groupId))).go();
    await (delete(members)..where((t) => t.groupId.equals(groupId))).go();
    await (delete(expenses)..where((t) => t.roomId.equals(groupId))).go();
    await (delete(settlements)..where((t) => t.roomId.equals(groupId))).go();
    await (delete(
      peerSyncStates,
    )..where((t) => t.groupId.equals(groupId))).go();
  });

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // v2 (Phase B): add the local membership table. Existing
      // groups/expenses/settlements are left untouched (clean-slate move to
      // roomless — old room-based groups simply stop syncing).
      if (from < 2) {
        await m.createTable(members);
      }
      // v3 (Phase C): per-record LWW clocks + tombstones for edit/delete
      // and digest anti-entropy, plus per-peer sync bookkeeping.
      if (from < 3) {
        await m.addColumn(groups, groups.updatedAt);
        await m.addColumn(expenses, expenses.updatedAt);
        await m.addColumn(expenses, expenses.deleted);
        await m.addColumn(settlements, settlements.updatedAt);
        await m.addColumn(settlements, settlements.deleted);
        await m.createTable(peerSyncStates);
        await customStatement('UPDATE expenses SET updated_at = created_at');
        await customStatement('UPDATE settlements SET updated_at = created_at');
      }
      // v4 (virtual users): participants gain a display name and an optional
      // Matrix-account claim. Existing rows were created from real accounts,
      // so their userId already IS the MXID — backfill matrixId from it and
      // derive a display name from the localpart. Non-destructive: userId
      // (the participant id) is untouched, so all expense/settlement
      // references stay valid.
      if (from < 4) {
        await m.addColumn(members, members.displayName);
        await m.addColumn(members, members.matrixId);
        await customStatement('UPDATE members SET matrix_id = user_id');
        // localpart of @local:server → strip leading '@' up to the ':'
        await customStatement(
          "UPDATE members SET display_name = "
          "substr(user_id, 2, instr(user_id, ':') - 2) "
          "WHERE user_id LIKE '@%:%'",
        );
        await customStatement(
          "UPDATE members SET display_name = user_id "
          "WHERE user_id NOT LIKE '@%:%'",
        );
      }
      // v5 (Phase F): device-local settings (onboarding-seen flag).
      if (from < 5) {
        await m.createTable(appSettings);
      }
    },
    beforeOpen: (_) async {
      final hook = onOpen;
      if (hook != null) await hook(this);
    },
  );
}

/// The platform executor for the database called [name]: a `<name>.sqlite`
/// file in the app documents dir on native, OPFS/IndexedDB on web
/// (drift_flutter picks the best available web storage).
QueryExecutor openNamedConnection(String name) {
  return driftDatabase(
    name: name,
    web: kIsWeb
        ? DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          )
        : null,
  );
}
