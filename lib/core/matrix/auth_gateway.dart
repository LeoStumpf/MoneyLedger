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

  /// Human-readable requirements of the easiest flow (e.g. `['a CAPTCHA']`).
  final List<String> requirements;

  const RegistrationRequiresWebException(this.homeserverUrl, this.requirements);

  @override
  String toString() => requirements.isEmpty
      ? 'This homeserver requires registering on its website.'
      : 'This homeserver requires ${requirements.join(' and ')} — '
          'please register on its website.';
}
