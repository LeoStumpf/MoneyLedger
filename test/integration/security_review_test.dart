/// G18 pre-release security review — end-to-end regressions over the
/// in-memory relay (findings 1–5 and 11). Each scenario was reproduced
/// against the code before the fix (`zz_review_sec_inject_test.dart`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_verifier.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';
const mallory = '@mallory:z.org';

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
        digestOnStartProvider.overrideWithValue(false),
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

  /// Alice creates "Trip" and adds [others]; returns its id.
  Future<String> trip(
    FakeMatrixNetwork net,
    ProviderContainer a,
    List<String> others,
  ) async {
    await net.settle();
    await a.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final z = (await a.read(groupsDaoProvider).getAllGroups()).single.roomId;
    for (final o in others) {
      await a.read(memberAdderProvider.notifier).add(z, o);
      await net.settle();
    }
    return z;
  }

  Future<ExpenseModel> dinner(
    FakeMatrixNetwork net,
    ProviderContainer a,
    String z,
  ) async {
    await a
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: z,
          description: 'Dinner',
          amountCents: 4000,
          currency: 'EUR',
          paidBy: alice,
          splits: {alice: 2000, bob: 2000},
        );
    await net.settle();
    return (await a.read(expensesDaoProvider).getExpensesForRoom(z)).single;
  }

  // Finding 1 (critical).
  test("a stranger's TOFU bootstrap can't inject members / records into "
      'another group', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final z = await trip(net, a, [bob]);

    final mc = net.clientFor(mallory).crypto;
    final now = DateTime.now().millisecondsSinceEpoch;
    final meta = await signGroupMeta(
      mc,
      GroupModel(
        roomId: 'X-fresh',
        name: 'Free money',
        currency: 'EUR',
        updatedAt: now,
      ),
    );
    final selfX = await signMember(
      mc,
      MemberModel(
        groupId: 'X-fresh',
        userId: mallory,
        displayName: 'M',
        matrixId: mallory,
        status: 'active',
        updatedAt: now,
      ),
    );
    final intoZ = await signMember(
      mc,
      MemberModel(
        groupId: z,
        userId: 'p-mallory',
        displayName: 'Mallory',
        matrixId: mallory,
        status: 'active',
        updatedAt: now,
      ),
    );
    final exp = await signExpense(
      mc,
      ExpenseModel(
        id: 'evil-1',
        roomId: z,
        description: 'You owe me',
        amountCents: 100000,
        currency: 'EUR',
        paidBy: 'p-mallory',
        splitsJson: '{"$bob":100000}',
        createdAt: now,
        updatedAt: now,
      ),
      creating: true,
    );
    await net
        .clientFor(mallory)
        .sendToUsers(
          {bob},
          bootstrapEventType,
          {
            'v': protocolVersion,
            'group': 'X-fresh',
            'meta': groupMetaPayload(meta),
            'members': [memberPayload(selfX), memberPayload(intoZ)],
            'expenses': [expensePayload(exp)],
            'settlements': [],
          },
        );
    await net.settle();

    final zMembers = await b.read(membersDaoProvider).getMembers(z);
    expect(zMembers.where((m) => m.matrixId == mallory), isEmpty);
    expect(await b.read(expensesDaoProvider).getExpenseById('evil-1'), isNull);
    // Mallory's own (spam) group may exist, but holds only its own entries.
    expect(
      (await b.read(membersDaoProvider).getMembers('X-fresh')).map(
        (m) => m.userId,
      ),
      [mallory],
    );

    // Bob's next write in Z isn't leaked to Mallory.
    final sentBefore = net.sent.length;
    await b
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: z,
          description: 'secret',
          amountCents: 10,
          currency: 'EUR',
          paidBy: bob,
          splits: {bob: 10},
        );
    await net.settle();
    expect(
      net.sent.skip(sentBefore).where((s) => s.targets.contains(mallory)),
      isEmpty,
    );
  });

  // Finding 2 (critical).
  test('a removed member can neither rejoin with a fresh participant id nor '
      'reactivate itself', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    makeUser(net, mallory);
    final z = await trip(net, a, [bob, mallory]);
    final mp = (await a.read(membersDaoProvider).getMembers(z)).firstWhere(
      (m) => m.matrixId == mallory,
    );
    await a.read(memberRemoverProvider.notifier).remove(z, mp.userId);
    await net.settle();

    final mc = net.clientFor(mallory).crypto;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final pid in ['p-again', mp.userId]) {
      final back = await signMember(
        mc,
        MemberModel(
          groupId: z,
          userId: pid,
          displayName: 'Mallory',
          matrixId: mallory,
          status: 'active',
          updatedAt: now + 1,
        ),
      );
      await net
          .clientFor(mallory)
          .sendToUsers({alice, bob}, memberEventType, memberPayload(back));
      await net.settle();
    }
    for (final c in [a, b]) {
      final ms = await c.read(membersDaoProvider).getMembers(z);
      expect(ms.where((m) => m.matrixId == mallory && m.isActive), isEmpty);
      expect(ms.map((m) => m.userId), isNot(contains('p-again')));
    }

    // Removal sticks: her records are ignored too.
    final e = await signExpense(
      mc,
      ExpenseModel(
        id: 'm-1',
        roomId: z,
        description: 'after removal',
        amountCents: 100,
        currency: 'EUR',
        paidBy: mp.userId,
        splitsJson: '{"$bob":100}',
        createdAt: now,
        updatedAt: now,
      ),
      creating: true,
    );
    await net
        .clientFor(mallory)
        .sendToUsers({alice, bob}, expenseEventType, expensePayload(e));
    await net.settle();
    expect(await a.read(expensesDaoProvider).getExpenseById('m-1'), isNull);
    expect(await b.read(expensesDaoProvider).getExpenseById('m-1'), isNull);
  });

  // Finding 3 (major).
  test('an unsigned far-future version does not freeze the record', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    makeUser(net, mallory);
    final z = await trip(net, a, [bob, mallory]);
    final e = await dinner(net, a, z);

    final p = expensePayload(e)
      ..remove('sig')
      ..['updated_at'] = 9000000000000000;
    await net.clientFor(mallory).sendToUsers({bob}, expenseEventType, p);
    await net.settle();
    expect(
      await b
          .read(signingDaoProvider)
          .rejectedClock(z, RecordKind.expense.wire, e.id),
      isNull,
      reason: 'a far-future refusal is never recorded',
    );

    await a
        .read(expenseAdderProvider.notifier)
        .updateExpense(
          id: e.id,
          roomId: z,
          description: 'Dinner fixed',
          amountCents: 5000,
          currency: 'EUR',
          paidBy: alice,
          splits: {alice: 5000},
          createdAt: e.createdAt,
        );
    await net.settle();
    await a.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    await b.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    final bobRow = await b.read(expensesDaoProvider).getExpenseById(e.id);
    expect(bobRow!.description, 'Dinner fixed');
    expect(bobRow.amountCents, 5000);
  });

  // Finding 4 (major).
  test("a throwaway group's attestation doesn't vouch for a fabricated "
      'device in another group', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    makeUser(net, mallory);
    final z = await trip(net, a, [bob, mallory]);
    final e = await dinner(net, a, z);

    final fake = net.keys.unlistedCrypto(alice, 'FAKEDEV');
    final mc = net.clientFor(mallory).crypto;
    final now = DateTime.now().millisecondsSinceEpoch;
    final meta = await signGroupMeta(
      mc,
      GroupModel(
        roomId: 'X-throwaway',
        name: 'x',
        currency: 'EUR',
        updatedAt: now,
      ),
    );
    await net
        .clientFor(mallory)
        .sendToUsers(
          {bob},
          bootstrapEventType,
          {
            'v': protocolVersion,
            'group': 'X-throwaway',
            'meta': groupMetaPayload(meta),
            'members': [],
            'expenses': [],
            'settlements': [],
            'device_keys': {
              alice: {'FAKEDEV': fake.identity!.key},
            },
          },
        );
    await net.settle();
    final pinned = await b.read(signingDaoProvider).keysFor(alice, 'FAKEDEV');
    expect(pinned.single.group, 'X-throwaway', reason: 'scoped to its group');

    final forged = await signExpense(
      fake,
      ExpenseModel(
        id: e.id,
        roomId: z,
        description: 'Bob owes Mallory',
        amountCents: 99900,
        currency: 'EUR',
        paidBy: alice,
        splitsJson: '{"$bob":99900}',
        createdAt: e.createdAt,
        updatedAt: e.updatedAt + 10,
        origin: e.origin,
      ),
    );
    await net
        .clientFor(mallory)
        .sendToUsers({bob}, expenseEventType, expensePayload(forged));
    await net.settle();
    final row = (await b.read(expensesDaoProvider).getExpenseById(e.id))!;
    final st = signatureStatus(
      row.sig,
      await b.read(signingDaoProvider).allKeys(),
      group: z,
    );
    expect(st.status, isNot(SigStatus.vouched));
    expect(st.status, SigStatus.unverified);
    // Even inside the throwaway group it wouldn't vouch: Bob holds alice's
    // first-hand device list, which lacks FAKEDEV.
    expect(
      signatureStatus(
        row.sig,
        await b.read(signingDaoProvider).allKeys(),
        group: 'X-throwaway',
      ).status,
      SigStatus.unverified,
    );
  });

  // Finding 5.
  test('a malformed split is refused (recorded) and never reaches the '
      'balances', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final z = await trip(net, a, [bob]);
    final ac = net.clientFor(alice).crypto;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final (id, split) in [
      ('bad-type', '{"$bob":"lots"}'),
      ('bad-sum', '{"$bob":1}'),
      ('bad-neg', '{"$bob":-100,"$alice":200}'),
    ]) {
      final e = await signExpense(
        ac,
        ExpenseModel(
          id: id,
          roomId: z,
          description: id,
          amountCents: 100,
          currency: 'EUR',
          paidBy: alice,
          splitsJson: split,
          createdAt: now,
          updatedAt: now,
        ),
        creating: true,
      );
      await net
          .clientFor(alice)
          .sendToUsers({bob}, expenseEventType, expensePayload(e));
    }
    await net.settle();
    for (final id in ['bad-type', 'bad-sum', 'bad-neg']) {
      expect(await b.read(expensesDaoProvider).getExpenseById(id), isNull);
      expect(
        await b
            .read(signingDaoProvider)
            .rejectedClock(z, RecordKind.expense.wire, id),
        now,
        reason: id,
      );
    }
    expect(
      calculateDebts(
        await b.read(expensesDaoProvider).getExpensesForRoom(z),
        const [],
      ),
      isEmpty,
    );
  });

  // Finding 11.
  test('plaintext (unencrypted) to-device events are dropped', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final z = await trip(net, a, [bob]);
    final e = await dinner(net, a, z);
    // A homeserver-injected plaintext event "from alice" (a validly signed
    // newer version, so only the missing encryption can stop it).
    final edit = await signExpense(
      net.clientFor(alice).crypto,
      ExpenseModel(
        id: e.id,
        roomId: z,
        description: 'plaintext',
        amountCents: 4000,
        currency: 'EUR',
        paidBy: alice,
        splitsJson: '{"$alice":2000,"$bob":2000}',
        createdAt: e.createdAt,
        updatedAt: e.updatedAt + 1,
        origin: e.origin,
      ),
    );
    net.injectPlaintext(bob, alice, expenseEventType, expensePayload(edit));
    await net.settle();
    expect(
      (await b.read(expensesDaoProvider).getExpenseById(e.id))!.description,
      'Dinner',
    );
    expect(
      isAcceptedLedgerEvent(type: expenseEventType, encrypted: false),
      isFalse,
    );
    expect(
      isAcceptedLedgerEvent(type: expenseEventType, encrypted: true),
      isTrue,
    );
    expect(isAcceptedLedgerEvent(type: 'm.room_key', encrypted: true), isFalse);
  });
}
