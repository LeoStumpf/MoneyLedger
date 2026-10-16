/// G14 + G27 over the in-memory relay: groups too big for one to-device
/// message (forced with a small payload budget the fake network enforces)
/// still onboard new members / devices via chunked bootstraps and repair via
/// bucketed digests; two versions with the same clock converge to the same
/// one (content-hash tie-break) without a repair loop — also when one side
/// refused the other's version.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/payload_budget.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

/// Small enough that 80 records need several bootstrap parts and a bucketed
/// digest; the fake network refuses anything larger (like a homeserver's
/// 64 KiB limit would).
const _smallBudget = 4000;

void main() {
  ProviderContainer makeUser(
    FakeMatrixNetwork net,
    String userId, {
    String device = 'D1',
    int budget = _smallBudget,
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
        digestOnStartProvider.overrideWithValue(false),
        payloadBudgetProvider.overrideWithValue(budget),
      ],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    container.listen(syncEngineProvider, (_, _) {});
    return container;
  }

  Future<String> createGroup(
    ProviderContainer owner,
    FakeMatrixNetwork net,
  ) async {
    await net.settle();
    await owner.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    return (await owner.read(groupsDaoProvider).getAllGroups()).single.roomId;
  }

  /// [n] signed expenses written straight into [user]'s DB (no relay).
  Future<List<ExpenseModel>> seedExpenses(
    ProviderContainer user,
    FakeMatrixNetwork net,
    String userId,
    String groupId,
    int n, {
    String prefix = 'Expense',
    int start = 0,
  }) async {
    final crypto = net.clientFor(userId).crypto;
    final dao = user.read(expensesDaoProvider);
    final out = <ExpenseModel>[];
    for (var i = start; i < start + n; i++) {
      final e = await signExpense(
        crypto,
        ExpenseModel(
          id: '0199e3a0-0000-7000-a000-${i.toString().padLeft(12, '0')}',
          roomId: groupId,
          description: '$prefix $i — groceries and a long-ish description',
          amountCents: 1000 + i,
          currency: 'EUR',
          paidBy: userId,
          splitsJson: '{"$userId":${1000 + i}}',
          createdAt: 1760000000000 + i,
          updatedAt: 1760000000000 + i,
        ),
        creating: true,
      );
      await dao.upsertExpenseLww(expenseCompanion(e));
      out.add(e);
    }
    return out;
  }

  Future<int> lastInSync(
    ProviderContainer c,
    String groupId,
    String peer,
  ) async {
    final states = await c.read(syncStatesDaoProvider).getSyncStates(groupId);
    return states.where((s) => s.userId == peer).firstOrNull?.lastInSyncAt ?? 0;
  }

  Iterable<Map<String, dynamic>> sentOf(FakeMatrixNetwork net, String type) =>
      net.sent.where((s) => s.type == type).map((s) => s.content);

  test('a new member is onboarded with a chunked bootstrap; the bucketed '
      'digests then prove both sides in sync', () async {
    final net = FakeMatrixNetwork()..maxPayloadBytes = _smallBudget;
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final groupId = await createGroup(a, net);
    await seedExpenses(a, net, alice, groupId, 80);

    await a.read(memberAdderProvider.notifier).add(groupId, bob);
    await net.settle();

    final parts = sentOf(net, bootstrapEventType).toList();
    expect(parts.length, greaterThan(5), reason: 'chunked');
    expect(parts.map((p) => p['parts']).toSet(), {parts.length});
    expect(
      await b.read(expensesDaoProvider).getExpensesForRoom(groupId),
      hasLength(80),
    );
    expect((await b.read(membersDaoProvider).getMembers(groupId)).length, 2);

    await a.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    final digests = sentOf(net, digestEventType).toList();
    expect(digests, isNotEmpty);
    expect(
      digests.every((d) => d.containsKey('bucket_bits')),
      isTrue,
      reason: 'too big for a flat digest',
    );
    expect(await lastInSync(a, groupId, bob), greaterThan(0));
    expect(await lastInSync(b, groupId, alice), greaterThan(0));
  });

  test(
    'a new own device restores a large group from chunked bootstraps',
    () async {
      final net = FakeMatrixNetwork()..maxPayloadBytes = _smallBudget;
      final a1 = makeUser(net, alice);
      final groupId = await createGroup(a1, net);
      await seedExpenses(a1, net, alice, groupId, 80);
      await net.settle();

      final a2 = makeUser(net, alice, device: 'D2');
      await net.settle();

      expect(sentOf(net, bootstrapEventType).length, greaterThan(5));
      expect(
        await a2.read(expensesDaoProvider).getExpensesForRoom(groupId),
        hasLength(80),
      );
    },
  );

  test(
    'lost records on both sides are repaired by one bucketed exchange',
    () async {
      final net = FakeMatrixNetwork()..maxPayloadBytes = _smallBudget;
      final a = makeUser(net, alice);
      final b = makeUser(net, bob);
      final groupId = await createGroup(a, net);
      await seedExpenses(a, net, alice, groupId, 80);
      await a.read(memberAdderProvider.notifier).add(groupId, bob);
      await net.settle();

      // Both write while the network loses everything.
      net.dropWhere = (_, _, _) => true;
      await seedExpenses(
        a,
        net,
        alice,
        groupId,
        2,
        prefix: 'A-only',
        start: 100,
      );
      await seedExpenses(b, net, bob, groupId, 1, prefix: 'B-only', start: 200);
      await net.settle();
      net.dropWhere = null;
      net.sent.clear();

      await a.read(syncEngineProvider).broadcastDigests();
      await net.settle();

      for (final c in [a, b]) {
        expect(
          await c.read(expensesDaoProvider).getExpensesForRoom(groupId),
          hasLength(83),
        );
      }
      // Summary → detailed reply → final, all bucketed and within budget.
      final digests = sentOf(net, digestEventType).toList();
      expect(digests.any((d) => d['final'] == true), isTrue);
      expect(digests.every((d) => d.containsKey('bucket_bits')), isTrue);
      expect(
        digests.every((d) => encodedPayloadBytes(d) <= _smallBudget),
        isTrue,
      );
      expect(await lastInSync(a, groupId, bob), greaterThan(0));
      expect(await lastInSync(b, groupId, alice), greaterThan(0));
    },
  );

  for (final budget in [kMaxPayloadBytes, _smallBudget]) {
    final mode = budget == kMaxPayloadBytes ? 'flat' : 'bucketed';
    test('G27 ($mode digests): two edits with the same clock converge to '
        'the higher hash on both devices, no repair loop', () async {
      final net = FakeMatrixNetwork();
      final a = makeUser(net, alice, budget: budget);
      final b = makeUser(net, bob, budget: budget);
      final groupId = await createGroup(a, net);
      final seeded = await seedExpenses(a, net, alice, groupId, 80);
      await a.read(memberAdderProvider.notifier).add(groupId, bob);
      await net.settle();

      // Same record, same clock, different content — written offline.
      final base = seeded.first;
      const t = 1760000099999;
      Future<ExpenseModel> editAs(
        ProviderContainer c,
        String user,
        String text,
      ) async {
        final e = await signExpense(
          net.clientFor(user).crypto,
          ExpenseModel(
            id: base.id,
            roomId: groupId,
            description: text,
            amountCents: base.amountCents,
            currency: 'EUR',
            paidBy: alice,
            splitsJson: base.splitsJson,
            createdAt: base.createdAt,
            updatedAt: t,
            origin: base.origin,
          ),
        );
        await c.read(expensesDaoProvider).upsertExpenseLww(expenseCompanion(e));
        return e;
      }

      final ea = await editAs(a, alice, 'Edited by Alice');
      final eb = await editAs(b, bob, 'Edited by Bob');
      final winner =
          expenseVersionHash(ea).compareTo(expenseVersionHash(eb)) > 0
          ? ea
          : eb;

      await a.read(syncEngineProvider).broadcastDigests();
      await net.settle(); // terminates → no ping-pong

      for (final c in [a, b]) {
        final row = await c.read(expensesDaoProvider).getExpenseById(base.id);
        expect(row!.description, winner.description);
        expect(row.updatedAt, t);
      }
      expect(await lastInSync(a, groupId, bob), greaterThan(0));
      expect(await lastInSync(b, groupId, alice), greaterThan(0));

      // Another round changes nothing.
      net.sent.clear();
      await b.read(syncEngineProvider).broadcastDigests();
      await net.settle();
      expect(sentOf(net, expenseEventType), isEmpty);
    });
  }

  test('G27 + refused versions: a same-clock version that fails verification '
      'is refused, the sides agree to disagree, no loop', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final groupId = await createGroup(a, net);
    final seeded = await seedExpenses(a, net, alice, groupId, 3);
    await a.read(memberAdderProvider.notifier).add(groupId, bob);
    await net.settle();
    final mine = seeded.first;

    // Bob's copy gets tampered at the *same* clock with a higher hash (so it
    // would win the tie-break) — its signature no longer matches.
    late ExpenseModel tampered;
    for (var i = 0; ; i++) {
      tampered = ExpenseModel(
        id: mine.id,
        roomId: groupId,
        description: 'Tampered $i',
        amountCents: mine.amountCents,
        currency: 'EUR',
        paidBy: alice,
        splitsJson: mine.splitsJson,
        createdAt: mine.createdAt,
        updatedAt: mine.updatedAt,
        sig: mine.sig,
        origin: mine.origin,
      );
      if (expenseVersionHash(tampered).compareTo(expenseVersionHash(mine)) >
          0) {
        break;
      }
    }
    await b
        .read(expensesDaoProvider)
        .upsertExpenseLww(expenseCompanion(tampered));

    await b.read(syncEngineProvider).broadcastDigests();
    await net.settle();

    expect(
      (await a.read(expensesDaoProvider).getExpenseById(mine.id))!.description,
      mine.description,
      reason: 'the invalid version is refused',
    );
    expect(
      await a
          .read(signingDaoProvider)
          .rejectedClock(groupId, 'expense', mine.id),
      mine.updatedAt,
    );

    // Agree to disagree: the next rounds send no records and prove sync.
    net.sent.clear();
    await a.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    await b.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    expect(sentOf(net, expenseEventType), isEmpty);
    expect(await lastInSync(a, groupId, bob), greaterThan(0));
    expect(await lastInSync(b, groupId, alice), greaterThan(0));
  });

  test(
    'a payload over the limit fails loudly instead of being dropped',
    () async {
      final net = FakeMatrixNetwork()..maxPayloadBytes = 100;
      net.clientFor(alice);
      expect(
        () => net
            .clientFor(alice)
            .sendToUsers({bob}, digestEventType, {'x': 'y' * 200}),
        throwsA(isA<PayloadTooLargeException>()),
      );
    },
  );
}
