/// Friendly login / SSO / registration error messages (G20).
///
/// Pure Dart — no Flutter, no `package:matrix` — so it is unit-testable. The
/// real gateway (`matrix_auth_gateway.dart`) translates SDK errors into the
/// plain types of the auth port ([AuthServerException], [AuthNetworkException],
/// [NotAHomeserverException]); anything else is classified by its text as a
/// fallback (e.g. a raw `ClientException with SocketException: …`).
///
/// All user-facing English strings live in [AuthErrorStrings] so G12 can
/// localize them in one place.
library;

import 'dart:async';

import '../../core/matrix/auth_gateway.dart';

/// What the user was doing when the error happened — the same `errcode` means
/// different things (e.g. `M_FORBIDDEN` = wrong password on login, but an
/// invalid/expired token on the SSO callback).
enum AuthAction { login, sso, register }

/// A classified error, ready to show: a short [title], an optional friendly
/// [hint] (what to do), and the raw technical [detail] (behind "Details").
class AuthErrorMessage {
  final AuthErrorKind kind;
  final String title;
  final String? hint;
  final String? detail;

  const AuthErrorMessage(this.kind, this.title, {this.hint, this.detail});

  @override
  String toString() => 'AuthErrorMessage($kind, $title)';
}

enum AuthErrorKind {
  offline,
  serverUnreachable,
  timeout,
  notAHomeserver,
  wrongCredentials,
  userDeactivated,
  rateLimited,
  ssoTokenInvalid,
  usernameTaken,
  invalidUsername,
  weakPassword,
  registrationDisabled,
  unknown,
}

/// The single home of every English auth-error string (localized in G12).
abstract final class AuthErrorStrings {
  static const offlineTitle = 'No internet connection';
  static const offlineHint = 'Check your connection and try again.';
  static String unreachableTitle(String host) => "Can't reach $host";
  static const unreachableHint =
      'Check the homeserver address and your internet connection.';
  static const timeoutTitle = 'The server took too long to respond';
  static const timeoutHint = 'Check your connection and try again.';
  static String notAHomeserverTitle(String host) =>
      "$host doesn't look like a Matrix homeserver";
  static const notAHomeserverHint =
      'Check the address — for example matrix.org.';
  static const wrongCredentialsTitle = 'Wrong username or password';
  static const wrongCredentialsHint = 'Check both and try again.';
  static const deactivatedTitle = 'This account has been deactivated';
  static const deactivatedHint =
      'Contact your homeserver administrator, or use another account.';
  static const rateLimitedTitle = 'Too many attempts';
  static String rateLimitedRetry(int seconds) =>
      'Please wait $seconds ${seconds == 1 ? 'second' : 'seconds'} '
      'and try again.';
  static const rateLimitedHint = 'Please wait a moment and try again.';
  static const ssoTokenTitle = 'Sign-in link expired or invalid';
  static const ssoTokenHint = 'Please start the sign-in again.';
  static const usernameTakenTitle = 'That username is already taken';
  static const usernameTakenHint = 'Choose a different username.';
  static const invalidUsernameTitle = "That username isn't allowed";
  static const invalidUsernameHint =
      'Use only lowercase letters, digits and . _ = - /';
  static const weakPasswordTitle = 'Password is too weak';
  static const weakPasswordHint =
      'Use a longer password with a mix of letters, digits and symbols.';
  static const registrationDisabledTitle =
      "This homeserver doesn't allow sign-up here";
  static const registrationDisabledHint =
      'Create your account on its website, then sign in.';
  static const unknownTitle = 'Something went wrong';
  static const unknownHint = 'Please try again. The details below may help.';
  static const detailsLabel = 'Details';
}

/// Cap on the homeserver check (`/versions` + login types) before a login or
/// registration (G30) — a stalled connection must not spin the button forever.
const kHomeserverCheckTimeout = Duration(seconds: 10);

/// Cap on the login / registration request itself (G30). Longer than the
/// check: logging in also sets up and uploads this device's encryption keys.
const kAuthRequestTimeout = Duration(seconds: 20);

/// An auth network step that didn't answer within its limit (G30). A
/// [TimeoutException], so [describeAuthError] shows the friendly "took too
/// long" message.
class AuthTimeoutException extends TimeoutException {
  /// What timed out, e.g. `checkHomeserver` / `login` (for the details text).
  final String step;
  AuthTimeoutException(this.step, Duration limit)
      : super('$step timed out after ${limit.inSeconds}s', limit);

  @override
  String toString() => 'TimeoutException: $message';
}

/// [request], failing with an [AuthTimeoutException] once [limit] passes. The
/// underlying request isn't cancelled (the SDK has no cancellation) — a late
/// success still completes in the background.
Future<T> withAuthTimeout<T>(Future<T> request, Duration limit, String step) =>
    request.timeout(limit,
        onTimeout: () => throw AuthTimeoutException(step, limit));

/// Errcodes we recognize when they only appear inside an error's text.
final _errcodePattern = RegExp(r'\bM_[A-Z_]+\b');

