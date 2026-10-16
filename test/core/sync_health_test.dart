/// SyncHealth (Phase F, M2): the app-wide sync-health state machine that turns
/// swallowed replication/digest errors into a surfaced signal. No matrix import.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/in_memory_database.dart';
import 'package:money_ledger/core/sync/sync_health.dart';

void main() {
  group('SyncHealthState transitions', () {
    test('starts healthy', () {
      const s = SyncHealthState();
      expect(s.failing, isFalse);
      expect(s.consecutiveFailures, 0);
      expect(s.lastError, isNull);
    });

    test('one failure is below the threshold (a single blip is tolerated)', () {
      final s = const SyncHealthState().afterFailure('offline', 100);
      expect(s.consecutiveFailures, 1);
      expect(s.failing, isFalse);
      expect(s.lastError, 'offline');
      expect(s.lastErrorAt, 100);
    });

    test('reaching the threshold flips to failing', () {
      var s = const SyncHealthState();
      for (var i = 0; i < kSyncFailureThreshold; i++) {
        s = s.afterFailure('offline', 100 + i);
      }
      expect(s.consecutiveFailures, kSyncFailureThreshold);
      expect(s.failing, isTrue);
    });

    test('a success resets failures and clears the error', () {
      var s = const SyncHealthState()
          .afterFailure('e1', 1)
          .afterFailure('e2', 2);
      expect(s.failing, isTrue);
      s = s.afterSuccess(500);
      expect(s.failing, isFalse);
      expect(s.consecutiveFailures, 0);
      expect(s.lastError, isNull);
      expect(s.lastSuccessAt, 500);
    });

    test('a failure after success preserves the prior lastSuccessAt', () {
      final s = const SyncHealthState()
          .afterSuccess(500)
          .afterFailure('boom', 600);
      expect(s.lastSuccessAt, 500);
      expect(s.lastErrorAt, 600);
    });
  });

  group('unreachable peers (G24)', () {
    test('a peer with no device is tracked but is not a failure', () {
      final s = const SyncHealthState().afterSuccess(
        10,
        reached: {'@a:x'},
        unreachable: {'@b:y'},
      );
      expect(s.unreachablePeers, {'@b:y'});
      expect(s.failing, isFalse);
      expect(s.consecutiveFailures, 0);
    });

    test('a peer leaves the set once a send reaches one of its devices', () {
      final s = const SyncHealthState()
          .afterSuccess(10, unreachable: {'@b:y', '@c:z'})
          .afterSuccess(20, reached: {'@b:y'});
      expect(s.unreachablePeers, {'@c:z'});
    });

    test('a failure keeps the unreachable set', () {
      final s = const SyncHealthState()
          .afterSuccess(10, unreachable: {'@b:y'})
          .afterFailure('boom', 20);
      expect(s.unreachablePeers, {'@b:y'});
    });
  });

  group('SyncHealth notifier', () {
    test('repeated failures then a success drive failing on and off', () {
      final db = openTestDatabase();
      addTearDown(db.close);
      final c = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      );
      addTearDown(c.dispose);
      final notifier = c.read(syncHealthProvider.notifier);

      expect(c.read(syncHealthProvider).failing, isFalse);
      for (var i = 0; i < kSyncFailureThreshold; i++) {
        notifier.reportFailure(Exception('offline'));
      }
      expect(c.read(syncHealthProvider).failing, isTrue);

      notifier.reportSuccess();
      expect(c.read(syncHealthProvider).failing, isFalse);
      expect(c.read(syncHealthProvider).lastSuccessAt, isNotNull);
    });

    test("account A's failure state is gone after switching to B (G4)", () {
      // appDatabaseProvider is swapped exactly on an account switch.
      final dbA = openTestDatabase();
      final dbB = openTestDatabase();
      addTearDown(dbA.close);
      addTearDown(dbB.close);
      var account = dbA;
      final c = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWith((ref) => account)],
      );
      addTearDown(c.dispose);
      c.listen(syncHealthProvider, (_, _) {});

      final notifier = c.read(syncHealthProvider.notifier);
      for (var i = 0; i < kSyncFailureThreshold; i++) {
        notifier.reportFailure(Exception('offline'));
      }
      expect(c.read(syncHealthProvider).failing, isTrue);

      account = dbB; // switch to account B
      c.invalidate(appDatabaseProvider);
      final s = c.read(syncHealthProvider);
      expect(s.failing, isFalse);
      expect(s.lastError, isNull);
      expect(s.lastErrorAt, isNull);
    });
  });

  group('G11 unverified peers', () {
    test(
      'a send that withholds every device of a peer marks it unverified',
      () {
        final s = const SyncHealthState().afterSuccess(
          1,
          reached: {'@a:x'},
          unreachable: {'@b:x', '@c:x'},
          unverified: {'@b:x'},
        );
        expect(s.unreachablePeers, {'@b:x', '@c:x'});
        expect(s.unverifiedPeers, {'@b:x'});
        expect(s.failing, isFalse);
      },
    );

    test('reaching the peer later (or it losing all devices) clears it', () {
      final s = const SyncHealthState(
        unreachablePeers: {'@b:x', '@c:x'},
        unverifiedPeers: {'@b:x', '@c:x'},
      ).afterSuccess(2, reached: {'@b:x'}, unreachable: {'@c:x'});
      expect(s.unverifiedPeers, isEmpty);
      expect(s.unreachablePeers, {'@c:x'});
    });

    test('a failure keeps the unverified set', () {
      final s = const SyncHealthState(
        unverifiedPeers: {'@b:x'},
      ).afterFailure('x', 3);
      expect(s.unverifiedPeers, {'@b:x'});
    });

    test(
      'pendingPeerHint prefers unverified, then no-device, then waiting',
      () {
        const health = SyncHealthState(
          unreachablePeers: {'@b:x', '@c:x'},
          unverifiedPeers: {'@c:x'},
        );
        expect(pendingPeerHint(['@a:x', '@b:x', '@c:x'], health), (
          peer: '@c:x',
          reason: PendingReason.unverified,
        ));
        expect(pendingPeerHint(['@a:x', '@b:x'], health), (
          peer: '@b:x',
          reason: PendingReason.noDevice,
        ));
        expect(pendingPeerHint(['@a:x'], health), (
          peer: '@a:x',
          reason: PendingReason.waiting,
        ));
      },
    );
  });
}
