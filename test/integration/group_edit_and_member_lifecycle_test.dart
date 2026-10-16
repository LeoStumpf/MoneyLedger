/// G10 (group rename / default currency converge across devices) and G26
/// (member lifecycle: re-add reactivates instead of duplicating, leaving on
/// one device leaves on our other devices, removal by a peer keeps the group
/// read-only, re-add wins over a fast-clocked `removed` record).
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/left_groups.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

void main() {
  final dbs = <ProviderContainer, AppDatabase>{};

  ProviderContainer makeUser(
    FakeMatrixNetwork net,
    String userId, {
    String device = 'D1',
  }) {
    final db = openTestDatabase();
    net.clientFor(userId, device: device);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith(
          (ref) => net.clientFor(userId, device: device),
        ),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
    dbs[container] = db;
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    container.listen(syncEngineProvider, (_, _) {});
    return container;
  }

  Future<String> createGroup(ProviderContainer a, FakeMatrixNetwork net) async {
    await net.settle();
    await a.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    return (await a.read(groupsDaoProvider).getAllGroups()).single.roomId;
  }

  Future<void> addDinner(
    ProviderContainer c,
    String groupId,
    Map<String, int> split,
  ) async {
    await c
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: groupId,
          description: 'Dinner',
          amountCents: split.values.fold(0, (a, b) => a + b),
          currency: 'EUR',
          paidBy: split.keys.first,
          splits: split,
        );
  }

  Future<List<MemberModel>> membersOf(ProviderContainer c, String g) =>
      c.read(membersDaoProvider).getMembers(g);

  Future<bool> hasGroup(ProviderContainer c, String groupId) async =>
      (await c.read(groupsDaoProvider).getGroup(groupId)) != null;

  /// Lets the wall clock advance so the next write gets a strictly newer
  /// LWW clock than the previous one.
  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

  group('G10 group meta edit', () {
    test('a rename + currency change converges on the other member', () async {
      final n = FakeMatrixNetwork();
      final a = makeUser(n, alice);
      final b = makeUser(n, bob);
      final g = await createGroup(a, n);
      await a.read(memberAdderProvider.notifier).add(g, bob);
      await n.settle();
      expect((await b.read(groupsDaoProvider).getGroup(g))!.name, 'Trip');

      await tick();
      await b
          .read(groupEditorProvider.notifier)
          .edit(
            g,
            name: 'Ski trip',
            currency: 'CHF',
          ); // any active member may edit
      await n.settle();

      expect(b.read(groupEditorProvider).hasError, isFalse);
      for (final c in [a, b]) {
        final group = (await c.read(groupsDaoProvider).getGroup(g))!;
        expect(group.name, 'Ski trip');
        expect(group.currency, 'CHF');
      }
    });

    test(
      'concurrent renames converge to the latest clock (via anti-entropy)',
      () async {
        final n = FakeMatrixNetwork();
        final a = makeUser(n, alice);
        final b = makeUser(n, bob);
        final g = await createGroup(a, n);
        await a.read(memberAdderProvider.notifier).add(g, bob);
        await n.settle();

        // Both rename while partitioned: neither meta relay arrives.
        n.dropWhere = (_, _, _) => true;
        await tick();
        await a
            .read(groupEditorProvider.notifier)
            .edit(g, name: 'Alice name', currency: 'EUR');
        await tick();
        await b
            .read(groupEditorProvider.notifier)
            .edit(g, name: 'Bob name', currency: 'USD');
        await n.settle();
        n.dropWhere = null;
        expect(
          (await a.read(groupsDaoProvider).getGroup(g))!.name,
          'Alice name',
        );

        // The next digest exchange repairs the meta (meta_updated_at): the
        // later edit (Bob's) wins on both sides.
        await a.read(syncEngineProvider).broadcastDigests();
        await n.settle();
        for (final c in [a, b]) {
          final group = (await c.read(groupsDaoProvider).getGroup(g))!;
          expect(group.name, 'Bob name');
          expect(group.currency, 'USD');
        }
      },
    );

    test('a removed member cannot rename (peers drop the meta)', () async {
      final n = FakeMatrixNetwork();
      final a = makeUser(n, alice);
      final b = makeUser(n, bob);
      final g = await createGroup(a, n);
      await a.read(memberAdderProvider.notifier).add(g, bob);
      await n.settle();
      await tick();
      await a.read(memberRemoverProvider.notifier).remove(g, bob);
      await n.settle();

      await tick();
      await b
          .read(groupEditorProvider.notifier)
          .edit(g, name: 'Hijack', currency: 'EUR');
      await n.settle();
      expect((await a.read(groupsDaoProvider).getGroup(g))!.name, 'Trip');
    });
  });

  group('G26 re-add', () {
    test('re-adding someone who left after claiming a placeholder reactivates '
        'that participant — no duplicate', () async {
      final n = FakeMatrixNetwork();
      final a = makeUser(n, alice);
      final b = makeUser(n, bob);
      final g = await createGroup(a, n);
      // A local placeholder "Bobby" with history, then Bob claims it.
      await a.read(memberAdderProvider.notifier).addLocal(g, 'Bobby');
      final placeholder = (await membersOf(
        a,
        g,
      )).firstWhere((m) => m.displayName == 'Bobby').userId;
      await addDinner(a, g, {alice: 1500, placeholder: 1500});
      await a.read(memberAdderProvider.notifier).claim(g, placeholder, bob);
      await n.settle();
      expect(
        (await b.read(membersDaoProvider).memberByMatrixId(g, bob))!.userId,
        placeholder,
      );

      await tick();
      await b.read(groupExiterProvider.notifier).leave(g);
      await n.settle();
      expect(await hasGroup(b, g), isFalse);

      await tick();
      await a.read(memberAdderProvider.notifier).add(g, bob);
      await n.settle();
      expect(a.read(memberAdderProvider).hasError, isFalse);

      for (final c in [a, b]) {
        final claims = (await membersOf(
          c,
          g,
        )).where((m) => m.matrixId == bob).toList();
        expect(claims, hasLength(1), reason: 'exactly one participant for Bob');
        expect(claims.single.userId, placeholder);
        expect(claims.single.displayName, 'Bobby');
        expect(claims.single.isActive, isTrue);
        // The lookup that used to throw on duplicates.
        expect(
          (await c.read(membersDaoProvider).memberByMatrixId(g, bob))!.userId,
          placeholder,
        );
      }
      expect(await hasGroup(b, g), isTrue);
      expect(
        await b.read(expensesDaoProvider).getExpensesForRoom(g),
        hasLength(1),
      );
    });

    test(
      're-adding wins over a removed record stamped by a faster clock',
      () async {
        final n = FakeMatrixNetwork();
        final a = makeUser(n, alice);
        final b = makeUser(n, bob);
        final g = await createGroup(a, n);
        await a.read(memberAdderProvider.notifier).add(g, bob);
        await n.settle();

        // Bob's device clock runs 2 minutes ahead: his leave notice (and his
        // tombstone's left_at) are stamped in Alice's future.
        final future = DateTime.now().millisecondsSinceEpoch + 120000;
        final removed = MemberModel(
          groupId: g,
          userId: bob,
          displayName: 'bob',
          matrixId: bob,
          status: 'removed',
          updatedAt: future,
        );
        await a
            .read(membersDaoProvider)
            .upsertMemberLww(memberCompanion(removed));
        await dbs[b]!.purgeGroup(g);
        await SettingsDao(dbs[b]!).markGroupLeft(
          g,
          LeftGroupTombstone(
            leftAt: removed.updatedAt,
            removalNotice: memberPayload(removed),
          ),
        );

        await a.read(memberAdderProvider.notifier).add(g, bob);
        await n.settle();

        final readded = (await a
            .read(membersDaoProvider)
            .memberByMatrixId(g, bob))!;
        expect(
          readded.isActive,
          isTrue,
          reason: 'local LWW accepted the re-add',
        );
        expect(readded.updatedAt, greaterThan(future));
        expect(
          await hasGroup(b, g),
          isTrue,
          reason: "Bob's tombstone check (updated_at > left_at) passes",
        );
      },
    );

    test('memberByMatrixId tolerates pre-existing duplicate claims', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dao = MembersDao(db);
      MembersCompanion row(String id, String status, int at) =>
          MembersCompanion(
            groupId: const Value('g'),
            userId: Value(id),
            displayName: Value(id),
            matrixId: const Value(bob),
            status: Value(status),
            updatedAt: Value(at),
          );
      await dao.upsertMemberLww(row('p-old', 'removed', 5));
      await dao.upsertMemberLww(row(bob, 'active', 3));
      expect(
        (await dao.memberByMatrixId('g', bob))!.userId,
        bob,
        reason: 'active preferred',
      );
      await dao.upsertMemberLww(row(bob, 'removed', 4));
      expect(
        (await dao.memberByMatrixId('g', bob))!.userId,
        'p-old',
        reason: 'then newest',
      );
    });
  });

  group('G26 leave vs. own other devices', () {
    test('leaving on one device purges the group on our other device too '
        '(tombstoned); re-adding brings it back on both', () async {
      final n = FakeMatrixNetwork();
      final a = makeUser(n, alice);
      final b1 = makeUser(n, bob);
      final b2 = makeUser(n, bob, device: 'D2');
      final g = await createGroup(a, n);
      await a.read(memberAdderProvider.notifier).add(g, bob);
      await addDinner(a, g, {alice: 2000, bob: 2000});
      await n.settle();
      expect(await hasGroup(b2, g), isTrue, reason: 'sanity: D2 has it');

      await tick();
      await b1.read(groupExiterProvider.notifier).leave(g);
      await n.settle();

      expect(await hasGroup(b1, g), isFalse);
      expect(await hasGroup(b2, g), isFalse, reason: 'left on D2 as well');
      expect(await membersOf(b2, g), isEmpty);
      final t = await SettingsDao(dbs[b2]!).leftGroup(g);
      expect(t, isNotNull);
      expect(t!.removalNotice?['status'], 'removed');
      expect(
        (await a.read(membersDaoProvider).memberByMatrixId(g, bob))!.status,
        'removed',
      );

      // Alice's digests (and D2's) don't resurrect it.
      await a.read(syncEngineProvider).broadcastDigests();
      await n.settle();
      expect(await hasGroup(b2, g), isFalse);

      await tick();
      await a.read(memberAdderProvider.notifier).add(g, bob);
      await n.settle();
      for (final c in [b1, b2]) {
        expect(await hasGroup(c, g), isTrue);
        expect(
          await c.read(expensesDaoProvider).getExpensesForRoom(g),
          hasLength(1),
        );
        expect(await SettingsDao(dbs[c]!).leftGroup(g), isNull);
      }
    });

    test('removed by another member: the group stays (read-only history) on '
        'all our devices, no tombstone', () async {
      final n = FakeMatrixNetwork();
      final a = makeUser(n, alice);
      final b1 = makeUser(n, bob);
      final b2 = makeUser(n, bob, device: 'D2');
      final g = await createGroup(a, n);
      await a.read(memberAdderProvider.notifier).add(g, bob);
      await addDinner(a, g, {alice: 2000, bob: 2000});
      await n.settle();

      await tick();
      await a.read(memberRemoverProvider.notifier).remove(g, bob);
      await n.settle();

      for (final c in [b1, b2]) {
        expect(await hasGroup(c, g), isTrue);
        expect(
          await c.read(expensesDaoProvider).getExpensesForRoom(g),
          hasLength(1),
        );
        expect(await SettingsDao(dbs[c]!).leftGroup(g), isNull);
        final me = await c.read(currentParticipantProvider(g).future);
        expect(me!.isActive, isFalse);
        // The menu now offers a local delete.
        expect(groupExitKind(await membersOf(c, g), bob), GroupExitKind.delete);
      }
    });

    test('isOwnLeaveFromOtherDevice', () {
      Map<String, dynamic> rec(String mxid, String status) => {
        'matrix_id': mxid,
        'status': status,
        'participant_id': 'p',
      };
      bool check(String sender, Map<String, dynamic> c) =>
          LedgerSyncer.isOwnLeaveFromOtherDevice(
            senderId: sender,
            content: c,
            myMxid: bob,
          );
      expect(check(bob, rec(bob, 'removed')), isTrue);
      expect(
        check(alice, rec(bob, 'removed')),
        isFalse,
        reason: 'removed by peer',
      );
      expect(check(bob, rec(bob, 'active')), isFalse);
      expect(check(bob, rec(alice, 'removed')), isFalse);
    });
  });

  test('nextLwwClock is the wall clock but always strictly newer', () {
    expect(nextLwwClock(10, now: 50), 50);
    expect(nextLwwClock(50, now: 50), 51);
    expect(nextLwwClock(90, now: 50), 91);
  });
}
