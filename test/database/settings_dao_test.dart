/// SettingsDao (Phase F, M5): the device-local onboarding-seen flag.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';

import '../helpers/in_memory_database.dart';

void main() {
  late AppDatabase db;
  late SettingsDao dao;
  setUp(() {
    db = openTestDatabase();
    dao = SettingsDao(db);
  });
  tearDown(() => db.close());

  test('onboarding starts unseen', () async {
    expect(await dao.watchOnboardingSeen().first, isFalse);
  });

  test('markOnboardingSeen flips and is idempotent', () async {
    await dao.markOnboardingSeen();
    expect(await dao.watchOnboardingSeen().first, isTrue);

    await dao.markOnboardingSeen();
    expect(await dao.watchOnboardingSeen().first, isTrue);
  });
}
