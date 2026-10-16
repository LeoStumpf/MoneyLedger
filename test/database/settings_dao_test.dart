/// SettingsDao (Phase F, M5): the device-local onboarding-seen flag.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';

import 'package:money_ledger/core/matrix/ledger_transport.dart';
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

  group('G11 device verification', () {
    test('verified-only sync is off by default and toggles', () async {
      expect(await dao.verifiedOnlySync(), isFalse);
      expect(await dao.watchVerifiedOnlySync().first, isFalse);
      expect(await dao.deliveryPolicy(), same(DeliveryPolicy.everyone));
      await dao.setVerifiedOnlySync(true);
      expect(await dao.verifiedOnlySync(), isTrue);
      expect(await dao.watchVerifiedOnlySync().first, isTrue);
      await dao.setVerifiedOnlySync(false);
      expect(await dao.verifiedOnlySync(), isFalse);
    });

    test(
      'verified devices round-trip; a re-verification replaces the key',
      () async {
        const a = SignerId(user: '@b:x.org', device: 'DEV|1', key: 'k1');
        const b = SignerId(user: '@c:y.org', device: 'C1', key: 'kc');
        await dao.markDeviceVerified(a);
        await dao.markDeviceVerified(b);
        expect(await dao.verifiedDevices(), {a, b});
        await dao.markDeviceVerified(
          const SignerId(user: '@b:x.org', device: 'DEV|1', key: 'k2'),
        );
        expect(await dao.watchVerifiedDevices().first, {
          b,
          const SignerId(user: '@b:x.org', device: 'DEV|1', key: 'k2'),
        });
      },
    );

    test('unrelated settings never parse as verified devices', () async {
      await dao.markOnboardingSeen();
      await dao.setVerifiedOnlySync(true);
      expect(await dao.verifiedDevices(), isEmpty);
    });

    test('deliveryPolicy carries the flag and the verified devices', () async {
      const a = SignerId(user: '@b:x.org', device: 'B1', key: 'k1');
      await dao.markDeviceVerified(a);
      expect((await dao.deliveryPolicy()).verifiedOnly, isFalse);
      await dao.setVerifiedOnlySync(true);
      final p = await dao.deliveryPolicy();
      expect(p.verifiedOnly, isTrue);
      expect(p.trusted, {a});
    });
  });
}
