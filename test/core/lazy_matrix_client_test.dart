/// G79: a fresh install builds no Matrix client (and so no SDK store,
/// `money_ledger_matrix.sqlite`) while no mode has been chosen: the welcome
/// isn't seen and no Matrix store exists yet. A device that already has a
/// store (a session from before the welcome) still consults Matrix at start,
/// and choosing *Sign in* on the welcome builds the client then.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/device_prefs.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';

import '../helpers/fake_auth_gateway.dart';

void main() {
  late int clientBuilt;
  late FakeAuthGateway gateway;

  ProviderContainer container(
    InMemoryDevicePrefsStore store, {
    Future<bool>? storeExists,
  }) {
    final c = ProviderContainer(
      overrides: [
        devicePrefsStoreProvider.overrideWithValue(store),
        matrixStoreExistsProvider.overrideWith(
          (ref) => storeExists ?? Future.value(false),
        ),
        matrixClientProvider.overrideWith((ref) {
          clientBuilt++;
          return Completer<Never>().future;
        }),
        // The real gateway provider builds the client — mirror that.
        authGatewayProvider.overrideWith((ref) async {
          clientBuilt++;
          return gateway;
        }),
      ],
    );
    addTearDown(c.dispose);
    // Keep the session chain listened (Riverpod 3 pauses unlistened ones).
    c.listen(appSessionProvider, (_, _) {});
    c.listen(accountUserIdProvider, (_, _) {});
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    clientBuilt = 0;
    gateway = FakeAuthGateway();
  });

  test('fresh install on the welcome: no Matrix client, signed out', () async {
    final c = container(InMemoryDevicePrefsStore());
    await settle();
    expect(c.read(welcomeStatusProvider), WelcomeStatus.notSeen);
    expect(c.read(matrixSessionWantedProvider), isFalse);
    expect(c.read(appSessionProvider), AppSessionKind.signedOut);
    expect(clientBuilt, 0);
  });

  test('choosing Sign in on the welcome builds the client then', () async {
    final c = container(InMemoryDevicePrefsStore());
    await settle();
    await c.read(devicePrefsProvider.notifier).markWelcomeSeen();
    await settle();
    expect(c.read(matrixSessionWantedProvider), isTrue);
    expect(clientBuilt, greaterThan(0));
  });

  test('welcome not seen but a Matrix store exists (pre-welcome session): '
      'splash while checking, then the session is restored', () async {
    final exists = Completer<bool>();
    gateway = FakeAuthGateway(initialUserId: '@anna:x.org');
    final c = container(InMemoryDevicePrefsStore(), storeExists: exists.future);
    await settle();
    expect(c.read(appSessionProvider), AppSessionKind.loading);
    expect(clientBuilt, 0);
    exists.complete(true);
    await settle();
    expect(c.read(matrixSessionWantedProvider), isTrue);
    expect(c.read(appSessionProvider), AppSessionKind.matrix);
    expect(c.read(accountUserIdProvider), '@anna:x.org');
  });

  test('welcome seen (normal start): Matrix is consulted without the store '
      'check', () async {
    final checks = <int>[];
    final c = ProviderContainer(
      overrides: [
        devicePrefsStoreProvider.overrideWithValue(
          InMemoryDevicePrefsStore({'welcome_seen': '1'}),
        ),
        matrixStoreExistsProvider.overrideWith((ref) async {
          checks.add(1);
          return false;
        }),
        authGatewayProvider.overrideWith(
          (ref) async => FakeAuthGateway(initialUserId: '@anna:x.org'),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(appSessionProvider, (_, _) {});
    c.listen(accountUserIdProvider, (_, _) {});
    await settle();
    expect(c.read(appSessionProvider), AppSessionKind.matrix);
    expect(checks, isEmpty);
  });

  test('local mode: never Matrix, no store check', () async {
    final c = container(
      InMemoryDevicePrefsStore({
        'welcome_seen': '1',
        'local_profile': '{"name":"Lea","created_at":1}',
      }),
    );
    await settle();
    expect(c.read(appSessionProvider), AppSessionKind.local);
    expect(c.read(matrixSessionWantedProvider), isFalse);
    expect(clientBuilt, 0);
  });
}
