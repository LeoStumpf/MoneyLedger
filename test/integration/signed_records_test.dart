/// G6 signed records over the in-memory relay: every version is signed by its
/// editor's device; forged versions are refused (and never loop), legit edits
/// by any member are attributed, records stay verifiable after the signing
/// device signs out, and a non-member's digest can't gossip members.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_verifier.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';
const mallory = '@mallory:z.org';
const carol = '@carol:c.org';

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

  Future<String> createGroup(
    ProviderContainer owner,
    FakeMatrixNetwork net,
    List<String> others,
  ) async {
    await net.settle();
    await owner.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await owner.read(groupsDaoProvider).getAllGroups()).single.roomId;
    for (final o in others) {
      await owner.read(memberAdderProvider.notifier).add(groupId, o);
      await net.settle();
    }
    return groupId;
  }

  Future<ExpenseModel> addExpense(
    ProviderContainer user,
    FakeMatrixNetwork net,
    String groupId,
    String paidBy,
  ) async {
    await user
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: groupId,
          description: 'Dinner',
          amountCents: 4000,
          currency: 'EUR',
          paidBy: paidBy,
          splits: {paidBy: 4000},
        );
    await net.settle();
    return (await user.read(expensesDaoProvider).getExpensesForRoom(groupId))
        .single;
  }

  test('an edit by another member is accepted and attributed to them; '
      '"added by" stays with the creator', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final groupId = await createGroup(a, net, [bob]);
    final e = await addExpense(a, net, groupId, alice);

    await b
        .read(expenseAdderProvider.notifier)
        .updateExpense(
          id: e.id,
          roomId: groupId,
          description: 'Dinner (fixed)',
          amountCents: 5000,
          currency: 'EUR',
          paidBy: alice,
          splits: {alice: 5000},
          createdAt: e.createdAt,
        );
    await net.settle();

    for (final c in [a, b]) {
      final row = await c.read(expensesDaoProvider).getExpenseById(e.id);
      expect(row!.description, 'Dinner (fixed)');
      expect(row.origin!.user, alice);
      expect(row.sig!.user, bob);
      final keys = await c.read(signingDaoProvider).keysFor(bob, 'D1');
      expect(signatureStatus(row.sig, keys).status, SigStatus.verified);
    }

    // A delete is a signed version too ("deleted by").
    await a.read(expenseAdderProvider.notifier).deleteExpense(e.id, groupId);
    await net.settle();
    final tomb = await b.read(expensesDaoProvider).getExpenseById(e.id);
    expect(tomb!.deleted, isTrue);
    expect(tomb.sig!.user, alice);
    expect(tomb.origin!.user, alice);
  });

  test('a member forging a version as another member is refused, and the '
      'refused version is not re-sent by anti-entropy', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final m = makeUser(net, mallory);
    final groupId = await createGroup(a, net, [bob, mallory]);
    final e = await addExpense(a, net, groupId, alice);

    // Mallory crafts a newer version "by alice" (claiming alice's real
    // device D1) with her own key, stores it and relays it.
    final impostor = net.keys.unlistedCrypto(alice, 'D1');
    final forged = await signExpense(
      impostor,
      ExpenseModel(
        id: e.id,
        roomId: groupId,
        description: 'Alice owes me',
        amountCents: 99900,
        currency: 'EUR',
        paidBy: alice,
        splitsJson: '{"$alice":99900}',
        createdAt: e.createdAt,
        updatedAt: e.updatedAt + 10,
        origin: e.origin,
      ),
    );
    await m
        .read(expensesDaoProvider)
        .upsertExpenseLww(expenseCompanion(forged));
    await net
        .clientFor(mallory)
        .sendToUsers({bob}, expenseEventType, expensePayload(forged));
    await net.settle();

    final bobRow = await b.read(expensesDaoProvider).getExpenseById(e.id);
    expect(bobRow!.description, 'Dinner');
    expect(
      await b.read(signingDaoProvider).rejectedClock(groupId, 'expense', e.id),
      forged.updatedAt,
    );

    // Digest cycles: mallory's engine may offer the forged version once more
    // at most, then the `rejected` map in bob's digest stops it.
    await m.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    final before = net.sent
        .where((s) => s.sender == mallory && s.type == expenseEventType)
        .length;
    await m.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    await b.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    final after = net.sent
        .where((s) => s.sender == mallory && s.type == expenseEventType)
        .length;
    expect(after, before, reason: 'no repair loop for a refused version');
    expect(
      (await b.read(expensesDaoProvider).getExpenseById(e.id))!.description,
      'Dinner',
    );
  });

  test('records stay verified after the signing device signs out; a new '
      "member's bootstrap vouches for the key", () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final groupId = await createGroup(a, net, [bob]);
    final e = await addExpense(a, net, groupId, alice);

    net.removeDevice(alice); // alice signs out — her D1 key leaves the server

    // Bob had pinned alice's device: still verified for him.
    final bobKeys = await b.read(signingDaoProvider).keysFor(alice, 'D1');
    expect(
      signatureStatus(
        (await b.read(expensesDaoProvider).getExpenseById(e.id))!.sig,
        bobKeys,
      ).status,
      SigStatus.verified,
    );

    // Carol joins via bob: the bootstrap attests alice's key (TOFU inviter).
    final c = makeUser(net, carol);
    await b.read(memberAdderProvider.notifier).add(groupId, carol);
    await net.settle();
    final carolRow = await c.read(expensesDaoProvider).getExpenseById(e.id);
    expect(carolRow, isNotNull);
    final carolKeys = await c.read(signingDaoProvider).keysFor(alice, 'D1');
    final status = signatureStatus(carolRow!.sig, carolKeys);
    expect(status.status, SigStatus.vouched);
    expect(status.vouchedBy, bob);
  });

  test('a write while the signer is not ready is stored pendingSign, not '
      'sent, then signed + delivered by the next digest', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final groupId = await createGroup(a, net, [bob]);

    net.clientFor(alice).crypto.ready = false;
    final e = await addExpense(a, net, groupId, alice);
    expect(e.pendingSign, isTrue);
    expect(
      await b.read(expensesDaoProvider).getExpenseById(e.id),
      isNull,
      reason: 'nothing unsigned is ever sent',
    );

    net.clientFor(alice).crypto.ready = true;
    await a.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    final mine = await a.read(expensesDaoProvider).getExpenseById(e.id);
    expect(mine!.pendingSign, isFalse);
    expect(mine.origin!.user, alice);
    final theirs = await b.read(expensesDaoProvider).getExpenseById(e.id);
    expect(theirs!.sig, mine.sig);
  });

  test('regression: a digest from a non-member gossips no members and gets '
      'no repair / reply', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final groupId = await createGroup(a, net, [bob]);
    await addExpense(a, net, groupId, alice);
    net.clientFor(mallory);

    final membersBefore = await b.read(membersDaoProvider).getMembers(groupId);
    final sentBefore = net.sent.length;
    await net
        .clientFor(mallory)
        .sendToUsers(
          {bob},
          digestEventType,
          {
            'v': protocolVersion,
            'group': groupId,
            'reply': false,
            'meta_updated_at': 0,
            'members': {
              'p-intruder': {
                'status': 'active',
                'updated_at': 1,
                'name': 'Intruder',
                'matrix_id': mallory,
              },
            },
            'expenses': const <String, int>{},
            'settlements': const <String, int>{},
          },
        );
    await net.settle();

    final membersAfter = await b.read(membersDaoProvider).getMembers(groupId);
    expect(membersAfter.length, membersBefore.length);
    expect(membersAfter.any((m) => m.userId == 'p-intruder'), isFalse);
    expect(
      net.sent.skip(sentBefore + 1).where((s) => s.targets.contains(mallory)),
      isEmpty,
      reason: 'no records / digest reply to a non-member',
    );
  });

  test('unsigned member gossip from a member is refused', () async {
    final net = FakeMatrixNetwork();
    final a = makeUser(net, alice);
    final b = makeUser(net, bob);
    final groupId = await createGroup(a, net, [bob]);
    await net
        .clientFor(alice)
        .sendToUsers(
          {bob},
          memberEventType,
          {
            'v': 1,
            'group': groupId,
            'participant_id': 'p-ghost',
            'name': 'Ghost',
            'matrix_id': null,
            'status': 'active',
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
        );
    await net.settle();
    final members = await b.read(membersDaoProvider).getMembers(groupId);
    expect(members.any((m) => m.userId == 'p-ghost'), isFalse);
    expect(
      await b
          .read(signingDaoProvider)
          .rejectedClock(groupId, RecordKind.member.wire, 'p-ghost'),
      isNotNull,
    );
  });
}
