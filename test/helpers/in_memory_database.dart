import 'package:drift/native.dart';
import 'package:money_ledger/core/database/app_database.dart';

AppDatabase openTestDatabase() => AppDatabase.forTesting(NativeDatabase.memory());
