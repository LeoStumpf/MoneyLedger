/// G19 regression: an account switch (G4 — the ledger DB is closed and every
/// sync component rebuilt) while sync work is **in flight** must throw
/// nothing, log no "closed DB" / "disposed Ref" errors, and never write into
/// the new account's DB or leak into its sync health.
///
/// The switch is swept across many points of the async chain (after k
/// microtask turns) so every await in SyncEngine / LedgerSyncer /
/// ExpenseAdder is hit at least once mid-flight.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/core/sync/sync_health.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_auth_gateway.dart';
import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.test';
const bob = '@bob:y.org';

/// Log lines that mean async work outlived its DB / provider.
final _badLog = RegExp(
  r're-open|disposed|Bad state|Unmounted',
  caseSensitive: false,
);

void main() {
  final logs = <String>[];
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    logs.clear();
    originalDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  });
  tearDown(() => debugPrint = originalDebugPrint);

  /// The device under test: real auth flow (fake gateway), one in-memory DB
  /// per account, the transport following the signed-in account.
  Future<ProviderContainer> makeSwitchingDevice(FakeMatrixNetwork net) async {
    final gateway = FakeAuthGateway();
    final c = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWith((ref) => gateway),
        accountDatabaseOpenerProvider.overrideWithValue(
          (_) => openTestDatabase(),
        ),
        ledgerTransportProvider.overrideWith((ref) {
          final id = ref.watch(accountUserIdProvider);
          return id == null
              ? Completer<LedgerTransport>()
                    .future // signed out: idle
              : Future.value(net.clientFor(id));
        }),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
    addTearDown(() {
      c.dispose();
      gateway.dispose();
    });
    c.listen(accountUserIdProvider, (_, _) {});
    c.listen(ledgerSyncerProvider, (_, _) {});
    c.listen(syncEngineProvider, (_, _) {});
    c.listen(syncHealthProvider, (_, _) {});
    await login(c, 'alice');
    return c;
  }

  ProviderContainer makePeer(FakeMatrixNetwork net, String userId) {
    final db = openTestDatabase();
    net.clientFor(userId);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
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

  Future<String> seed(ProviderContainer a, FakeMatrixNetwork net) async {
    await net.settle();
    await a.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await a.read(groupsDaoProvider).getAllGroups()).single.roomId;
    await a.read(memberAdderProvider.notifier).add(groupId, bob);
    await net.settle();
    // Bob misses one expense, so the digest exchange below does real repair
    // work (more awaits to interrupt).
    net.dropWhere = (_, target, type) =>
        target == bob && type == expenseEventType;
    await addExpense(a, groupId, 'Missed by bob');
    await net.settle();
    net.dropWhere = null;
    return groupId;
  }

  /// Switches the device from alice to carol and lets everything settle.
  Future<void> switchToCarol(ProviderContainer c, FakeMatrixNetwork net) async {
    await c.read(authProvider.notifier).logout();
    await c.read(loginStateProvider.future);
    await login(c, 'carol');
    await net.settle();
  }

  /// The new account's DB must be untouched by the old account's sync, and
  /// its health must not inherit the old account's in-flight failures.
  Future<void> expectCleanSwitch(
    ProviderContainer c,
    String groupId,
    int k,
  ) async {
    final reason = 'switch after $k microtask turns';
    expect(c.read(accountUserIdProvider), '@carol:x.test', reason: reason);
    expect(
      await c.read(groupsDaoProvider).getAllGroups(),
      isEmpty,
      reason: reason,
    );
    expect(
      await c.read(membersDaoProvider).getMembers(groupId),
      isEmpty,
      reason: reason,
    );
    expect(
      await c.read(expensesDaoProvider).getAllExpensesForGroup(groupId),
      isEmpty,
      reason: reason,
    );
    expect(
      await c.read(syncStatesDaoProvider).getSyncStates(groupId),
      isEmpty,
      reason: reason,
    );
    final health = c.read(syncHealthProvider);
    expect(health.consecutiveFailures, 0, reason: reason);
    expect(health.lastError, isNull, reason: reason);
    expect(logs.where(_badLog.hasMatch), isEmpty, reason: reason);
  }

  Future<void> microtaskTurns(int k) async {
    for (var i = 0; i < k; i++) {
      await Future<void>.microtask(() {});
    }
  }

  test('switching accounts mid digest exchange is clean', () async {
    for (var k = 0; k <= 40; k += 2) {
      final net = FakeMatrixNetwork();
      final a = await makeSwitchingDevice(net);
      final b = makePeer(net, bob);
      final groupId = await seed(a, net);

      // Bob's digest reaches alice → alice repairs bob + replies; switch
      // alice's device to carol somewhere inside that chain.
      unawaited(b.read(syncEngineProvider).broadcastDigests());
      await microtaskTurns(k);
      await switchToCarol(a, net);

      await expectCleanSwitch(a, groupId, k);
    }
  });

  test(
    'switching accounts while an inbound record is being applied is clean',
    () async {
      for (var k = 0; k <= 30; k += 2) {
        final net = FakeMatrixNetwork();
        final a = await makeSwitchingDevice(net);
        final b = makePeer(net, bob);
        final groupId = await seed(a, net);

        // Bob's expense + the bootstrap-like digest chain race the switch.
        unawaited(addExpense(b, groupId, 'From bob'));
        await microtaskTurns(k);
        await switchToCarol(a, net);

        await expectCleanSwitch(a, groupId, k);
      }
    },
  );

  test('switching accounts while a local write replicates is clean', () async {
    for (var k = 0; k <= 30; k += 2) {
      final net = FakeMatrixNetwork();
      final a = await makeSwitchingDevice(net);
      makePeer(net, bob);
      final groupId = await seed(a, net);

      final write = addExpense(a, groupId, 'Racing the switch');
      await microtaskTurns(k);
      await switchToCarol(a, net);
      // The user action itself never throws, whatever point it reached.
      await write;

      await expectCleanSwitch(a, groupId, k);
    }
  });

  test('disposing the container mid-flight throws nothing', () async {
    // Teardown order of every integration test: container first, then DB.
    for (var k = 0; k <= 30; k += 3) {
      final net = FakeMatrixNetwork();
      final db = openTestDatabase();
      net.clientFor(alice);
      final a = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(alice)),
          pokeDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 1),
          ),
          syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
        ],
      );
      a.listen(ledgerSyncerProvider, (_, _) {});
      a.listen(syncEngineProvider, (_, _) {});
      final b = makePeer(net, bob);
      final groupId = await seed(a, net);

      unawaited(b.read(syncEngineProvider).broadcastDigests());
      unawaited(addExpense(b, groupId, 'From bob'));
      await microtaskTurns(k);
      a.dispose();
      await db.close();
      await net.settle();

      expect(
        logs.where(_badLog.hasMatch),
        isEmpty,
        reason: 'dispose after $k microtask turns',
      );
    }
  });
}

Future<void> login(ProviderContainer c, String user) async {
  await c
      .read(authProvider.notifier)
      .login(
        resolvedHomeserver: 'https://x.test',
        username: user,
        password: 'pw',
      );
  await c.read(loginStateProvider.future);
  await c.read(authGatewayProvider.future);
}

Future<void> addExpense(
  ProviderContainer c,
  String groupId,
  String description,
) => c
    .read(expenseAdderProvider.notifier)
    .addExpense(
      roomId: groupId,
      description: description,
      amountCents: 4000,
      currency: 'EUR',
      paidBy: alice,
      splits: {alice: 2000, bob: 2000},
    );
