/// Offline login tests: drive the auth providers against an in-memory
/// FakeAuthGateway — no real homeserver, no network.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';

import '../helpers/fake_auth_gateway.dart';

void main() {
  ProviderContainer makeContainer(FakeAuthGateway gateway) {
    final container = ProviderContainer(
      overrides: [authGatewayProvider.overrideWith((ref) => gateway)],
    );
    addTearDown(() {
      container.dispose();
      gateway.dispose();
    });
    // Keep the reactive login-state chain alive for the duration of the test.
    container.listen(isLoggedInProvider, (_, _) {});
    return container;
  }

  test('starts logged out', () async {
    final container = makeContainer(FakeAuthGateway());
    // Let loginState yield its initial value.
    await container.read(loginStateProvider.future);
    expect(container.read(isLoggedInProvider), isFalse);
  });

  test('password login flips isLoggedIn to true', () async {
    final container = makeContainer(FakeAuthGateway());
    await container.read(loginStateProvider.future);

    await container
        .read(authProvider.notifier)
        .login(
          resolvedHomeserver: 'https://matrix.org',
          username: 'alice',
          password: 'hunter2',
        );

    expect(container.read(authProvider).hasError, isFalse);
    // login() refreshes loginState; await its rebuilt first emission.
    await container.read(loginStateProvider.future);
    expect(container.read(isLoggedInProvider), isTrue);
  });

  test('logout flips isLoggedIn back to false', () async {
    final container = makeContainer(FakeAuthGateway(initialUserId: '@a:x.org'));
    await container.read(loginStateProvider.future);
    expect(container.read(isLoggedInProvider), isTrue);

    await container.read(authProvider.notifier).logout();
    await container.read(loginStateProvider.future);
    expect(container.read(isLoggedInProvider), isFalse);
  });

  test('login failure is surfaced and leaves user logged out', () async {
    final gateway = FakeAuthGateway()..failWith = Exception('bad creds');
    final container = makeContainer(gateway);
    await container.read(loginStateProvider.future);

    await container
        .read(authProvider.notifier)
        .login(
          resolvedHomeserver: 'https://matrix.org',
          username: 'alice',
          password: 'wrong',
        );

    expect(container.read(authProvider).hasError, isTrue);
    expect(container.read(isLoggedInProvider), isFalse);
  });

  // #10: logging in again after a logout reuses the same gateway/client.
  test('re-login after logout flips isLoggedIn back to true', () async {
    final container = makeContainer(FakeAuthGateway(initialUserId: '@a:x.org'));
    await container.read(loginStateProvider.future);

    await container.read(authProvider.notifier).logout();
    await container.read(loginStateProvider.future);
    expect(container.read(isLoggedInProvider), isFalse);

    await container
        .read(authProvider.notifier)
        .login(
          resolvedHomeserver: 'https://x.org',
          username: 'a',
          password: 'hunter2',
        );
    expect(container.read(authProvider).hasError, isFalse);
    await container.read(loginStateProvider.future);
    expect(container.read(isLoggedInProvider), isTrue);
  });

  // #11: a remote logout / token expiry arrives on the gateway stream and the
  // app reacts — without the app calling logout() itself.
  test('an external remote logout propagates to isLoggedIn', () async {
    final gateway = FakeAuthGateway(initialUserId: '@a:x.org');
    final container = makeContainer(gateway);
    await container.read(loginStateProvider.future);
    // Let the loginState generator subscribe to the broadcast stream before we
    // emit, so the external event isn't dropped.
    await pumpEventQueue();
    expect(container.read(isLoggedInProvider), isTrue);

    final flipped = Completer<void>();
    final sub = container.listen<bool>(isLoggedInProvider, (_, next) {
      if (!next && !flipped.isCompleted) flipped.complete();
    });
    gateway.simulateRemoteLogout();
    await flipped.future;
    sub.close();

    expect(container.read(isLoggedInProvider), isFalse);
  });

  // F-M4: in-app registration flips isLoggedIn like a login does.
  test('register flips isLoggedIn to true', () async {
    final container = makeContainer(FakeAuthGateway());
    await container.read(loginStateProvider.future);

    await container
        .read(authProvider.notifier)
        .register(
          resolvedHomeserver: 'https://matrix.org',
          username: 'alice',
          password: 'password123',
        );

    expect(container.read(authProvider).hasError, isFalse);
    await container.read(loginStateProvider.future);
    expect(container.read(isLoggedInProvider), isTrue);
  });

  test('register surfaces a web-fallback error and stays logged out', () async {
    final gateway = FakeAuthGateway()
      ..registerRequiresWeb = ['m.login.recaptcha'];
    final container = makeContainer(gateway);
    await container.read(loginStateProvider.future);

    await container
        .read(authProvider.notifier)
        .register(
          resolvedHomeserver: 'https://matrix.org',
          username: 'alice',
          password: 'password123',
        );

    expect(container.read(authProvider).hasError, isTrue);
    expect(container.read(isLoggedInProvider), isFalse);
  });

  test('loginFlows is served offline from the gateway', () async {
    final container = makeContainer(FakeAuthGateway());
    final flows = await container.read(loginFlowsProvider('matrix.org').future);
    expect(flows.hasPassword, isTrue);
    expect(flows.resolvedUrl, 'https://fake.test');
  });
}
