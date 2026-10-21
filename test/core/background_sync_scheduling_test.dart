/// G31: the OS registration of the periodic background sync follows the
/// session and the per-account setting (default on).
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/background/background_scheduler.dart';
import 'package:money_ledger/core/background/background_sync_provider.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/onboarding/onboarding_provider.dart';

import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/models/link_model.dart';

import '../helpers/fake_auth_gateway.dart';

class RecordingScheduler implements BackgroundScheduler {
  final calls = <String>[];

  /// G33: make `schedule()` throw (the OS refused the registration).
  bool failSchedule = false;
  @override
  Future<void> schedule() async {
    calls.add('schedule');
    if (failSchedule) throw StateError('WorkManager refused');
  }

  @override
  Future<void> cancel() async => calls.add('cancel');

  @override
  Future<void> runOnce({Duration delay = Duration.zero}) async =>
      calls.add('runOnce:${delay.inSeconds}');
}

void main() {
  test('scheduled while signed in + enabled; cancelled when turned off or '
      'signed out', () async {
    final gateway = FakeAuthGateway();
    final scheduler = RecordingScheduler();
    final c = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWith((ref) => gateway),
        ledgerTransportProvider.overrideWith(
          (ref) => Completer<LedgerTransport>().future,
        ),
        accountDatabaseOpenerProvider.overrideWithValue(
          (_) => AppDatabase.forTesting(NativeDatabase.memory()),
        ),
        backgroundSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    addTearDown(() {
      c.dispose();
      gateway.dispose();
    });
    c.listen(backgroundSyncSchedulingProvider, (_, _) {});
    // Polls (no fixed sleep) until the last OS call is [expected].
    Future<void> lastCallIs(String expected) async {
      final sw = Stopwatch()..start();
      while (scheduler.calls.isEmpty || scheduler.calls.last != expected) {
        if (sw.elapsed > const Duration(seconds: 5)) {
          fail('expected last call $expected, got ${scheduler.calls}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    await c.read(loginStateProvider.future);
    await lastCallIs('cancel'); // signed out
    expect(scheduler.calls.toSet(), {'cancel'});

    await c
        .read(authProvider.notifier)
        .login(
          resolvedHomeserver: 'https://x.test',
          username: 'bob',
          password: 'pw',
        );
    await lastCallIs('schedule'); // default on
    expect(c.read(backgroundSyncEnabledProvider).value, isTrue);

    await c.read(settingsDaoProvider).setBackgroundSyncEnabled(false);
    await lastCallIs('cancel');
    expect(c.read(backgroundSyncEnabledProvider).value, isFalse);

    await c.read(settingsDaoProvider).setBackgroundSyncEnabled(true);
    await lastCallIs('schedule');

    await c.read(authProvider.notifier).logout();
    await lastCallIs('cancel');
  });

  test('a scheduling failure is kept for the settings sheet and cleared by '
      'the next successful call (G33)', () async {
    final gateway = FakeAuthGateway();
    final scheduler = RecordingScheduler()..failSchedule = true;
    final c = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWith((ref) => gateway),
        ledgerTransportProvider.overrideWith(
          (ref) => Completer<LedgerTransport>().future,
        ),
        accountDatabaseOpenerProvider.overrideWithValue(
          (_) => AppDatabase.forTesting(NativeDatabase.memory()),
        ),
        backgroundSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    addTearDown(() {
      c.dispose();
      gateway.dispose();
    });
    c.listen(backgroundSyncSchedulingProvider, (_, _) {});
    Future<void> until(bool Function() ok) async {
      final sw = Stopwatch()..start();
      while (!ok()) {
        if (sw.elapsed > const Duration(seconds: 5)) fail('timed out');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    await c.read(loginStateProvider.future);
    await c
        .read(authProvider.notifier)
        .login(
          resolvedHomeserver: 'https://x.test',
          username: 'bob',
          password: 'pw',
        );
    await until(() => c.read(backgroundSyncSchedulingErrorProvider) != null);
    expect(
      c.read(backgroundSyncSchedulingErrorProvider).toString(),
      contains('WorkManager refused'),
    );

    // Turning it off (cancel succeeds) clears the error.
    await c.read(settingsDaoProvider).setBackgroundSyncEnabled(false);
    await until(() => c.read(backgroundSyncSchedulingErrorProvider) == null);
  });

  test(
    'G52 step 8/9: local mode registers the round only while a link group '
    'exists (design doc §8.3) and the switch is on — never consulting Matrix',
    () async {
      final scheduler = RecordingScheduler();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final c = ProviderContainer(
        overrides: [
          localModeActiveProvider.overrideWithValue(true),
          ledgerIdentityProvider.overrideWithValue(kLocalAccountId),
          appDatabaseProvider.overrideWithValue(db),
          backgroundSchedulerProvider.overrideWithValue(scheduler),
          // Building a Matrix client would throw here.
          matrixSessionWantedProvider.overrideWith(
            (ref) => throw StateError('Matrix consulted in local mode'),
          ),
        ],
      );
      addTearDown(() async {
        c.dispose();
        await db.close();
      });
      c.listen(backgroundSyncSchedulingProvider, (_, _) {});
      Future<void> lastCallIs(String expected) async {
        final sw = Stopwatch()..start();
        while (scheduler.calls.isEmpty || scheduler.calls.last != expected) {
          if (sw.elapsed > const Duration(seconds: 5)) {
            fail('expected last call $expected, got ${scheduler.calls}');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      await lastCallIs('cancel'); // no link group yet
      await LinkDao(db).putChannel(
        const LinkChannelModel(
          groupId: 'G',
          epoch: 1,
          secret: 's',
          nostrPriv: 'k',
          openedAt: 1,
        ),
      );
      await lastCallIs('schedule');
      // G52 step 9: the settings switch (local mode's Sync section).
      await SettingsDao(db).setBackgroundSyncEnabled(false);
      await lastCallIs('cancel');
      await SettingsDao(db).setBackgroundSyncEnabled(true);
      await lastCallIs('schedule');
      await LinkDao(db).deleteChannel('G');
      await lastCallIs('cancel');
    },
  );
}
