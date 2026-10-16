/// G11: "Only sync with verified devices" end-to-end over the fake relay —
/// every app sender (replication, member bootstraps, digests) goes through
/// the account's delivery policy; unverified devices (own and peers') get
/// nothing, and a peer with no verified device is reported as such.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/core/sync/sync_health.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

void main() {
  late FakeMatrixNetwork net;
  late ProviderContainer aliceApp;
  late AppDatabase aliceDb;
  late SettingsDao aliceSettings;

  /// Every payload that reaches the raw (app-less) [device] of [user].
  List<TransportMessage> inbox(String user, String device) {
    final got = <TransportMessage>[];
    net.clientFor(user, device: device).onMessage.listen(got.add);
    return got;
  }

  setUp(() async {
    net = FakeMatrixNetwork();
    aliceDb = openTestDatabase();
    aliceSettings = SettingsDao(aliceDb);
    net.clientFor(alice);
    aliceApp = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(aliceDb),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(alice)),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
    addTearDown(() async {
      aliceApp.dispose();
      await aliceDb.close();
    });
    aliceApp.listen(ledgerSyncerProvider, (_, _) {});
    aliceApp.listen(syncEngineProvider, (_, _) {});
    aliceApp.listen(syncHealthProvider, (_, _) {});
  });

  Future<String> createGroupWithBob() async {
    await net.settle();
    await aliceApp.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await aliceApp.read(groupsDaoProvider).watchAllGroups().first)
            .first
            .roomId;
    await aliceApp.read(memberAdderProvider.notifier).add(groupId, bob);
    await net.settle();
    return groupId;
  }

  Future<void> addExpense(String groupId, String what) async {
    await aliceApp
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: groupId,
          description: what,
          amountCents: 1000,
          currency: 'EUR',
          paidBy: alice,
          splits: {alice: 500, bob: 500},
        );
    await net.settle();
  }

  bool hasExpense(List<TransportMessage> got, String what) => got.any(
    (m) =>
        m.senderId == alice &&
        m.type == expenseEventType &&
        m.content['description'] == what,
  );

  SignerId deviceOf(String user, String device) => SignerId(
    user: user,
    device: device,
    key: net.keys.listedKey(user, device)!,
  );

  test('off (default): every device of every member receives', () async {
    final bobPhone = inbox(bob, 'D1');
    final bobLaptop = inbox(bob, 'D2');
    final aliceTablet = inbox(alice, 'T1');
    final groupId = await createGroupWithBob();

    await addExpense(groupId, 'Dinner');
    expect(hasExpense(bobPhone, 'Dinner'), isTrue);
    expect(hasExpense(bobLaptop, 'Dinner'), isTrue);
    expect(hasExpense(aliceTablet, 'Dinner'), isTrue);
  });

  test('on: only verified devices receive (own and peers alike)', () async {
    final bobPhone = inbox(bob, 'D1');
    final bobLaptop = inbox(bob, 'D2');
    final aliceTablet = inbox(alice, 'T1');
    final groupId = await createGroupWithBob();

    await aliceSettings.setVerifiedOnlySync(true);
    await aliceSettings.markDeviceVerified(deviceOf(bob, 'D1'));
    await addExpense(groupId, 'Taxi');

    expect(hasExpense(bobPhone, 'Taxi'), isTrue);
    expect(hasExpense(bobLaptop, 'Taxi'), isFalse);
    expect(hasExpense(aliceTablet, 'Taxi'), isFalse);

    // Digests follow the same policy.
    final before = bobLaptop.length;
    await aliceApp.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    expect(bobLaptop.skip(before).where((m) => m.senderId == alice), isEmpty);
    expect(
      bobPhone.any((m) => m.senderId == alice && m.type == digestEventType),
      isTrue,
    );

    // Verifying our own tablet lets it receive the next write.
    await aliceSettings.markDeviceVerified(deviceOf(alice, 'T1'));
    await addExpense(groupId, 'Museum');
    expect(hasExpense(aliceTablet, 'Museum'), isTrue);
    expect(hasExpense(bobLaptop, 'Museum'), isFalse);
  });

  test(
    'a recorded key that no longer matches the device is not trusted',
    () async {
      final bobPhone = inbox(bob, 'D1');
      final groupId = await createGroupWithBob();
      await aliceSettings.setVerifiedOnlySync(true);
      await aliceSettings.markDeviceVerified(
        const SignerId(user: bob, device: 'D1', key: 'some-other-key'),
      );
      await addExpense(groupId, 'Hotel');
      expect(hasExpense(bobPhone, 'Hotel'), isFalse);
    },
  );

  test('a member with no verified device is reported as unverified, and '
      'turning the setting off delivers again', () async {
    final bobPhone = inbox(bob, 'D1');
    final groupId = await createGroupWithBob();
    await aliceSettings.setVerifiedOnlySync(true);

    await addExpense(groupId, 'Lunch');
    expect(hasExpense(bobPhone, 'Lunch'), isFalse);
    final health = aliceApp.read(syncHealthProvider);
    expect(health.unreachablePeers, contains(bob));
    expect(health.unverifiedPeers, contains(bob));
    expect(health.failing, isFalse, reason: 'withholding is not an error');
    expect(pendingPeerHint({bob}, health).reason, PendingReason.unverified);

    await aliceSettings.setVerifiedOnlySync(false);
    await addExpense(groupId, 'Coffee');
    expect(hasExpense(bobPhone, 'Coffee'), isTrue);
    final after = aliceApp.read(syncHealthProvider);
    expect(after.unverifiedPeers, isNot(contains(bob)));
    expect(after.unreachablePeers, isNot(contains(bob)));
  });

  test('SDK-verified devices count as verified', () async {
    final bobPhone = inbox(bob, 'D1');
    final groupId = await createGroupWithBob();
    await aliceSettings.setVerifiedOnlySync(true);
    net.sdkVerified.add('$bob|D1');
    await addExpense(groupId, 'Bus');
    expect(hasExpense(bobPhone, 'Bus'), isTrue);
  });
}
