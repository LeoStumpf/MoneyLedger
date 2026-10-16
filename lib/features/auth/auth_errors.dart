/// Friendly login / SSO / registration error messages (G20).
///
/// Pure Dart — no Flutter, no `package:matrix` — so it is unit-testable. The
/// real gateway (`matrix_auth_gateway.dart`) translates SDK errors into the
/// plain types of the auth port ([AuthServerException], [AuthNetworkException],
/// [NotAHomeserverException]); anything else is classified by its text as a
/// fallback (e.g. a raw `ClientException with SocketException: …`).
///
/// The text is localized at the widget layer: [AuthErrorMessage.title] /
/// [AuthErrorMessage.hint] take an [AppLocalizations] (G12).
library;

import 'dart:async';

import '../../core/matrix/auth_gateway.dart';
import '../../l10n/app_localizations.dart';

/// What the user was doing when the error happened — the same `errcode` means
/// different things (e.g. `M_FORBIDDEN` = wrong password on login, but an
/// invalid/expired token on the SSO callback).
enum AuthAction { login, sso, register }

/// A classified error, ready to show: a short [title], an optional friendly
/// [hint] (what to do), and the raw technical [detail] (behind "Details").
/// Title and hint are localized on demand from the structured fields.
class AuthErrorMessage {
  final AuthErrorKind kind;

  /// The homeserver host, for [AuthErrorKind.serverUnreachable] /
  /// [AuthErrorKind.notAHomeserver].
  final String? host;

  /// Server-provided wait for [AuthErrorKind.rateLimited], if any.
  final int? retryAfterSeconds;

  /// A raw transport error the gateway didn't wrap: "offline" title, but the
  /// hint covers both "offline" and "bad server".
  final bool ambiguousNetwork;
  final String? detail;

  const AuthErrorMessage(
    this.kind, {
    this.host,
    this.retryAfterSeconds,
    this.ambiguousNetwork = false,
    this.detail,
  });

  String title(AppLocalizations l) => switch (kind) {
    AuthErrorKind.offline => l.authOfflineTitle,
    AuthErrorKind.serverUnreachable => l.authUnreachableTitle(host ?? ''),
    AuthErrorKind.timeout => l.authTimeoutTitle,
    AuthErrorKind.notAHomeserver => l.authNotAHomeserverTitle(host ?? ''),
    AuthErrorKind.wrongCredentials => l.authWrongCredentialsTitle,
    AuthErrorKind.userDeactivated => l.authDeactivatedTitle,
    AuthErrorKind.rateLimited => l.authRateLimitedTitle,
    AuthErrorKind.ssoTokenInvalid => l.authSsoTokenTitle,
    AuthErrorKind.usernameTaken => l.authUsernameTakenTitle,
    AuthErrorKind.invalidUsername => l.authInvalidUsernameTitle,
    AuthErrorKind.weakPassword => l.authWeakPasswordTitle,
    AuthErrorKind.registrationDisabled => l.authRegistrationDisabledTitle,
    AuthErrorKind.unknown => l.authUnknownTitle,
  };

  String? hint(AppLocalizations l) => switch (kind) {
    AuthErrorKind.offline =>
      ambiguousNetwork ? l.authUnreachableHint : l.authOfflineHint,
    AuthErrorKind.serverUnreachable => l.authUnreachableHint,
    AuthErrorKind.timeout => l.authTimeoutHint,
    AuthErrorKind.notAHomeserver => l.authNotAHomeserverHint,
    AuthErrorKind.wrongCredentials => l.authWrongCredentialsHint,
    AuthErrorKind.userDeactivated => l.authDeactivatedHint,
    AuthErrorKind.rateLimited =>
      retryAfterSeconds == null
          ? l.authRateLimitedHint
          : l.authRateLimitedRetry(retryAfterSeconds!),
    AuthErrorKind.ssoTokenInvalid => l.authSsoTokenHint,
    AuthErrorKind.usernameTaken => l.authUsernameTakenHint,
    AuthErrorKind.invalidUsername => l.authInvalidUsernameHint,
    AuthErrorKind.weakPassword => l.authWeakPasswordHint,
    AuthErrorKind.registrationDisabled => l.authRegistrationDisabledHint,
    AuthErrorKind.unknown => l.authUnknownHint,
  };

