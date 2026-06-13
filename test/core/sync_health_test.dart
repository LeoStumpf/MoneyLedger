/// SyncHealth (Phase F, M2): the app-wide sync-health state machine that turns
/// swallowed replication/digest errors into a surfaced signal. No matrix import.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  group('SyncHealth notifier', () {
    test('repeated failures then a success drive failing on and off', () {
      final c = ProviderContainer();
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
  });
}
