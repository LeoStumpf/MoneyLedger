/// SettingsDao (Phase F, M5): the device-local onboarding-seen flag.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';

import 'package:money_ledger/core/sync/left_groups.dart';

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

  test('left-group tombstones: mark / read / clear (G9)', () async {
    expect(await dao.leftGroup('g1'), isNull);
    await dao.markGroupLeft(
      'g1',
      const LeftGroupTombstone(
        leftAt: 42,
        removalNotice: {'participant_id': 'p', 'status': 'removed'},
      ),
    );
    final t = await dao.leftGroup('g1');
    expect(t!.leftAt, 42);
    expect(t.removalNotice!['status'], 'removed');
    expect(await dao.leftGroup('g2'), isNull);
    // Doesn't disturb other flags.
    expect(await dao.watchOnboardingSeen().first, isFalse);
    await dao.clearGroupLeft('g1');
    expect(await dao.leftGroup('g1'), isNull);
  });
}
