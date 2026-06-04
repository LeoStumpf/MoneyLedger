import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

part 'app_database.g.dart';

class Groups extends Table {
  TextColumn get roomId => text()();
  TextColumn get name => text()();
  TextColumn get currency => text().withDefault(const Constant('EUR'))();

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

@DriftDatabase(tables: [Groups, Expenses, Settlements, Members])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

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
        },
      );
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'money_ledger_db',
    web: kIsWeb ? DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js')) : null,
  );
}
