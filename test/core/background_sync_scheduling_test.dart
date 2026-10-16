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

import '../helpers/fake_auth_gateway.dart';

class RecordingScheduler implements BackgroundScheduler {
  final calls = <String>[];
  @override
  Future<void> schedule() async => calls.add('schedule');
  @override
  Future<void> cancel() async => calls.add('cancel');
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
}
