library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

void main() {
  group('ledgerGroupsProvider', () {
    late AppDatabase db;
    late GroupsDao dao;

    setUp(() {
      db = openTestDatabase();
      dao = GroupsDao(db);
    });

    tearDown(() => db.close());

    ProviderContainer makeContainer() => ProviderContainer(overrides: [
          appDatabaseProvider.overrideWithValue(db),
        ]);

    // Returns the first emission of ledgerGroupsProvider while keeping the
    // provider alive (autoDispose disposes it if there are no listeners).
    Future<List> firstEmission(ProviderContainer c) async {
      final completer = Completer<List>();
      final sub = c.listen<AsyncValue>(ledgerGroupsProvider, (_, next) {
        next.whenData((v) {
          if (!completer.isCompleted) completer.complete(v);
        });
      }, fireImmediately: true);
      final result = await completer.future;
      sub.close();
      return result;
    }

    test('emits empty list initially', () async {
      final c = makeContainer();
      addTearDown(c.dispose);

      final groups = await firstEmission(c);
      expect(groups, isEmpty);
    });

    test('emits group after it is inserted into the DAO', () async {
      final c = makeContainer();
      addTearDown(c.dispose);

      await dao.upsertGroupLww(const GroupsCompanion(
        roomId: Value('!abc:matrix.org'),
        name: Value('Road Trip'),
        currency: Value('EUR'),
        updatedAt: Value(1000),
      ));

      final groups = await firstEmission(c);
      expect(groups.length, 1);
      expect(groups.first.roomId, '!abc:matrix.org');
      expect(groups.first.name, 'Road Trip');
      expect(groups.first.currency, 'EUR');
    });

    test('emits updated list when a second group is inserted', () async {
      final c = makeContainer();
      addTearDown(c.dispose);

      await dao.upsertGroupLww(const GroupsCompanion(
        roomId: Value('!r1:m.org'),
        name: Value('G1'),
        currency: Value('EUR'),
        updatedAt: Value(1000),
      ));
      await dao.upsertGroupLww(const GroupsCompanion(
        roomId: Value('!r2:m.org'),
        name: Value('G2'),
        currency: Value('USD'),
        updatedAt: Value(1000),
      ));

      final groups = await firstEmission(c);
      expect(groups.length, 2);
      final roomIds = groups.map((g) => g.roomId).toSet();
      expect(roomIds, containsAll(['!r1:m.org', '!r2:m.org']));
    });
  });

  group('participant identity', () {
    late AppDatabase db;
    late ProviderContainer c;

    setUp(() {
      db = openTestDatabase();
      final net = FakeMatrixNetwork();
      c = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider
            .overrideWith((ref) => net.clientFor('@alice:x.org')),
      ]);
    });
    tearDown(() {
      c.dispose();
      db.close();
    });

    Future<String> createTrip() async {
      await c.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
      return (await c.read(groupsDaoProvider).getAllGroups()).single.roomId;
    }

    test('create seeds a self-participant claimed by the creator', () async {
      final groupId = await createTrip();
      final self = (await c.read(membersDaoProvider).getMembers(groupId)).single;
      expect(self.matrixId, '@alice:x.org');
      expect(self.displayName, 'alice');
      expect(self.userId, '@alice:x.org'); // from-scratch invariant
      expect(self.isClaimed, true);

      final cp = await c.read(currentParticipantProvider(groupId).future);
      expect(cp?.userId, self.userId);
    });

    test('a pure-local participant is never a sync target', () async {
      final groupId = await createTrip();
      await c.read(membersDaoProvider).upsertMemberLww(MembersCompanion(
            groupId: Value(groupId),
            userId: const Value('p-local'),
            displayName: const Value('Cash'),
            status: const Value('active'),
            updatedAt: const Value(1),
          ));
      final targets =
          await c.read(membersDaoProvider).activeClaimedMatrixIds(groupId);
      expect(targets, ['@alice:x.org']); // only the claimed self
    });

    test('addLocal creates an unclaimed participant, not a sync target',
        () async {
      final groupId = await createTrip();
      await c.read(memberAdderProvider.notifier).addLocal(groupId, 'Cash');
      final cash = (await c.read(membersDaoProvider).getMembers(groupId))
          .firstWhere((m) => m.displayName == 'Cash');
      expect(cash.matrixId, isNull);
      expect(cash.isClaimed, false);
      expect(await c.read(membersDaoProvider).activeClaimedMatrixIds(groupId),
          ['@alice:x.org']);
    });

    test('claim then unclaim keeps the participant identity + name', () async {
      final groupId = await createTrip();
      await c.read(memberAdderProvider.notifier).addLocal(groupId, 'Bob');
      final bob = (await c.read(membersDaoProvider).getMembers(groupId))
          .firstWhere((m) => m.displayName == 'Bob');

      await c
          .read(memberAdderProvider.notifier)
          .claim(groupId, bob.userId, '@bob:y.org');
      final claimed =
          await c.read(membersDaoProvider).memberByMatrixId(groupId, '@bob:y.org');
      expect(claimed?.userId, bob.userId); // same ledger identity
      expect(claimed?.matrixId, '@bob:y.org');

      await c.read(memberAdderProvider.notifier).unclaim(groupId, bob.userId);
      final after = (await c.read(membersDaoProvider).getMembers(groupId))
          .firstWhere((m) => m.userId == bob.userId);
      expect(after.matrixId, isNull);
      expect(after.displayName, 'Bob'); // identity + history preserved
    });

    test('reactivate re-adds a removed local person in place (G7)', () async {
      final groupId = await createTrip();
      await c.read(memberAdderProvider.notifier).addLocal(groupId, 'Carl');
      final carl = (await c.read(membersDaoProvider).getMembers(groupId))
          .firstWhere((m) => m.displayName == 'Carl');
      await c.read(memberRemoverProvider.notifier).remove(groupId, carl.userId);
      final removed = (await c.read(membersDaoProvider).getMembers(groupId))
          .firstWhere((m) => m.userId == carl.userId);
      expect(removed.isActive, isFalse);

      await c.read(memberAdderProvider.notifier).reactivate(groupId, carl.userId);
      final members = await c.read(membersDaoProvider).getMembers(groupId);
      final carls = members.where((m) => m.displayName == 'Carl').toList();
      expect(carls, hasLength(1)); // no duplicate participant
      expect(carls.single.userId, carl.userId); // same identity → history kept
      expect(carls.single.isActive, isTrue);
      expect(carls.single.updatedAt, greaterThan(removed.updatedAt));
    });

    test('rename updates the display name', () async {
      final groupId = await createTrip();
      await c.read(memberAdderProvider.notifier).addLocal(groupId, 'Cassh');
      final p = (await c.read(membersDaoProvider).getMembers(groupId))
          .firstWhere((m) => m.displayName == 'Cassh');
      await c.read(memberAdderProvider.notifier).rename(groupId, p.userId, 'Cash');
      final after = (await c.read(membersDaoProvider).getMembers(groupId))
          .firstWhere((m) => m.userId == p.userId);
      expect(after.displayName, 'Cash');
    });

    test('participantNames resolves names, falling back to matrixId/id',
        () async {
      final groupId = await createTrip();
      await c.read(membersDaoProvider).upsertMemberLww(MembersCompanion(
            groupId: Value(groupId),
            userId: const Value('p1'),
            displayName: const Value(''),
            matrixId: const Value('@x:y.org'),
            status: const Value('active'),
            updatedAt: const Value(1),
          ));
      // Keep the (auto-dispose) stream alive so it emits before we read it.
      final sub = c.listen(participantNamesProvider(groupId), (_, _) {});
      await c.read(groupMembersProvider(groupId).future);
      final names = c.read(participantNamesProvider(groupId));
      expect(names['@alice:x.org'], 'alice'); // creator's localpart
      expect(names['p1'], 'x'); // empty name → matrixId localpart (G17)
      sub.close();
    });

    test('names still resolve for removed participants (balances/history, #8)',
        () async {
      final groupId = await createTrip();
      // A removed member is hidden from the roster but keeps their history, so
      // their name must still resolve where old splits reference them.
      await c.read(membersDaoProvider).upsertMemberLww(MembersCompanion(
            groupId: Value(groupId),
            userId: const Value('p-gone'),
            displayName: const Value('Old Pal'),
            matrixId: const Value('@gone:x.org'),
            status: const Value('removed'),
            updatedAt: const Value(1),
          ));
      final sub = c.listen(participantNamesProvider(groupId), (_, _) {});
      await c.read(groupMembersProvider(groupId).future);
      expect(c.read(participantNamesProvider(groupId))['p-gone'], 'Old Pal');
      sub.close();
    });
  });
}
