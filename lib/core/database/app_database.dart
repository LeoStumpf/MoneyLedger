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

@DriftDatabase(tables: [Groups, Expenses, Settlements])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'money_ledger_db',
    web: kIsWeb ? DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js')) : null,
  );
}
