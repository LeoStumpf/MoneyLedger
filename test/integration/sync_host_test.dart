/// G7a real-device finding: inbound sync must run while signed in regardless of
/// the screen. Before, only GroupsPage/ExpensesPage kept LedgerSyncer alive, so
/// a bootstrap that arrived while the invitee sat on the onboarding screen was
/// dropped (the to-device stream isn't buffered) and the group never appeared.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/ledger_sync_host.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

void main() {
  ProviderContainer makeUser(FakeMatrixNetwork net, String userId,
      {required bool viaHostOnly}) {
    final db = openTestDatabase();
    net.clientFor(userId);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      accountUserIdProvider.overrideWithValue(userId),
      ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
      pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
      syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ]);
    addTearDown(() {
      container.dispose();
      db.close();
    });
    if (viaHostOnly) {
      // Only the app-level host — no page is watching the syncer (e.g. the
      // user is on the onboarding screen).
      container.listen(ledgerSyncActiveProvider, (_, _) {});
    } else {
      container.listen(ledgerSyncerProvider, (_, _) {});
      container.listen(syncEngineProvider, (_, _) {});
    }
    return container;
  }

  test('the sync host alone receives an invite bootstrap', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, '@alice:x.org', viaHostOnly: false);
    final bob = makeUser(net, '@bob:y.org', viaHostOnly: true);
    await net.settle();

    expect(bob.read(ledgerSyncActiveProvider), isTrue);

    await alice.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await alice.read(groupsDaoProvider).watchAllGroups().first)
            .first
            .roomId;
    await alice.read(memberAdderProvider.notifier).add(groupId, '@bob:y.org');
    await net.settle();

    final bobGroups = await bob.read(groupsDaoProvider).watchAllGroups().first;
    expect(bobGroups.map((g) => g.roomId), [groupId]);
  });

  test('the sync host is inactive while signed out', () async {
    final db = openTestDatabase();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      accountUserIdProvider.overrideWithValue(null),
    ]);
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncActiveProvider, (_, _) {});
    expect(container.read(ledgerSyncActiveProvider), isFalse);
  });
}