/// Classifies [error] into a friendly message for [action].
AuthErrorMessage describeAuthError(Object error,
    {AuthAction action = AuthAction.login}) {
  final detail = error.toString();
  AuthErrorMessage msg(AuthErrorKind k, String title, String? hint) =>
      AuthErrorMessage(k, title, hint: hint, detail: detail);

  if (error is AuthNetworkException) {
    return error.deviceOffline
        ? msg(AuthErrorKind.offline, AuthErrorStrings.offlineTitle,
            AuthErrorStrings.offlineHint)
        : _isTimeout(error.cause)
            ? msg(AuthErrorKind.timeout, AuthErrorStrings.timeoutTitle,
                AuthErrorStrings.timeoutHint)
            : msg(
                AuthErrorKind.serverUnreachable,
                AuthErrorStrings.unreachableTitle(error.host),
                AuthErrorStrings.unreachableHint);
  }
  if (error is NotAHomeserverException) {
    return msg(
        AuthErrorKind.notAHomeserver,
        AuthErrorStrings.notAHomeserverTitle(error.host),
        AuthErrorStrings.notAHomeserverHint);
  }
  if (error is RegistrationRequiresWebException) {
    return msg(AuthErrorKind.registrationDisabled,
        AuthErrorStrings.registrationDisabledTitle,
        AuthErrorStrings.registrationDisabledHint);
  }

  final String? errcode;
  int? retryAfterMs;
  if (error is AuthServerException) {
    errcode = error.errcode;
    retryAfterMs = error.retryAfterMs;
  } else {
    errcode = _errcodePattern.firstMatch(detail)?.group(0);
  }
  if (errcode != null) {
    final m = _describeErrcode(errcode, action, retryAfterMs, detail);
    if (m != null) return m;
  }

  if (_isTimeout(error)) {
    return msg(AuthErrorKind.timeout, AuthErrorStrings.timeoutTitle,
        AuthErrorStrings.timeoutHint);
  }
  if (isNetworkError(error)) {
    // Raw network error the gateway didn't wrap: we can't tell "offline"
    // from "bad server", so give the advice covering both.
    return msg(AuthErrorKind.offline, AuthErrorStrings.offlineTitle,
        AuthErrorStrings.unreachableHint);
  }
  return msg(AuthErrorKind.unknown, AuthErrorStrings.unknownTitle,
      AuthErrorStrings.unknownHint);
}

AuthErrorMessage? _describeErrcode(
    String errcode, AuthAction action, int? retryAfterMs, String detail) {
  AuthErrorMessage msg(AuthErrorKind k, String title, String? hint) =>
      AuthErrorMessage(k, title, hint: hint, detail: detail);
  switch (errcode) {
    case 'M_FORBIDDEN':
      return switch (action) {
        AuthAction.login => msg(AuthErrorKind.wrongCredentials,
            AuthErrorStrings.wrongCredentialsTitle,
            AuthErrorStrings.wrongCredentialsHint),
        AuthAction.sso => msg(AuthErrorKind.ssoTokenInvalid,
            AuthErrorStrings.ssoTokenTitle, AuthErrorStrings.ssoTokenHint),
        AuthAction.register => msg(AuthErrorKind.registrationDisabled,
            AuthErrorStrings.registrationDisabledTitle,
            AuthErrorStrings.registrationDisabledHint),
      };
    case 'M_UNKNOWN_TOKEN':
    case 'M_MISSING_TOKEN':
      if (action == AuthAction.sso) {
        return msg(AuthErrorKind.ssoTokenInvalid,
            AuthErrorStrings.ssoTokenTitle, AuthErrorStrings.ssoTokenHint);
      }
      return null;
    case 'M_USER_DEACTIVATED':
      return msg(AuthErrorKind.userDeactivated,
          AuthErrorStrings.deactivatedTitle, AuthErrorStrings.deactivatedHint);
    case 'M_LIMIT_EXCEEDED':
      final secs = retryAfterMs == null || retryAfterMs <= 0
          ? null
          : (retryAfterMs / 1000).ceil();
      return msg(
          AuthErrorKind.rateLimited,
          AuthErrorStrings.rateLimitedTitle,
          secs == null
              ? AuthErrorStrings.rateLimitedHint
              : AuthErrorStrings.rateLimitedRetry(secs));
    case 'M_USER_IN_USE':
    case 'M_EXCLUSIVE':
      return msg(AuthErrorKind.usernameTaken,
          AuthErrorStrings.usernameTakenTitle,
          AuthErrorStrings.usernameTakenHint);
    case 'M_INVALID_USERNAME':
      return msg(AuthErrorKind.invalidUsername,
          AuthErrorStrings.invalidUsernameTitle,
          AuthErrorStrings.invalidUsernameHint);
    case 'M_WEAK_PASSWORD':
    case 'M_PASSWORD_TOO_SHORT':
    case 'M_PASSWORD_NO_DIGIT':
    case 'M_PASSWORD_NO_UPPERCASE':
    case 'M_PASSWORD_NO_LOWERCASE':
    case 'M_PASSWORD_NO_SYMBOL':
    case 'M_PASSWORD_IN_DICTIONARY':
      return msg(AuthErrorKind.weakPassword, AuthErrorStrings.weakPasswordTitle,
          AuthErrorStrings.weakPasswordHint);
    case 'M_UNRECOGNIZED':
    case 'M_NOT_FOUND':
      return null; // ambiguous — fall through to the generic message
  }
  return null;
}

bool _isTimeout(Object error) =>
    error is TimeoutException || error.toString().contains('TimeoutException');

/// Substrings of transport-level failures across platforms: dart:io
/// (`SocketException`, `HandshakeException`, `Failed host lookup`), package:http
/// (`ClientException`) and the browser (`XMLHttpRequest error`, `Failed to
/// fetch`).
const _networkMarkers = [
  'SocketException',
  'ClientException',
  'HandshakeException',
  'HttpException',
  'Failed host lookup',
  'Connection refused',
  'Connection reset',
  'Connection closed',
  'Network is unreachable',
  'No route to host',
  'XMLHttpRequest error',
  'Failed to fetch',
];

/// True for transport-level failures (no HTTP response at all). Matched on the
/// error's text so it works without importing dart:io / package:http (and on
/// the web, where those types don't exist).
bool isNetworkError(Object error) {
  if (error is AuthNetworkException) return true;
  if (error is TimeoutException) return true;
  final s = error.toString();
  return _networkMarkers.any(s.contains);
}
