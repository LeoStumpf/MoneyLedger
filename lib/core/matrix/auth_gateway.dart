/// Authentication port: a narrow, plain-Dart interface over login/session
/// management. The real implementation (`matrix_auth_gateway.dart`) wraps the
/// Matrix client; tests/offline mode use an in-memory fake.
///
/// **No `package:matrix` import may ever be added to this file.** This keeps
/// login flows simulatable without a real homeserver. See [LedgerTransport] for
/// the sibling sync/transport port.
library;

import '../../models/login_flows_result.dart';

abstract interface class AuthGateway {
  /// Whether a session is currently active.
  bool get isLoggedIn;

  /// The logged-in user's MXID, or null when signed out.
  String? get userId;

  /// Emits the new [isLoggedIn] value after each login/logout. Broadcast.
  Stream<bool> get loginStateChanges;

  /// Resolves a homeserver (with .well-known discovery) from a bare domain,
  /// URL, or MXID, and returns its available login flows (password / SSO).
  Future<LoginFlowsResult> loginFlows(String input);

  Future<void> loginWithPassword({
    required String homeserver,
    required String username,
    required String password,
  });

  Future<void> loginWithToken({
    required String homeserver,
    required String token,
  });

  /// Creates a new account and signs in. Succeeds only when the homeserver
  /// offers an in-app-completable registration flow (open / `m.login.dummy`);
  /// otherwise throws [RegistrationRequiresWebException].
  Future<void> register({
    required String homeserver,
    required String username,
    required String password,
  });

  Future<void> logout();
}

/// Thrown by [AuthGateway.register] when the homeserver requires interactive
/// stages MoneyLedger doesn't implement (CAPTCHA, email/phone verification,
/// terms acceptance, registration token) — the user must register on the web.
class RegistrationRequiresWebException implements Exception {
  /// The resolved homeserver the user was trying to register on.
  final String homeserverUrl;

  /// Blocking UIA stage ids of the easiest flow (e.g. `['m.login.recaptcha']`;
  /// `kWebSignupStage` when sign-up is website-only) — labelled in the UI.
  final List<String> stages;

  /// Where the user can create an account: the server's advertised sign-up /
  /// account-management page when known (see `sign_up_url.dart`), else null —
  /// then the UI falls back to [homeserverUrl].
  final String? signUpUrl;

  const RegistrationRequiresWebException(
    this.homeserverUrl,
    this.stages, {
    this.signUpUrl,
  });

  /// The page "Open homeserver website" opens.
  String get webUrl => signUpUrl ?? homeserverUrl;

  @override
  String toString() => stages.isEmpty
      ? 'This homeserver requires registering on its website.'
      : 'This homeserver requires ${stages.join(', ')} — '
            'please register on its website.';
}

// ── Plain-Dart auth failures (G20) ──────────────────────────────────────────
// The real gateway translates SDK / transport errors into these so the UI's
// pure error mapper (`features/auth/auth_errors.dart`) can classify them
// without importing `package:matrix`.

/// The homeserver answered with a Matrix error (`errcode`), e.g. `M_FORBIDDEN`
/// for a wrong password or `M_LIMIT_EXCEEDED` when rate limited.
class AuthServerException implements Exception {
  final String errcode;

  /// The server's own (English, technical) error text, if any.
  final String? serverMessage;

  /// `retry_after_ms` of an `M_LIMIT_EXCEEDED` response.
  final int? retryAfterMs;

  const AuthServerException(
    this.errcode, {
    this.serverMessage,
    this.retryAfterMs,
  });

  @override
  String toString() =>
      serverMessage == null ? errcode : '$errcode: $serverMessage';
}

/// The homeserver couldn't be reached at all (DNS failure, refused connection,
/// timeout). [deviceOffline] is true when a reference server was unreachable
/// too — i.e. the device has no working internet connection.
class AuthNetworkException implements Exception {
  /// Host the app tried to reach (e.g. `matrix.org`).
  final String host;
  final bool deviceOffline;

  /// The underlying error (shown only behind "Details").
  final Object cause;

  const AuthNetworkException(
    this.host, {
    required this.deviceOffline,
    required this.cause,
  });

  @override
  String toString() => cause.toString();
}

/// The server answered, but not like a Matrix homeserver (no `/versions`,
/// HTML instead of JSON, …) — usually a typo in the homeserver address.
class NotAHomeserverException implements Exception {
  final String host;
  final Object cause;
  const NotAHomeserverException(this.host, this.cause);

  @override
  String toString() => cause.toString();
}

/// A sign-in / registration was requested while an earlier one is still
/// running (G36) — typically one whose UI timeout fired while the request
/// itself carries on (the SDK can't cancel it). Never started in parallel: two
/// concurrent `client.login`s would create two devices / race over the session.
class AuthInProgressException implements Exception {
  const AuthInProgressException();

  @override
  String toString() => 'AuthInProgressException: a sign-in is still running';
}

/// Single-flight guard for auth requests (G36). [operation] wraps a whole
/// login / registration; [track] marks each raw homeserver request inside it,
/// which may **outlive** the operation when its UI timeout fires. While either
/// runs, a new [operation] fails with [AuthInProgressException] instead of
/// starting a parallel request. A late success of the tracked request is
/// **adopted**: the client signs in and the app follows its login-state
/// stream (as before) — no second device, nothing to log out.
class AuthSingleFlight {
  bool _operation = false;
  int _pending = 0;

  /// Whether an operation or a (timed-out but still running) request is in
  /// flight.
  bool get busy => _operation || _pending > 0;

  Future<T> operation<T>(Future<T> Function() body) async {
    if (busy) throw const AuthInProgressException();
    _operation = true;
    try {
      return await body();
    } finally {
      _operation = false;
    }
  }

  /// [request], counted as in flight until it settles (success or error).
  Future<T> track<T>(Future<T> request) {
    _pending++;
    request.then<void>((_) {}, onError: (_) {}).whenComplete(() => _pending--);
    return request;
  }
}
