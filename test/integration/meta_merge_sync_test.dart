/// G57 (C1) end to end over the fake Matrix relay: concurrent edits of the
/// group meta on two devices — a rename on one, a new custom category and
/// exchange rates on the other — all survive on **both** sides (per-field
/// clocks, the merging device re-signs the merged meta), whether the edits
/// cross live or were lost and repaired by the digests; both end on the same
/// signed meta version.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/exchange_rates.dart';
import 'package:money_ledger/models/group_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const _alice = '@alice:x.org';
const _bob = '@bob:y.org';

void main() {
  ProviderContainer makeUser(FakeMatrixNetwork net, String userId) {
    final db = openTestDatabase();
    net.clientFor(userId);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    container.listen(syncEngineProvider, (_, _) {});
    container.listen(groupEditorProvider, (_, _) {});
    return container;
  }

  Future<(ProviderContainer, ProviderContainer, String)> twoMembers(
    FakeMatrixNetwork net,
  ) async {
    final alice = makeUser(net, _alice);
    final bob = makeUser(net, _bob);
    await net.settle();
    final groupId = (await alice
        .read(groupCreatorProvider.notifier)
        .create('Trip', 'EUR'))!;
    await alice.read(memberAdderProvider.notifier).add(groupId, _bob);
    await net.settle();
    return (alice, bob, groupId);
  }

  Future<GroupModel> metaOf(ProviderContainer c, String groupId) async =>
      (await c.read(groupsDaoProvider).getGroup(groupId))!;

  /// Alice renames while Bob adds a category and sets exchange rates.
  Future<String> concurrentEdits(
    ProviderContainer alice,
    ProviderContainer bob,
    String groupId,
  ) async {
    await alice
        .read(groupEditorProvider.notifier)
        .edit(groupId, name: 'Ski trip', currency: 'EUR');
    final bobEditor = bob.read(groupEditorProvider.notifier);
    final dog = await bobEditor.addCategory(groupId, name: 'Dog', icon: 'pets');
    await bobEditor.setExchangeRates(
      groupId,
      ExchangeRates(base: 'EUR', rates: const {'CHF': '1.1'}),
    );
    expect(alice.read(groupEditorProvider).hasError, isFalse);
    expect(bob.read(groupEditorProvider).hasError, isFalse);
    return dog!;
  }

  Future<void> expectConverged(
    ProviderContainer alice,
    ProviderContainer bob,
    String groupId,
    String dog,
  ) async {
    final a = await metaOf(alice, groupId);
    final b = await metaOf(bob, groupId);
    for (final g in [a, b]) {
      expect(g.name, 'Ski trip');
      expect(g.currency, 'EUR');
      expect(g.categories.map((c) => c.id), [dog]);
      expect(g.categories.single.name, 'Dog');
      expect(g.exchangeRates?.rates, {'CHF': '1.1'});
      expect(g.sig, isNotNull);
      expect(g.pendingSign, isFalse);
    }
    expect(groupMetaVersion(a), groupMetaVersion(b));
  }

  test('lost meta messages: rename + category + rates written on two devices '
      'meet through the digests; both keep every change', () async {
    final net = FakeMatrixNetwork();
    final (alice, bob, groupId) = await twoMembers(net);

    net.dropWhere = (_, _, type) => type == groupMetaEventType;
    final dog = await concurrentEdits(alice, bob, groupId);
    await net.settle();
    // Each side has only its own changes so far.
    expect((await metaOf(alice, groupId)).categories, isEmpty);
    expect((await metaOf(bob, groupId)).name, 'Trip');

    net.dropWhere = null;
    await alice.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    await bob.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    await expectConverged(alice, bob, groupId, dog);
  });

  test(
    'live: the edits cross on the relay; both converge on the merge',
    () async {
      final net = FakeMatrixNetwork();
      final (alice, bob, groupId) = await twoMembers(net);
      final dog = await concurrentEdits(alice, bob, groupId);
      await net.settle();
      await alice.read(syncEngineProvider).broadcastDigests();
      await net.settle();
      await expectConverged(alice, bob, groupId, dog);
    },
  );

  test('a later rename of the category on one side and of the group on the '
      'other: both survive (per-category clock)', () async {
    final net = FakeMatrixNetwork();
    final (alice, bob, groupId) = await twoMembers(net);
    final id = await alice
        .read(groupEditorProvider.notifier)
        .addCategory(groupId, name: 'Dog', icon: 'pets');
    await net.settle();

    net.dropWhere = (_, _, type) => type == groupMetaEventType;
    final cat = (await metaOf(bob, groupId)).categories.single;
    await bob
        .read(groupEditorProvider.notifier)
        .updateCategory(groupId, cat.copyWith(name: 'Dog & cat'));
    await alice
        .read(groupEditorProvider.notifier)
        .edit(groupId, name: 'Ski trip', currency: 'CHF');
    await net.settle();
    net.dropWhere = null;
    await bob.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    await alice.read(syncEngineProvider).broadcastDigests();
    await net.settle();

    final a = await metaOf(alice, groupId);
    final b = await metaOf(bob, groupId);
    for (final g in [a, b]) {
      expect(g.name, 'Ski trip');
      expect(g.currency, 'CHF');
      expect(g.categories.single.id, id);
      expect(g.categories.single.name, 'Dog & cat');
    }
    expect(groupMetaVersion(a), groupMetaVersion(b));
  });
}
