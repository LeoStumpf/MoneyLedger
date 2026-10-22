/// G31: one Android background sync round (`runBackgroundRound`), driven
/// against the fake relay and file-backed Drift — no Matrix, no WorkManager.
/// The "closed app" device is a buffered fake transport with no listeners:
/// payloads queue there like to-device messages queue on the homeserver.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/background/background_round.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/database/daos/sync_states_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/history/snapshot_store.dart';
import 'package:money_ledger/features/notifications/change_notices.dart';

import '../helpers/fake_ledger_network.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

class FakeSession implements BackgroundSession {
  FakeSession(this.transport, {this.onFetch});

  @override
  final LedgerTransport transport;
  final Future<void> Function()? onFetch;
  int fetches = 0;
  bool closed = false;

  @override
  String get userId => transport.userId;

  @override
  Future<void> fetchOnce({Duration wait = Duration.zero}) async {
    fetches++;
    await onFetch?.call();
  }

  @override
  Future<void> close() async => closed = true;
}

void main() {
  late Directory tmp;
  late FakeMatrixNetwork net;
  final containers = <ProviderContainer>[];
  final dbs = <AppDatabase>[];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bg_round_');
    net = FakeMatrixNetwork(bufferInbound: true);
  });

  tearDown(() async {
    for (final c in containers) {
      c.dispose();
    }
    containers.clear();
    for (final d in dbs) {
      if (!d.isClosed) await d.close();
    }
    dbs.clear();
    await tmp.delete(recursive: true);
  });

  /// A file-backed ledger DB per (user, device) — survives close/reopen like
  /// the real per-account file.
  AppDatabase openDb(String user, {String device = 'D1'}) {
    final db = AppDatabase.forTesting(
      NativeDatabase(File('${tmp.path}/${user.hashCode}_$device.sqlite')),
    );
    dbs.add(db);
    return db;
  }

  /// The running app on a device.
  ProviderContainer openApp(String user, {String device = 'D1'}) {
    final db = openDb(user, device: device);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith(
          (ref) => net.clientFor(user, device: device),
        ),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
    containers.add(c);
    c.listen(ledgerSyncerProvider, (_, _) {});
    c.listen(syncEngineProvider, (_, _) {});
    return c;
  }

  /// "Closes" the app: sync components detach (inbound now buffers), DB closed.
  Future<void> closeApp(ProviderContainer c) async {
    final db = c.read(appDatabaseProvider);
    c.dispose();
    containers.remove(c);
    await db.close();
  }

  Future<BackgroundRoundResult> round(
    String user, {
    String device = 'D1',
    FakeSession? session,
    Future<bool> Function()? tryAcquire,
    Future<void>? abort,
    Duration timeout = const Duration(seconds: 10),
    Duration digestMaxAge = const Duration(minutes: 15),
    Duration inFlightGrace = const Duration(milliseconds: 200),
    SnapshotStore? Function(String dbName)? snapshotStores,
    Duration snapshotMinRemaining = Duration.zero,
    int Function()? clock,
    Future<void> Function(List<ChangeNotice>)? notify,
  }) => runBackgroundRound(
    tryAcquire: tryAcquire ?? () async => true,
    openSession: () async =>
        session ?? FakeSession(net.clientFor(user, device: device)),
    openDatabase: (_) => openDb(user, device: device),
    abort: abort,
    timeout: timeout,
    quietPeriod: const Duration(milliseconds: 100),
    pokeDebounce: const Duration(milliseconds: 1),
    followUpWait: Duration.zero,
    digestMaxAge: digestMaxAge,
    inFlightGrace: inFlightGrace,
    snapshotStores: snapshotStores,
    snapshotMinRemaining: snapshotMinRemaining,
    clock: clock,
    notify: notify,
  );

  /// Alice and Bob share "Trip"; both apps ran once, Bob's is now closed.
  Future<(ProviderContainer, String)> sharedGroupBobClosed() async {
    net.clientFor(alice);
    net.clientFor(bob);
    final a = openApp(alice);
    final b = openApp(bob);
    await net.settle();
    await a.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final groupId =
        (await a.read(groupsDaoProvider).getAllGroups()).single.roomId;
    await a.read(memberAdderProvider.notifier).add(groupId, bob);
    await net.settle();
    expect(await b.read(groupsDaoProvider).getAllGroups(), hasLength(1));
    await closeApp(b);
    return (a, groupId);
  }

  Future<List<String>> bobExpenseDescriptions() async {
    final db = openDb(bob);
    final rows = await ExpensesDao(db).getAllExpensesForGroup(
      (await GroupsDao(db).getAllGroups()).single.roomId,
    );
    await db.close();
    return [for (final e in rows) e.description];
  }

  test('applies records queued while the app was closed and answers the '
      "peer's digest", () async {
    final (a, groupId) = await sharedGroupBobClosed();
    await a
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: groupId,
          description: 'G31 bg',
          amountCents: 100,
          currency: 'EUR',
          paidBy: alice,
          splits: {alice: 50, bob: 50},
        );
    await a.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    net.sent.clear();

    final result = await round(bob);
    await net.settle();

    expect(result.status, BackgroundRoundStatus.completed);
    expect(result.received, greaterThanOrEqualTo(2)); // expense + digest
    expect(await bobExpenseDescriptions(), ['G31 bg']);
    // Bob answered Alice's digest (reply: true) …
    expect(
      net.sent.where(
        (s) =>
            s.sender == bob &&
            s.type == digestEventType &&
            s.targets.contains(alice) &&
            s.content['reply'] == true,
      ),
      isNotEmpty,
    );
    // … which proved to Alice that Bob has everything ("Synced").
    final states = await a.read(syncStatesDaoProvider).getSyncStates(groupId);
    expect(
      states.singleWhere((s) => s.userId == bob).lastInSyncAt,
      greaterThan(0),
    );
  });

  test("answers a pending resync_request from the user's new device", () async {
    final (a, groupId) = await sharedGroupBobClosed();
    await closeApp(a); // Alice's phone app is closed too.
    // Alice signs in on a new device: empty DB → resync_request{all} to self,
    // which waits (buffered) for her phone.
    final d2 = openApp(alice, device: 'D2');
    await net.settle();
    expect(await d2.read(groupsDaoProvider).getAllGroups(), isEmpty);

    final result = await round(alice);
    await net.settle();

    expect(result.status, BackgroundRoundStatus.completed);
    expect(
      net.sent.where(
        (s) =>
            s.sender == alice &&
            s.type == bootstrapEventType &&
            s.content['group'] == groupId,
      ),
      isNotEmpty,
    );
    expect(
      (await d2.read(groupsDaoProvider).getAllGroups()).single.roomId,
      groupId,
    );
  });

  test(
    'skips without opening anything while the app holds the stores',
    () async {
      var opened = false;
      final result = await runBackgroundRound(
        tryAcquire: () async => false,
        openSession: () async {
          opened = true;
          return null;
        },
        openDatabase: (_) => throw StateError('must not open'),
      );
      expect(result.status, BackgroundRoundStatus.skippedBusy);
      expect(opened, isFalse);
    },
  );

  test('skips when signed out', () async {
    final result = await runBackgroundRound(
      tryAcquire: () async => true,
      openSession: () async => null,
      openDatabase: (_) => throw StateError('must not open'),
    );
    expect(result.status, BackgroundRoundStatus.skippedSignedOut);
  });

  test('skips (and sends nothing) when the account disabled it', () async {
    final (a, groupId) = await sharedGroupBobClosed();
    final db = openDb(bob);
    await SettingsDao(db).setBackgroundSyncEnabled(false);
    await db.close();
    await a.read(syncEngineProvider).broadcastDigests();
    await net.settle();
    net.sent.clear();

    final session = FakeSession(net.clientFor(bob));
    final result = await round(bob, session: session);

    expect(result.status, BackgroundRoundStatus.skippedDisabled);
    expect(session.fetches, 0);
    expect(session.closed, isTrue);
    expect(net.sent.where((s) => s.sender == bob), isEmpty);
    expect(groupId, isNotEmpty);
  });

  test('respects the time budget and still shuts down cleanly', () async {
    await sharedGroupBobClosed();
    final session = FakeSession(
      net.clientFor(bob),
      onFetch: () => Completer<void>().future,
    ); // /sync hangs
    final sw = Stopwatch()..start();
    final result = await round(
      bob,
      session: session,
      timeout: const Duration(milliseconds: 300),
    );
    expect(result.status, BackgroundRoundStatus.timedOut);
    expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
    expect(session.closed, isTrue);
    expect(dbs.last.isClosed, isTrue);
  });

  test('stops early when the app asks it to', () async {
    await sharedGroupBobClosed();
    final abort = Completer<void>();
    final session = FakeSession(
      net.clientFor(bob),
      onFetch: () async {
        abort.complete(); // the app starts mid-round
        await Completer<void>().future;
      },
    );
    final result = await round(bob, session: session, abort: abort.future);
    expect(result.status, BackgroundRoundStatus.aborted);
    expect(session.closed, isTrue);
  });

  // G18 review (finding 7): a stopped round waits (bounded) for the step in
  // flight before it closes the stores under it.
  test('an abort waits for the in-flight /sync before closing', () async {
    await sharedGroupBobClosed();
    final abort = Completer<void>();
    var fetchDone = false;
    var fetchDoneAtClose = false;
    late FakeSession session;
    session = _ClosingSession(
      net.clientFor(bob),
      onFetch: () async {
        abort.complete(); // the app starts mid-/sync
        await Future<void>.delayed(const Duration(milliseconds: 150));
        fetchDone = true;
      },
      onClose: () => fetchDoneAtClose = fetchDone,
    );
    final result = await round(
      bob,
      session: session,
      abort: abort.future,
      inFlightGrace: const Duration(seconds: 2),
    );
    expect(result.status, BackgroundRoundStatus.aborted);
    expect(session.closed, isTrue);
    expect(fetchDoneAtClose, isTrue);
  });

  // G18 review 2 (Minor 5): a request can outlast the grace (90 s header
  // timeout vs 10 s) — the round aborts it before closing the stores.
  test('a stopped round aborts the requests in flight before it closes the '
      'stores', () async {
    await sharedGroupBobClosed();
    final abort = Completer<void>();
    final request = Completer<void>(); // a /sync that would hang for long
    var aborted = false;
    var fetchSettledAtClose = false;
    var fetchSettled = false;
    late FakeSession session;
    session = _ClosingSession(
      net.clientFor(bob),
      onFetch: () async {
        abort.complete(); // the app starts mid-/sync
        try {
          await request.future;
        } finally {
          fetchSettled = true;
        }
      },
      onClose: () => fetchSettledAtClose = fetchSettled,
    );
    final db = openDb(bob);
    var dbOpenAtSettle = false;
    final result = await runBackgroundRound(
      tryAcquire: () async => true,
      openSession: () async => session,
      openDatabase: (_) => db,
      abort: abort.future,
      abortRequests: () {
        aborted = true;
        dbOpenAtSettle = !db.isClosed;
        // Closing the HTTP client fails the request at once.
        request.completeError(StateError('Client is already closed'));
      },
      quietPeriod: const Duration(milliseconds: 100),
      pokeDebounce: const Duration(milliseconds: 1),
      // Far shorter than the hanging request: without the abort the stores
      // would be closed under it.
      inFlightGrace: const Duration(milliseconds: 100),
    );
    expect(result.status, BackgroundRoundStatus.aborted);
    expect(aborted, isTrue);
    expect(dbOpenAtSettle, isTrue, reason: 'aborted before the DB closed');
    expect(fetchSettledAtClose, isTrue, reason: 'settled before close');
    expect(db.isClosed, isTrue);
  });

  test('a session still opening when stopped is closed before the round '
      'returns', () async {
    await sharedGroupBobClosed();
    final opened = Completer<void>();
    final session = FakeSession(net.clientFor(bob));
    final result = await runBackgroundRound(
      tryAcquire: () async => true,
      openSession: () async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        opened.complete();
        return session;
      },
      openDatabase: (_) => openDb(bob),
      timeout: const Duration(milliseconds: 50),
      inFlightGrace: const Duration(seconds: 2),
    );
    expect(result.status, BackgroundRoundStatus.timedOut);
    expect(opened.isCompleted, isTrue);
    expect(session.closed, isTrue);
  });

  group('G58 daily snapshot', () {
    final day1 = DateTime(2026, 10, 16, 9).millisecondsSinceEpoch;
    final day2 = DateTime(2026, 10, 17, 9).millisecondsSinceEpoch;

    test('written once per day, only when the ledger changed', () async {
      final (a, groupId) = await sharedGroupBobClosed();
      final store = InMemorySnapshotStore();
      final names = <String>[];
      SnapshotStore? stores(String name) {
        names.add(name);
        return store;
      }

      var result = await round(bob, snapshotStores: stores, clock: () => day1);
      expect(result.status, BackgroundRoundStatus.completed);
      expect(result.snapshot, isTrue);
      expect(store.files.keys, ['2026-10-16.json']);
      expect(store.files.values.single, contains('"account": "$bob"'));
      expect(names.toSet(), hasLength(1));
      expect(names.single, startsWith('money_ledger_'));

      // Same day: not again — even with a new expense from Alice.
      await a
          .read(expenseAdderProvider.notifier)
          .addExpense(
            roomId: groupId,
            description: 'G58',
            amountCents: 100,
            currency: 'EUR',
            paidBy: alice,
            splits: {alice: 50, bob: 50},
          );
      await net.settle();
      result = await round(bob, snapshotStores: stores, clock: () => day1);
      expect(result.snapshot, isFalse);
      expect(await bobExpenseDescriptions(), ['G58']);

      // Next day: changed since → today's file; the day after: unchanged.
      result = await round(bob, snapshotStores: stores, clock: () => day2);
      expect(result.snapshot, isTrue);
      expect(store.files['2026-10-17.json'], contains('G58'));
      result = await round(
        bob,
        snapshotStores: stores,
        clock: () => DateTime(2026, 10, 18, 9).millisecondsSinceEpoch,
      );
      expect(result.snapshot, isFalse);
      expect(store.files.keys, ['2026-10-16.json', '2026-10-17.json']);
    });

    test('no store / no group / budget almost used up → none', () async {
      // No group yet: nothing to protect.
      net.clientFor(bob);
      final store = InMemorySnapshotStore();
      var result = await round(
        bob,
        snapshotStores: (_) => store,
        clock: () => day1,
      );
      expect(result.status, BackgroundRoundStatus.completed);
      expect(result.snapshot, isFalse);

      await sharedGroupBobClosed();
      // Less budget left than a snapshot may take: skipped (stays due).
      result = await round(
        bob,
        snapshotStores: (_) => store,
        snapshotMinRemaining: const Duration(hours: 1),
        clock: () => day2,
      );
      expect(result.status, BackgroundRoundStatus.completed);
      expect(result.snapshot, isFalse);
      expect(store.files, isEmpty);
      // Without a store (web / tests) nothing either.
      result = await round(bob, clock: () => day2);
      expect(result.snapshot, isFalse);
      // Next round with time left: written.
      result = await round(
        bob,
        snapshotStores: (_) => store,
        clock: () => day2,
      );
      expect(result.snapshot, isTrue);
      expect(store.files.keys, ['2026-10-17.json']);
    });

    test(
      'a stop during the snapshot waits for the write, then closes',
      () async {
        await sharedGroupBobClosed();
        final store = _BlockingStore();
        final abort = Completer<void>();
        final done = round(
          bob,
          snapshotStores: (_) => store,
          clock: () => day1,
          abort: abort.future,
          inFlightGrace: const Duration(seconds: 5),
        );
        await store.started.future;
        abort.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        store.release.complete();
        final result = await done;
        expect(result.status, BackgroundRoundStatus.aborted);
        // The write in flight finished (atomic) before the DB was closed.
        expect(store.files.keys, ['2026-10-16.json']);
      },
    );
  });

  test('broadcasts its own digest only when the last one is stale', () async {
    final (a, groupId) = await sharedGroupBobClosed();

    // Bob's last digest (sent while his app ran) is fresh: no broadcast.
    var result = await round(bob);
    expect(result.status, BackgroundRoundStatus.completed);
    expect(result.broadcastDigests, isFalse);

    // Pretend it was long ago → the round sends one.
    final db = openDb(bob);
    await SyncStatesDao(db).markDigestSent(groupId, alice, 1);
    await SyncStatesDao(db).markDigestSent(groupId, bob, 1);
    await db.close();
    net.sent.clear();
    result = await round(bob);
    await net.settle();
    expect(result.broadcastDigests, isTrue);
    expect(
      net.sent.where(
        (s) =>
            s.sender == bob &&
            s.type == digestEventType &&
            s.content['reply'] == false,
      ),
      isNotEmpty,
    );
    expect(a, isNotNull);
  });

  group('G72 notifications', () {
    Future<void> addExpense(ProviderContainer a, String groupId, String d) => a
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: groupId,
          description: d,
          amountCents: 1000,
          currency: 'EUR',
          paidBy: alice,
          splits: {alice: 500, bob: 500},
        );

    test("others' changes queued while the app was closed → one notice "
        'per group', () async {
      final (a, groupId) = await sharedGroupBobClosed();
      await addExpense(a, groupId, 'Dinner');
      await net.settle();

      final posted = <List<ChangeNotice>>[];
      final result = await round(bob, notify: (n) async => posted.add(n));
      expect(result.status, BackgroundRoundStatus.completed);
      expect(result.notified, 1);
      final notice = posted.single.single;
      expect(notice.groupId, groupId);
      expect(notice.groupName, 'Trip');
      expect(notice.newGroup, isFalse);
      final c = notice.changes.single;
      expect(c.action, NoticeAction.added);
      expect(c.description, 'Dinner');
      expect(c.author, 'alice');

      // Nothing new → the next round posts nothing.
      posted.clear();
      final again = await round(bob, notify: (n) async => posted.add(n));
      expect(again.notified, 0);
      expect(posted, isEmpty);
    });

    test('an edit of a record held before is "edited"', () async {
      final (a, groupId) = await sharedGroupBobClosed();
      await addExpense(a, groupId, 'Dinner');
      await net.settle();
      await round(bob, notify: (_) async {});

      final e =
          (await a.read(expensesDaoProvider).getAllExpensesForGroup(groupId))
              .single;
      await a
          .read(expenseAdderProvider.notifier)
          .updateExpense(
            id: e.id,
            roomId: groupId,
            createdAt: e.createdAt,
            description: 'Dinner + wine',
            amountCents: 1200,
            currency: 'EUR',
            paidBy: alice,
            splits: {alice: 600, bob: 600},
          );
      await net.settle();
      final posted = <ChangeNotice>[];
      await round(bob, notify: (n) async => posted.addAll(n));
      final c = posted.single.changes.single;
      expect(c.action, NoticeAction.edited);
      expect(c.description, 'Dinner + wine');
    });

    test('being added to a group while the app was closed → "you were '
        'added"', () async {
      net.clientFor(alice);
      net.clientFor(bob);
      final a = openApp(alice);
      await closeApp(openApp(bob));
      await net.settle();
      await a.read(groupCreatorProvider.notifier).create('Flat', 'EUR');
      final groupId =
          (await a.read(groupsDaoProvider).getAllGroups()).single.roomId;
      await a.read(memberAdderProvider.notifier).add(groupId, bob);
      await net.settle();

      final posted = <ChangeNotice>[];
      await round(bob, notify: (n) async => posted.addAll(n));
      expect(posted.single.groupName, 'Flat');
      expect(posted.single.newGroup, isTrue);
    });

    test('notifications turned off → nothing is posted', () async {
      final (a, groupId) = await sharedGroupBobClosed();
      final db = openDb(bob);
      await SettingsDao(db).setNotificationsEnabled(false);
      await db.close();
      await addExpense(a, groupId, 'Dinner');
      await net.settle();
      var called = false;
      final result = await round(bob, notify: (_) async => called = true);
      expect(result.status, BackgroundRoundStatus.completed);
      expect(called, isFalse);
      expect(await bobExpenseDescriptions(), ['Dinner']);
    });

    test('our own changes are not announced', () async {
      final (a, groupId) = await sharedGroupBobClosed();
      // Bob's app writes, then closes; the round finds only Alice's echo
      // traffic (digests) — nothing by someone else.
      final b = openApp(bob);
      await b
          .read(expenseAdderProvider.notifier)
          .addExpense(
            roomId: groupId,
            description: 'Mine',
            amountCents: 1000,
            currency: 'EUR',
            paidBy: bob,
            splits: {alice: 500, bob: 500},
          );
      await net.settle();
      await closeApp(b);
      await a.read(syncEngineProvider).broadcastDigests();
      await net.settle();
      final posted = <ChangeNotice>[];
      await round(bob, notify: (n) async => posted.addAll(n));
      expect(posted, isEmpty);
    });
  });
}

/// G58: a snapshot store whose writes wait for [release].
class _BlockingStore extends InMemorySnapshotStore {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> write(String name, String content) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    await super.write(name, content);
  }
}

class _ClosingSession extends FakeSession {
  _ClosingSession(super.transport, {super.onFetch, required this.onClose});
  final void Function() onClose;

  @override
  Future<void> close() async {
    onClose();
    await super.close();
  }
}
