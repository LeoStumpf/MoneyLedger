/// G36: after applying a live record from a peer, the receiver sends its ack
/// digest after the short [ackDebounceProvider] instead of the 5 s poke
/// debounce — so the writer's cloud turns "synced" sooner. Bounded: one fast
/// ack per group per [kFastAckMinGap]; bootstraps keep the long debounce.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const _alice = '@alice:x.org';
const _bob = '@bob:x.org';

void main() {
  group('pokeDelay (pure)', () {
    const normal = Duration(seconds: 5), fast = Duration(seconds: 1);
    test('a live record gets the fast ack', () {
      expect(
        SyncEngine.pokeDelay(
          liveRecord: true,
          lastFastAckAt: null,
          now: 100000,
          normal: normal,
          fast: fast,
        ),
        fast,
      );
    });
    test('a bootstrap / local poke keeps the normal debounce', () {
      expect(
        SyncEngine.pokeDelay(
          liveRecord: false,
          lastFastAckAt: null,
          now: 100000,
          normal: normal,
          fast: fast,
        ),
        normal,
      );
    });
    test('at most one fast ack per group per gap', () {
      Duration at(int now) => SyncEngine.pokeDelay(
        liveRecord: true,
        lastFastAckAt: 100000,
        now: now,
        normal: normal,
        fast: fast,
      );
      expect(at(100000 + kFastAckMinGap.inMilliseconds - 1), normal);
      expect(at(100000 + kFastAckMinGap.inMilliseconds), fast);
    });
    test('never longer than the normal debounce', () {
      expect(
        SyncEngine.pokeDelay(
          liveRecord: true,
          lastFastAckAt: null,
          now: 1,
          normal: const Duration(milliseconds: 1),
          fast: fast,
        ),
        const Duration(milliseconds: 1),
      );
    });
  });

  test('the writer is proven in sync by the fast ack alone', () async {
    final net = FakeMatrixNetwork();
    ProviderContainer device(String user) {
      final db = openTestDatabase();
      net.clientFor(user);
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(user)),
          // The normal debounce never fires within the test: only the fast
          // ack can produce the digest.
          pokeDebounceProvider.overrideWithValue(const Duration(hours: 1)),
          ackDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 1),
          ),
          syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
        ],
      );
      addTearDown(() {
        c.dispose();
        db.close();
      });
      c.listen(ledgerSyncerProvider, (_, _) {});
      c.listen(syncEngineProvider, (_, _) {});
      return c;
    }

    final alice = device(_alice);
    device(_bob);
    await net.settle();
    await alice.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await alice.read(groupsDaoProvider).getAllGroups()).single.roomId;
    await alice.read(memberAdderProvider.notifier).add(groupId, _bob);
    await net.settle();

    int bobDigests() => net.sent
        .where((s) => s.sender == _bob && s.type == digestEventType)
        .length;
    final digestsBefore = bobDigests();

    await alice
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: groupId,
          description: 'Dinner',
          amountCents: 4000,
          currency: 'EUR',
          paidBy: _alice,
          splits: {_alice: 2000, _bob: 2000},
        );
    await net.settle();

    expect(bobDigests(), greaterThan(digestsBefore), reason: 'Bob acked');
    final expense =
        (await alice.read(expensesDaoProvider).getAllExpensesForGroup(groupId))
            .single;
    final state =
        (await alice.read(syncStatesDaoProvider).getSyncStates(groupId))
            .firstWhere((s) => s.userId == _bob);
    expect(state.lastInSyncAt, greaterThanOrEqualTo(expense.updatedAt));

    // A second edit right after: no second fast ack (bounded) — the normal
    // debounce (1 h here) covers it.
    final afterFirst = bobDigests();
    await alice
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: groupId,
          description: 'Taxi',
          amountCents: 1000,
          currency: 'EUR',
          paidBy: _alice,
          splits: {_alice: 500, _bob: 500},
        );
    await net.settle();
    expect(bobDigests(), afterFirst);
  });
}
