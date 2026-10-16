import 'package:drift/native.dart';
import 'package:money_ledger/core/database/app_database.dart';

AppDatabase openTestDatabase() =>
    AppDatabase.forTesting(NativeDatabase.memory());

/// In-memory DB whose drift `beforeOpen` runs [onOpen] (e.g. legacy adoption).
AppDatabase openTestDatabaseWithHook(
  Future<void> Function(AppDatabase db) onOpen,
) => AppDatabase.forTesting(NativeDatabase.memory(), onOpen: onOpen);
