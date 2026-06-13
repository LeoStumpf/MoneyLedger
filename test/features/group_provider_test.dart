library;

import 'dart:async';

import 'package:drift/drift.dart';
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
  });
}
