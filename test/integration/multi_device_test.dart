/// Multi-device recovery tests (Phase C, M6): a user's second/reinstalled
/// device starts with an empty DB and must end up with the full ledger —
/// either from the user's own other device (self resync) or, failing that,
/// organically from a peer's digest (rule 5: unknown group → resync_request).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

void main() {
  // autoTearDown: false lets a test dispose the device itself (simulating a
  // lost/reset install) without a double-dispose in the teardown.
  ProviderContainer makeDevice(FakeMatrixNetwork net, String userId,
      {String device = 'D1', bool autoTearDown = true}) {
    final db = openTestDatabase();
    net.clientFor(userId, device: device);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ledgerTransportProvider
          .overrideWith((ref) => net.clientFor(userId, device: device)),
      pokeDebounceProvider
          .overrideWithValue(const Duration(milliseconds: 1)),
      syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ]);
    if (autoTearDown) {
      addTearDown(() {
        container.dispose();
        db.close();
      });
    }
    container.listen(ledgerSyncerProvider, (_, _) {});
    container.listen(syncEngineProvider, (_, _) {});
    return container;
  }

  Future<void> pump() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  Future<String> seedTripGroup(
      ProviderContainer alice, FakeMatrixNetwork net) async {
    await pump();
    await alice.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await alice.read(groupsDaoProvider).watchAllGroups().first)
            .first
            .roomId;
    await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
    await alice.read(expenseAdderProvider.notifier).addExpense(
      roomId: groupId,
      description: 'Dinner',
      amountCents: 4000,
      currency: 'EUR',
      paidBy: '@alice:x.org',
      splits: {'@alice:x.org': 2000, '@bob:y.org': 2000},
    );
    await pump();
    return groupId;
  }

  test("a second device populates itself from the user's first device",
      () async {
    final net = FakeMatrixNetwork();
    final aliceD1 = makeDevice(net, '@alice:x.org');
    makeDevice(net, '@bob:y.org');
    final groupId = await seedTripGroup(aliceD1, net);

    // Alice signs in on a brand-new device: empty DB → resync_request
    // {scope: all} to her own MXID → device 1 answers with bootstraps.
    final aliceD2 = makeDevice(net, '@alice:x.org', device: 'D2');
    await pump();

    final d2Groups =
        await aliceD2.read(groupsDaoProvider).watchAllGroups().first;
    expect(d2Groups, hasLength(1));
    expect(d2Groups.single.name, 'Trip');
    final d2Expenses =
        await aliceD2.read(expensesDaoProvider).getExpensesForRoom(groupId);
    expect(d2Expenses.single.description, 'Dinner');
    final d2Members =
        await aliceD2.read(membersDaoProvider).getMembers(groupId);
    expect(d2Members.map((m) => m.userId),
        containsAll(['@alice:x.org', '@bob:y.org']));
  });

  test('a write on one device replicates to the same user\'s other device',
      () async {
    final net = FakeMatrixNetwork();
    final aliceD1 = makeDevice(net, '@alice:x.org');
    makeDevice(net, '@bob:y.org');
    final groupId = await seedTripGroup(aliceD1, net);
    final aliceD2 = makeDevice(net, '@alice:x.org', device: 'D2');
    await pump();

    await aliceD2.read(expenseAdderProvider.notifier).addExpense(
      roomId: groupId,
      description: 'From device two',
      amountCents: 1000,
      currency: 'EUR',
      paidBy: '@alice:x.org',
      splits: {'@alice:x.org': 500, '@bob:y.org': 500},
    );
    await pump();

    final d1Expenses =
        await aliceD1.read(expensesDaoProvider).getExpensesForRoom(groupId);
    expect(d1Expenses.map((e) => e.description),
        containsAll(['Dinner', 'From device two']));
  });

  test(
      'a reinstalled device with no other own devices recovers from a peer\'s digest',
      () async {
    final net = FakeMatrixNetwork();
    final alice = makeDevice(net, '@alice:x.org');
    final bobOld = makeDevice(net, '@bob:y.org', autoTearDown: false);
    final groupId = await seedTripGroup(alice, net);
    // Bob's old install is gone for good (device lost/reset) — were it still
    // alive, it would answer the new device's self resync itself.
    bobOld.dispose();

    // Fresh install: empty DB; the self resync goes nowhere (no other own
    // device). Recovery must come organically from Alice's next digest:
    // unknown group → resync_request → membership check → bootstrap.
    final bobNew = makeDevice(net, '@bob:y.org', device: 'D2');
    await pump();
    expect(await bobNew.read(groupsDaoProvider).watchAllGroups().first,
        isEmpty,
        reason: 'sanity: nothing answered the self resync');

    await alice.read(syncEngineProvider).broadcastDigests();
    await pump();

    final bobGroups =
        await bobNew.read(groupsDaoProvider).watchAllGroups().first;
    expect(bobGroups, hasLength(1));
    final bobExpenses =
        await bobNew.read(expensesDaoProvider).getExpensesForRoom(groupId);
    expect(bobExpenses.single.description, 'Dinner');
  });
}
