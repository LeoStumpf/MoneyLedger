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

/// Group membership, owned locally and replicated peer-to-peer (Phase B,
/// roomless). [groupId] is the local group id (the Groups.roomId value).
/// [status] is `active` or `removed`; [updatedAt] is a logical clock used for
/// last-writer-wins so concurrent add/remove of the same member resolves
/// deterministically.
class Members extends Table {
  TextColumn get groupId => text()();
  TextColumn get userId => text()(); // Matrix ID (@user:server)
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

@DriftDatabase(tables: [Groups, Expenses, Settlements, Members, PeerSyncStates])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 3;

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
            await customStatement(
                'UPDATE settlements SET updated_at = created_at');
          }
        },
      );
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'money_ledger_db',
    web: kIsWeb ? DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js')) : null,
  );
}
