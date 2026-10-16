/// G36: a login / registration whose UI timeout fired keeps running in the
/// SDK. A second attempt meanwhile must not start a parallel request; a late
/// success is adopted (the account signs in).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/auth_gateway.dart';
import 'package:money_ledger/features/auth/auth_errors.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';

import '../helpers/fake_auth_gateway.dart';
import '../helpers/l10n.dart';

void main() {
  late FakeAuthGateway gateway;
  late ProviderContainer c;

  setUp(() {
    gateway = FakeAuthGateway()
      ..pendingRequest = Completer<void>()
      ..requestTimeout = const Duration(milliseconds: 20);
    c = ProviderContainer(
      overrides: [authGatewayProvider.overrideWith((ref) => gateway)],
    );
    c.listen(isLoggedInProvider, (_, _) {});
    addTearDown(c.dispose);
  });

  Future<void> login(String user) => c
      .read(authProvider.notifier)
      .login(
        resolvedHomeserver: 'https://fake.test',
        username: user,
        password: 'pw',
      );

  test('a retry while the timed-out login still runs is refused, and the '
      'late success signs in', () async {
    await login('alice');
    expect(c.read(authProvider).error, isA<AuthTimeoutException>());
    expect(gateway.requestsStarted, 1);
    expect(c.read(isLoggedInProvider), isFalse);

    // Second attempt: no parallel request.
    await login('alice');
    final err = c.read(authProvider).error;
    expect(err, isA<AuthInProgressException>());
    expect(describeAuthError(err!).kind, AuthErrorKind.inProgress);
    expect(gateway.requestsStarted, 1);

    // The first request finally succeeds → adopted.
    gateway.pendingRequest!.complete();
    await pumpEventQueue();
    expect(gateway.userId, '@alice:fake.test');
    expect(c.read(isLoggedInProvider), isTrue);
  });

  test('after a late failure a new attempt runs normally', () async {
    await login('alice');
    expect(c.read(authProvider).error, isA<AuthTimeoutException>());
    gateway.pendingRequest!.completeError(StateError('server gave up'));
    await pumpEventQueue();
    expect(gateway.isLoggedIn, isFalse);

    gateway.pendingRequest = null; // the server answers at once now
    await login('alice');
    expect(c.read(authProvider).hasError, isFalse);
    expect(gateway.requestsStarted, 2);
    expect(gateway.isLoggedIn, isTrue);
  });

  test('registration is guarded the same way', () async {
    Future<void> register() => c
        .read(authProvider.notifier)
        .register(
          resolvedHomeserver: 'https://fake.test',
          username: 'bob',
          password: 'pw',
        );
    await register();
    expect(c.read(authProvider).error, isA<AuthTimeoutException>());
    await login('bob');
    expect(c.read(authProvider).error, isA<AuthInProgressException>());
    expect(gateway.requestsStarted, 1);
  });

  test('AuthSingleFlight (pure)', () async {
    final f = AuthSingleFlight();
    final slow = Completer<void>();
    expect(f.busy, isFalse);
    final op = f.operation(() => f.track(slow.future));
    expect(f.busy, isTrue);
    await expectLater(
      f.operation(() async {}),
      throwsA(isA<AuthInProgressException>()),
    );
    slow.complete();
    await op;
    expect(f.busy, isFalse);
    await f.operation(() async {});
  });

  test('the in-progress message is localized', () {
    const m = AuthErrorMessage(AuthErrorKind.inProgress);
    expect(m.title(en), 'Still signing in…');
    expect(m.title(de), 'Die Anmeldung läuft noch…');
    expect(m.hint(en), contains('signed in automatically'));
  });
}
