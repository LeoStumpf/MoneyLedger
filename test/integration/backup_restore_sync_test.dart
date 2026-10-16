/// G34 / G35 over the in-memory relay:
/// - restoring a backup of a group whose members have since removed us brings
///   it back, the next digest exchange turns it read-only again — and the
///   exchange settles (no repair loop);
/// - refused unsigned (pre-G6) records in a peer's bootstrap are surfaced in
///   `SyncHealth` instead of leaving a silently half-empty / missing group.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/core/sync/sync_health.dart';
import 'package:money_ledger/features/backup/backup_service.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

void main() {
  final dbs = <ProviderContainer, AppDatabase>{};

  ProviderContainer makeUser(FakeMatrixNetwork net, String userId) {
    final db = openTestDatabase();
    net.clientFor(userId);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
        digestOnStartProvider.overrideWithValue(false),
      ],
    );
    dbs[container] = db;
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    container.listen(syncEngineProvider, (_, _) {});
    container.listen(syncHealthProvider, (_, _) {});
    return container;
  }

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

  Future<String> createGroup(ProviderContainer a, FakeMatrixNetwork n) async {
    await n.settle();
    await a.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    return (await a.read(groupsDaoProvider).getAllGroups()).single.roomId;
  }

  BackupService backupOf(ProviderContainer c) {
    c.listen(backupServiceProvider, (_, _) {});
    return c.read(backupServiceProvider);
  }

  test('G34: restoring a group whose members removed us since → read-only '
      'again after the next digest, and the exchange settles', () async {
    final n = FakeMatrixNetwork();
    final a = makeUser(n, alice);
    final b = makeUser(n, bob);
    final g = await createGroup(a, n);
    await a.read(memberAdderProvider.notifier).add(g, bob);
    await n.settle();
    await a
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: g,
          description: 'Dinner',
          amountCents: 4000,
          currency: 'EUR',
          paidBy: alice,
          splits: {alice: 2000, bob: 2000},
        );
    await n.settle();

    // Bob backs up while still a member…
    final json = await backupOf(b).exportJson(account: bob, now: 1);
    // …then Alice removes him, and he deletes the read-only copy.
    await tick();
    await a.read(memberRemoverProvider.notifier).remove(g, bob);
    await n.settle();
    expect(
      (await b.read(membersDaoProvider).memberByMatrixId(g, bob))!.isActive,
      isFalse,
    );
    await b.read(groupExiterProvider.notifier).delete(g);
    await n.settle();
    expect(await b.read(groupsDaoProvider).getGroup(g), isNull);
    expect(await SettingsDao(dbs[b]!).leftGroup(g), isNotNull);

    // The preview can't know yet (the backup has him active, nothing local).
    final backup = parseBackup(json);
    final preview = await backupOf(b).preview(backup, myMxid: bob);
    expect(preview.groups.single.removed, isFalse);
    expect(preview.groups.single.wasLeft, isTrue);

    // Restore: back, active per the (older) backup, tombstone cleared.
    expect(await backupOf(b).restore(backup), [g]);
    expect(
      (await b.read(membersDaoProvider).memberByMatrixId(g, bob))!.isActive,
      isTrue,
    );
    expect(await SettingsDao(dbs[b]!).leftGroup(g), isNull);

    // The UI pokes the restored group → digest → Alice answers with the
    // newer "removed" record (rule 6) → read-only history again.
    b.read(syncEngineProvider).pokeGroup(g);
    await n.settle();
    final me = (await b.read(membersDaoProvider).memberByMatrixId(g, bob))!;
    expect(me.isActive, isFalse);
    expect(await b.read(groupsDaoProvider).getGroup(g), isNotNull);
    expect(
      await b.read(expensesDaoProvider).getExpensesForRoom(g),
      hasLength(1),
    );
    // Alice's side is untouched — Bob stays removed there.
    expect(
      (await a.read(membersDaoProvider).memberByMatrixId(g, bob))!.isActive,
      isFalse,
    );

    // No loop: the relay is quiet, and another round from both sides ends.
    final before = n.sent.length;
    await n.settle();
    expect(n.sent.length, before);
    await b.read(syncEngineProvider).broadcastDigests();
    await a.read(syncEngineProvider).broadcastDigests();
    await n.settle();
    final round = n.sent.length - before;
    expect(round, lessThan(10));
    final again = n.sent.length;
    await n.settle();
    expect(n.sent.length, again);
    expect(
      (await b.read(membersDaoProvider).memberByMatrixId(g, bob))!.isActive,
      isFalse,
    );
  });

  group('G35 legacy (unsigned) records are surfaced', () {
    test('a refused unsigned expense in a bootstrap shows up in SyncHealth '
        '(group name + who sent it)', () async {
      final n = FakeMatrixNetwork();
      final a = makeUser(n, alice);
      final b = makeUser(n, bob);
      final g = await createGroup(a, n);
      // A pre-G6 row on Alice's device: no signature.
      await a
          .read(expensesDaoProvider)
          .upsertExpenseLww(
            ExpensesCompanion(
              id: const Value('legacy-1'),
              roomId: Value(g),
              description: const Value('Old dinner'),
              amountCents: const Value(1000),
              currency: const Value('EUR'),
              paidBy: const Value(alice),
              splitsJson: Value(jsonEncode({alice: 1000})),
              createdAt: const Value(10),
              updatedAt: const Value(10),
            ),
          );
      await a.read(memberAdderProvider.notifier).add(g, bob);
      await n.settle();

      // The signed part arrived, the legacy row didn't…
      expect(await b.read(groupsDaoProvider).getGroup(g), isNotNull);
      expect(
        await b.read(expensesDaoProvider).getExpenseById('legacy-1'),
        isNull,
      );
      // …and Bob is told why.
      final r = b.read(syncHealthProvider).legacyRefusals[g]!;
      expect(r.relayedBy, alice);
      expect(r.groupName, 'Trip');
      expect(r.count, greaterThanOrEqualTo(1));
      // Not a sync failure.
      expect(b.read(syncHealthProvider).failing, isFalse);

      b.read(syncHealthProvider.notifier).dismissLegacyRefusals();
      expect(b.read(syncHealthProvider).legacyRefusals, isEmpty);
    });

    test('an unsigned (legacy) group meta: the group is missing — and the '
        'hint says so instead of nothing', () async {
      final n = FakeMatrixNetwork();
      final a = makeUser(n, alice);
      final b = makeUser(n, bob);
      await n.settle();
      // A whole pre-G6 group on Alice's device.
      await a
          .read(groupsDaoProvider)
          .upsertGroupLww(
            const GroupsCompanion(
              roomId: Value('old'),
              name: Value('Old flat'),
              currency: Value('EUR'),
              updatedAt: Value(10),
            ),
          );
      await a
          .read(membersDaoProvider)
          .upsertMemberLww(
            const MembersCompanion(
              groupId: Value('old'),
              userId: Value(alice),
              displayName: Value('Alice'),
              matrixId: Value(alice),
              status: Value('active'),
              updatedAt: Value(10),
            ),
          );
      await a.read(memberAdderProvider.notifier).add('old', bob);
      await n.settle();

      expect(await b.read(groupsDaoProvider).getGroup('old'), isNull);
      final r = b.read(syncHealthProvider).legacyRefusals['old']!;
      expect(r.groupName, 'Old flat');
      expect(r.relayedBy, alice);
    });
  });
}