  @override
  String toString() => 'AuthErrorMessage($kind)';
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
    request.timeout(
      limit,
      onTimeout: () => throw AuthTimeoutException(step, limit),
    );

/// Errcodes we recognize when they only appear inside an error's text.
final _errcodePattern = RegExp(r'\bM_[A-Z_]+\b');

/// Classifies [error] into a friendly message for [action].
AuthErrorMessage describeAuthError(
  Object error, {
  AuthAction action = AuthAction.login,
}) {
  final detail = error.toString();
  AuthErrorMessage msg(
    AuthErrorKind k, {
    String? host,
    bool ambiguousNetwork = false,
  }) => AuthErrorMessage(
    k,
    host: host,
    ambiguousNetwork: ambiguousNetwork,
    detail: detail,
  );

  if (error is AuthNetworkException) {
    return error.deviceOffline
        ? msg(AuthErrorKind.offline)
        : _isTimeout(error.cause)
        ? msg(AuthErrorKind.timeout)
        : msg(AuthErrorKind.serverUnreachable, host: error.host);
  }
  if (error is NotAHomeserverException) {
    return msg(AuthErrorKind.notAHomeserver, host: error.host);
  }
  if (error is RegistrationRequiresWebException) {
    return msg(AuthErrorKind.registrationDisabled);
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

  if (_isTimeout(error)) return msg(AuthErrorKind.timeout);
  if (isNetworkError(error)) {
    // Raw network error the gateway didn't wrap: we can't tell "offline"
    // from "bad server", so give the advice covering both.
    return msg(AuthErrorKind.offline, ambiguousNetwork: true);
  }
  return msg(AuthErrorKind.unknown);
}

AuthErrorMessage? _describeErrcode(
  String errcode,
  AuthAction action,
  int? retryAfterMs,
  String detail,
) {
  AuthErrorMessage msg(AuthErrorKind k, {int? retryAfterSeconds}) =>
      AuthErrorMessage(k, retryAfterSeconds: retryAfterSeconds, detail: detail);
  switch (errcode) {
    case 'M_FORBIDDEN':
      return switch (action) {
        AuthAction.login => msg(AuthErrorKind.wrongCredentials),
        AuthAction.sso => msg(AuthErrorKind.ssoTokenInvalid),
        AuthAction.register => msg(AuthErrorKind.registrationDisabled),
      };
    case 'M_UNKNOWN_TOKEN':
    case 'M_MISSING_TOKEN':
      if (action == AuthAction.sso) return msg(AuthErrorKind.ssoTokenInvalid);
      return null;
    case 'M_USER_DEACTIVATED':
      return msg(AuthErrorKind.userDeactivated);
    case 'M_LIMIT_EXCEEDED':
      final secs = retryAfterMs == null || retryAfterMs <= 0
          ? null
          : (retryAfterMs / 1000).ceil();
      return msg(AuthErrorKind.rateLimited, retryAfterSeconds: secs);
    case 'M_USER_IN_USE':
    case 'M_EXCLUSIVE':
      return msg(AuthErrorKind.usernameTaken);
    case 'M_INVALID_USERNAME':
      return msg(AuthErrorKind.invalidUsername);
    case 'M_WEAK_PASSWORD':
    case 'M_PASSWORD_TOO_SHORT':
    case 'M_PASSWORD_NO_DIGIT':
    case 'M_PASSWORD_NO_UPPERCASE':
    case 'M_PASSWORD_NO_LOWERCASE':
    case 'M_PASSWORD_NO_SYMBOL':
    case 'M_PASSWORD_IN_DICTIONARY':
      return msg(AuthErrorKind.weakPassword);
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
