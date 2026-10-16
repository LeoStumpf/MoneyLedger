/// describeAuthError (G20): friendly login / SSO / registration messages.
/// Pure — no matrix import; SDK errors arrive as the auth port's plain types
/// (or as raw text the mapper falls back on).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/auth_gateway.dart';
import 'package:money_ledger/features/auth/auth_errors.dart';

import '../helpers/l10n.dart';

AuthErrorKind kindOf(Object e, [AuthAction action = AuthAction.login]) =>
    describeAuthError(e, action: action).kind;

void main() {
  group('network', () {
    test('G43: offline and server down are one message (no probe)', () {
      final m = describeAuthError(
        AuthNetworkException(
          'matrix.org',
          cause: Exception("Failed host lookup: 'matrix.org'"),
        ),
      );
      expect(m.kind, AuthErrorKind.serverUnreachable);
      expect(m.title(en), "Can't reach matrix.org");
      expect(m.hint(en), en.authUnreachableHint);
      expect(m.hint(en), contains('offline'));
      expect(m.hint(de), contains('offline'));
      expect(m.detail, contains('Failed host lookup'));
    });

    test('server unreachable names the host', () {
      final m = describeAuthError(
        AuthNetworkException(
          'nope.example',
          cause: Exception('Connection refused'),
        ),
      );
      expect(m.kind, AuthErrorKind.serverUnreachable);
      expect(m.title(en), contains('nope.example'));
    });

    test('timeout (wrapped or raw)', () {
      expect(
        kindOf(AuthNetworkException('x.org', cause: TimeoutException('slow'))),
        AuthErrorKind.timeout,
      );
      expect(kindOf(TimeoutException('slow')), AuthErrorKind.timeout);
    });

    test('raw ClientException / SocketException text is a network error', () {
      final e = Exception(
        'ClientException with SocketException: Failed host '
        "lookup: 'matrix.org' (OS Error: No address associated with "
        'hostname, errno = 7)',
      );
      expect(isNetworkError(e), isTrue);
      final m = describeAuthError(e);
      expect(m.kind, AuthErrorKind.serverUnreachable);
      expect(m.title(en), en.authUnreachableNoHostTitle);
      expect(m.title(en), isNot(contains('ClientException')));
      expect(m.detail, contains('ClientException'));
    });

    test('browser fetch failures are network errors', () {
      expect(isNetworkError(Exception('XMLHttpRequest error.')), isTrue);
      expect(isNetworkError(Exception('http error response')), isFalse);
    });
  });

  test('not a Matrix homeserver', () {
    final m = describeAuthError(
      NotAHomeserverException('example.com', const FormatException('<html')),
    );
    expect(m.kind, AuthErrorKind.notAHomeserver);
    expect(m.title(en), contains('example.com'));
  });

  group('errcodes', () {
    test('M_FORBIDDEN on login = wrong username or password', () {
      final m = describeAuthError(
        const AuthServerException(
          'M_FORBIDDEN',
          serverMessage: 'Invalid username or password',
        ),
      );
      expect(m.kind, AuthErrorKind.wrongCredentials);
      expect(m.title(en), en.authWrongCredentialsTitle);
      expect(m.detail, 'M_FORBIDDEN: Invalid username or password');
    });

    test('M_FORBIDDEN on the SSO callback = invalid/expired token', () {
      expect(
        kindOf(const AuthServerException('M_FORBIDDEN'), AuthAction.sso),
        AuthErrorKind.ssoTokenInvalid,
      );
      expect(
        kindOf(const AuthServerException('M_UNKNOWN_TOKEN'), AuthAction.sso),
        AuthErrorKind.ssoTokenInvalid,
      );
    });

    test('M_FORBIDDEN on register = sign-up disabled', () {
      expect(
        kindOf(const AuthServerException('M_FORBIDDEN'), AuthAction.register),
        AuthErrorKind.registrationDisabled,
      );
    });

    test('M_USER_DEACTIVATED', () {
      expect(
        kindOf(const AuthServerException('M_USER_DEACTIVATED')),
        AuthErrorKind.userDeactivated,
      );
    });

    test('M_LIMIT_EXCEEDED shows retry-after when present', () {
      final m = describeAuthError(
        const AuthServerException('M_LIMIT_EXCEEDED', retryAfterMs: 12300),
      );
      expect(m.kind, AuthErrorKind.rateLimited);
      expect(m.hint(en), contains('13 seconds'));
      expect(
        describeAuthError(
          const AuthServerException('M_LIMIT_EXCEEDED'),
        ).hint(en),
        en.authRateLimitedHint,
      );
      expect(
        describeAuthError(
          const AuthServerException('M_LIMIT_EXCEEDED', retryAfterMs: 400),
        ).hint(en),
        contains('1 second '),
      );
    });

    test('registration errors', () {
      const r = AuthAction.register;
      expect(
        kindOf(const AuthServerException('M_USER_IN_USE'), r),
        AuthErrorKind.usernameTaken,
      );
      expect(
        kindOf(const AuthServerException('M_INVALID_USERNAME'), r),
        AuthErrorKind.invalidUsername,
      );
      expect(
        kindOf(const AuthServerException('M_WEAK_PASSWORD'), r),
        AuthErrorKind.weakPassword,
      );
      expect(
        kindOf(const AuthServerException('M_PASSWORD_TOO_SHORT'), r),
        AuthErrorKind.weakPassword,
      );
    });

    test('an errcode inside an unwrapped error text is still recognized', () {
      expect(
        kindOf(Exception('M_FORBIDDEN: Invalid username/password')),
        AuthErrorKind.wrongCredentials,
      );
      expect(
        kindOf(Exception('SSO login failed: M_FORBIDDEN'), AuthAction.sso),
        AuthErrorKind.ssoTokenInvalid,
      );
    });

    test('an unknown errcode falls back to "Something went wrong"', () {
      final m = describeAuthError(
        const AuthServerException('M_UNRECOGNIZED', serverMessage: 'nope'),
      );
      expect(m.kind, AuthErrorKind.unknown);
      expect(m.detail, 'M_UNRECOGNIZED: nope');
    });
  });

  test('registration needing the web', () {
    expect(
      kindOf(
        const RegistrationRequiresWebException('https://x.org', []),
        AuthAction.register,
      ),
      AuthErrorKind.registrationDisabled,
    );
  });

  test('anything else: generic title + the raw text as detail', () {
    final m = describeAuthError(StateError('boom'));
    expect(m.kind, AuthErrorKind.unknown);
    expect(m.title(en), en.authUnknownTitle);
    expect(m.detail, contains('boom'));
  });

  group('auth timeouts (G30)', () {
    test('limits: discovery 10 s, login/register 20 s', () {
      expect(kHomeserverCheckTimeout, const Duration(seconds: 10));
      expect(kAuthRequestTimeout, const Duration(seconds: 20));
    });

    test('a stalled request fails with AuthTimeoutException', () async {
      final stalled = Completer<void>().future; // never completes
      await expectLater(
        withAuthTimeout(stalled, const Duration(milliseconds: 10), 'login'),
        throwsA(
          isA<AuthTimeoutException>()
              .having((e) => e.step, 'step', 'login')
              .having((e) => e.toString(), 'text', contains('login timed out')),
        ),
      );
    });

    test('a request that answers in time passes its result through', () async {
      expect(
        await withAuthTimeout(
          Future.value(42),
          const Duration(seconds: 1),
          'checkHomeserver',
        ),
        42,
      );
    });

    test(
      'a request error inside the limit is not turned into a timeout',
      () async {
        await expectLater(
          withAuthTimeout(
            Future<void>.error(StateError('boom')),
            const Duration(seconds: 1),
            'register',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('maps to the friendly "took too long" message', () {
      final timeout = AuthTimeoutException(
        'checkHomeserver',
        kHomeserverCheckTimeout,
      );
      for (final action in AuthAction.values) {
        final m = describeAuthError(timeout, action: action);
        expect(m.kind, AuthErrorKind.timeout);
        expect(m.title(en), en.authTimeoutTitle);
        expect(m.hint(en), en.authTimeoutHint);
        expect(m.detail, contains('checkHomeserver timed out after 10s'));
      }
      // As the gateway wraps it.
      final wrapped = AuthNetworkException(
        'matrix.org',
        cause: AuthTimeoutException('login', kAuthRequestTimeout),
      );
      expect(kindOf(wrapped), AuthErrorKind.timeout);
      expect(kindOf(wrapped, AuthAction.register), AuthErrorKind.timeout);
    });
  });

  group('localized (G12)', () {
    test('German title + plural retry hint', () {
      final m = describeAuthError(
        const AuthServerException('M_LIMIT_EXCEEDED', retryAfterMs: 2000),
      );
      expect(m.title(de), 'Zu viele Versuche');
      expect(m.hint(de), 'Bitte warte 2 Sekunden und versuche es erneut.');
    });
    test('host placeholder in both languages', () {
      final m = describeAuthError(
        AuthNetworkException(
          'nope.example',
          cause: Exception('Connection refused'),
        ),
      );
      expect(m.title(en), "Can't reach nope.example");
      expect(m.title(de), 'nope.example ist nicht erreichbar');
    });
    test('raw network error: host-less title, same hint', () {
      final m = describeAuthError(Exception('SocketException: boom'));
      expect(m.title(en), en.authUnreachableNoHostTitle);
      expect(m.title(de), de.authUnreachableNoHostTitle);
      expect(m.hint(en), en.authUnreachableHint);
    });
  });
}
