/// First-login recovery (G30): a fresh device with an empty DB asks the user's
/// own other devices for everything (`resync_request{scope: all}`) and keeps
/// retrying with backoff while nothing has arrived; the groups page shows
/// "Restoring…" meanwhile ([selfRecoveryProvider]).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/self_recovery.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';
import '../helpers/manual_timers.dart';

const _alice = '@alice:x.org';

// Distinct durations so each timer is identifiable. They are never waited for
// in real time: [ManualTimers] fires them explicitly (G15 — no wall-clock
// dependence, so nothing flakes under CPU load).
const _retry1 = Duration(seconds: 1);
const _retry2 = Duration(seconds: 2);
const _retry3 = Duration(seconds: 3);
const _retries = [_retry1, _retry2, _retry3];
const _timeout = Duration(minutes: 3);

void main() {
  late ManualTimers timers;
  setUp(() => timers = ManualTimers());

  ProviderContainer makeDevice(
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
        selfResyncRetryDelaysProvider.overrideWithValue(_retries),
        selfRecoveryTimeoutProvider.overrideWithValue(_timeout),
        selfRecoveryTimerFactoryProvider.overrideWithValue(timers.call),
      ],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    container.listen(syncEngineProvider, (_, _) {});
    container.listen(selfRecoveryProvider, (_, _) {});
    return container;
  }

  /// Alice's first device with one group (+ an expense), settled.
  Future<ProviderContainer> aliceWithGroup(FakeMatrixNetwork net) async {
    final d1 = makeDevice(net, _alice);
    await net.settle();
    await d1.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await d1.read(groupsDaoProvider).watchAllGroups().first).first.roomId;
    await d1
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: groupId,
          description: 'Dinner',
          amountCents: 4000,
          currency: 'EUR',
          paidBy: _alice,
          splits: {_alice: 4000},
        );
    await net.settle();
    return d1;
  }

  int selfResyncsFrom(FakeMatrixNetwork net, String userId) => net.sent
      .where(
        (s) =>
            s.sender == userId &&
            s.type == resyncRequestEventType &&
            s.content['scope'] == 'all',
      )
      .length;

  Future<List<String>> groupNames(ProviderContainer c) async =>
      (await c.read(groupsDaoProvider).getAllGroups())
          .map((g) => g.name)
          .toList();

  /// "The [delay] backoff elapses": fires that retry timer, then lets the
  /// resulting request round-trip settle.
  Future<void> elapseRetry(FakeMatrixNetwork net, Duration delay) async {
    expect(timers.fireWhere(delay), 1, reason: 'retry after $delay pending');
    await net.settle();
  }

  int pendingRetries() =>
      _retries.fold(0, (n, d) => n + timers.pendingWith(d).length);

  test(
    'a lost first resync_request is retried and the device recovers',
    () async {
      final net = FakeMatrixNetwork();
      await aliceWithGroup(net);

      // The new device's first request never reaches device 1.
      var dropped = 0;
      net.dropWhere = (sender, target, type) =>
          type == resyncRequestEventType && dropped++ == 0;
      final d2 = makeDevice(net, _alice, device: 'D2');
      await net.settle();
      expect(await groupNames(d2), isEmpty);
      expect(d2.read(selfRecoveryProvider), isTrue);

      await elapseRetry(net, _retry1);

      expect(dropped, greaterThanOrEqualTo(2), reason: 'a retry went out');
      expect(await groupNames(d2), ['Trip']);
      expect(
        d2.read(selfRecoveryProvider),
        isFalse,
        reason: 'restoring ends once the bootstrap landed',
      );
      expect(pendingRetries(), 0, reason: 'no further retry scheduled');
    },
  );

  test('no retry once the first request was answered', () async {
    final net = FakeMatrixNetwork();
    await aliceWithGroup(net);
    final before = selfResyncsFrom(net, _alice); // device 1's own (empty) start

    final d2 = makeDevice(net, _alice, device: 'D2');
    await net.settle();
    expect(await groupNames(d2), ['Trip']);

    // The answered request cancelled its retry: nothing left to fire.
    expect(pendingRetries(), 0);
    expect(selfResyncsFrom(net, _alice) - before, 1);
    expect(d2.read(selfRecoveryProvider), isFalse);
  });

  test('"restoring" is shown while the other device stays silent, '
      'and the retries stop after the backoff schedule', () async {
    final net = FakeMatrixNetwork();
    await aliceWithGroup(net);
    final before = selfResyncsFrom(net, _alice);

    // Device 1 is "not running": every request to it is lost.
    net.dropWhere = (sender, target, type) => type == resyncRequestEventType;
    final d2 = makeDevice(net, _alice, device: 'D2');
    await net.settle();
    expect(d2.read(selfRecoveryProvider), isTrue);

    for (final delay in _retries) {
      await elapseRetry(net, delay);
    }

    expect(
      selfResyncsFrom(net, _alice) - before,
      4,
      reason: 'first + 3 retries',
    );
    expect(pendingRetries(), 0, reason: 'out of retries: stop asking');
    expect(await groupNames(d2), isEmpty);
    expect(
      d2.read(selfRecoveryProvider),
      isTrue,
      reason: 'only the UI timeout ends "restoring"',
    );
  });

  test('"restoring" falls back to the empty state after the timeout', () async {
    final net = FakeMatrixNetwork();
    await aliceWithGroup(net);
    net.dropWhere = (sender, target, type) => type == resyncRequestEventType;
    final d2 = makeDevice(net, _alice, device: 'D2');
    await net.settle();
    expect(d2.read(selfRecoveryProvider), isTrue);

    expect(timers.fireWhere(_timeout), 1, reason: 'UI timeout pending');
    expect(d2.read(selfRecoveryProvider), isFalse);
  });

  test(
    'no other own device: nothing to restore, no "restoring", no retry',
    () async {
      final net = FakeMatrixNetwork();
      final only = makeDevice(net, _alice);
      await net.settle();

      expect(only.read(selfRecoveryProvider), isFalse);
      expect(selfResyncsFrom(net, _alice), 1);
      expect(pendingRetries(), 0);
    },
  );

  test(
    'a send that fails at first (encryption not ready) is retried',
    () async {
      final net = FakeMatrixNetwork();
      await aliceWithGroup(net);

      final t2 = net.clientFor(_alice, device: 'D2')..unavailable = true;
      final d2 = makeDevice(net, _alice, device: 'D2');
      await net.settle();
      expect(await groupNames(d2), isEmpty);
      expect(d2.read(selfRecoveryProvider), isTrue);

      t2.unavailable = false; // keys uploaded / encryption ready
      await elapseRetry(net, _retry1);

      expect(await groupNames(d2), ['Trip']);
      expect(d2.read(selfRecoveryProvider), isFalse);
    },
  );
}
