import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../../features/auth/auth_errors.dart';
import '../../features/auth/register_flows.dart';
import '../../features/auth/sign_up_url.dart';
import '../../models/login_flows_result.dart';
import 'auth_gateway.dart';

/// Real [AuthGateway] backed by the Matrix SDK [Client]. The only place that
/// translates Matrix auth types into the app's plain-Dart auth port.
class MatrixAuthGateway implements AuthGateway {
  /// Cap on the discovery/login-flows network calls so a stalled connection on
  /// a flaky mobile network surfaces as the fallback result instead of an
  /// indefinite spinner on the login screen.
  static const _lookupTimeout = Duration(seconds: 10);

  final Client _client;
  MatrixAuthGateway(this._client);

  /// G36: one login / registration at a time — also while a timed-out
  /// request is still running in the SDK (its late success is adopted).
  final AuthSingleFlight _flight = AuthSingleFlight();

  @override
  bool get isLoggedIn => _client.isLogged();

  @override
  String? get userId => _client.userID;

  @override
  Stream<bool> get loginStateChanges =>
      _client.onLoginStateChanged.stream.map((_) => _client.isLogged());

  @override
  Future<LoginFlowsResult> loginFlows(String input) async {
    final sw = Stopwatch()..start();
    final normalised = _normalise(input);
    if (normalised == null) return LoginFlowsResult.empty;

    // Step 1: try .well-known discovery to find the real homeserver URL.
    Uri resolved = normalised;
    try {
      final probe = MatrixApi(homeserver: normalised);
      final wk = await probe.getWellknown().timeout(_lookupTimeout);
      probe.httpClient.close();
      resolved = wk.mHomeserver.baseUrl;
      debugPrint(
        '[flows] well-known $normalised -> $resolved '
        '(${sw.elapsedMilliseconds}ms)',
      );
    } catch (e) {
      // No .well-known or server doesn't support it — use the URL as-is.
      debugPrint(
        '[flows] well-known failed for $normalised after '
        '${sw.elapsedMilliseconds}ms: $e',
      );
    }

    // Step 2: fetch login flows from the resolved URL.
    try {
      final api = MatrixApi(homeserver: resolved);
      final rawFlows = await api.getLoginFlows().timeout(_lookupTimeout) ?? [];
      api.httpClient.close();
      debugPrint(
        '[flows] getLoginFlows $resolved ok '
        '(total ${sw.elapsedMilliseconds}ms)',
      );
      return _toResult(resolved.toString(), rawFlows);
    } catch (e) {
      debugPrint(
        '[flows] getLoginFlows $resolved failed after '
        '${sw.elapsedMilliseconds}ms: $e',
      );
      // Flow check failed (e.g. CORS on a non-public server). Show both SSO and
      // password — we don't know which is supported, but SSO is worth offering
      // since we at least have the resolved homeserver URL to redirect to.
      return LoginFlowsResult(
        resolvedUrl: resolved.toString(),
        hasPassword: true,
        hasSso: true,
        ssoProviders: [],
      );
    }
  }

  @override
  Future<void> loginWithPassword({
    required String homeserver,
    required String username,
    required String password,
  }) => _flight.operation(
    () => _translated(homeserver, () async {
      await _checkHomeserver(homeserver);
      await withAuthTimeout(
        _flight.track(
          _client.login(
            AuthenticationTypes.password,
            identifier: AuthenticationUserIdentifier(user: username),
            password: password,
            initialDeviceDisplayName: 'MoneyLedger',
          ),
        ),
        kAuthRequestTimeout,
        'login',
      );
    }),
  );

  @override
  Future<void> loginWithToken({
    required String homeserver,
    required String token,
  }) => _flight.operation(
    () => _translated(homeserver, () async {
      await _checkHomeserver(homeserver);
      await withAuthTimeout(
        _flight.track(
          _client.login(
            AuthenticationTypes.token,
            token: token,
            initialDeviceDisplayName: 'MoneyLedger',
          ),
        ),
        kAuthRequestTimeout,
        'login',
      );
    }),
  );

  @override
  Future<void> register({
    required String homeserver,
    required String username,
    required String password,
  }) => _flight.operation(
    () => _translated(
      homeserver,
      () => _register(homeserver, username, password),
    ),
  );

  Future<void> _register(
    String homeserver,
    String username,
    String password,
  ) async {
    await _checkHomeserver(homeserver);
    try {
      // First attempt with no auth: an open server completes immediately;
      // otherwise it answers with a UIA challenge (flows + session).
      await withAuthTimeout(
        _flight.track(
          _client.register(
            username: username,
            password: password,
            initialDeviceDisplayName: 'MoneyLedger',
          ),
        ),
        kAuthRequestTimeout,
        'register',
      );
    } on MatrixException catch (e) {
      final flows = e.authenticationFlows;
      if (isClientRegistrationDisabled(e.errcode, hasFlows: flows != null)) {
        // e.g. matrix.org (MAS/OIDC): sign-up only on the website.
        throw RegistrationRequiresWebException(homeserver, const [
          kWebSignupStage,
        ], signUpUrl: await _signUpUrl(homeserver));
      }
      if (flows == null) rethrow; // not a UIA challenge (e.g. username taken)
      final plan = classifyRegistrationFlows([for (final f in flows) f.stages]);
      final session = e.session;
      if (!plan.canRegisterInApp || session == null) {
        throw RegistrationRequiresWebException(
          homeserver,
          plan.blockingStages,
          signUpUrl: await _signUpUrl(homeserver),
        );
      }
      // Complete the no-op dummy stage to finish sign-up.
      await withAuthTimeout(
        _flight.track(
          _client.register(
            username: username,
            password: password,
            initialDeviceDisplayName: 'MoneyLedger',
            auth: AuthenticationData(
              type: AuthenticationTypes.dummy,
              session: session,
            ),
          ),
        ),
        kAuthRequestTimeout,
        'register',
      );
    }
  }

  @override
  Future<void> logout() => _client.logout();

  // ── error translation (G20) ───────────────────────────────────────────────

  /// Reference server probed when the homeserver is unreachable, to tell "the
  /// device is offline" from "that server is down / doesn't exist".
  static final _connectivityProbe = Uri.parse('https://matrix.org');
  static const _probeTimeout = Duration(seconds: 5);

  /// `checkHomeserver`, with any non-network failure (no `/versions`, HTML
  /// instead of JSON, …) reported as [NotAHomeserverException].
  Future<void> _checkHomeserver(String homeserver) async {
    try {
      await withAuthTimeout(
        _flight.track(_client.checkHomeserver(Uri.parse(homeserver))),
        kHomeserverCheckTimeout,
        'checkHomeserver',
      );
    } catch (e) {
      if (isNetworkError(e) || e is BadServerLoginTypesException) rethrow;
      if (e is MatrixException && e.errcode != 'M_UNRECOGNIZED') rethrow;
      throw NotAHomeserverException(_host(homeserver), e);
    }
  }

  /// Runs [body], translating SDK / transport errors into the plain-Dart
  /// failures of the auth port so the UI's pure `describeAuthError` can
  /// classify them without `package:matrix`.
  Future<void> _translated(
    String homeserver,
    Future<void> Function() body,
  ) async {
    try {
      await body();
    } on MatrixException catch (e) {
      throw AuthServerException(
        e.errcode,
        serverMessage: e.errorMessage,
        retryAfterMs: e.retryAfterMs,
      );
    } catch (e) {
      if (e is AuthServerException ||
          e is NotAHomeserverException ||
          e is RegistrationRequiresWebException ||
          !isNetworkError(e)) {
        rethrow;
      }
      // A timeout means the server didn't answer in time — no need to spend
      // another few seconds probing whether the device is offline.
      if (e is TimeoutException) {
        throw AuthNetworkException(
          _host(homeserver),
          deviceOffline: false,
          cause: e,
        );
      }
      throw AuthNetworkException(
        _host(homeserver),
        deviceOffline: !await _referenceServerReachable(),
        cause: e,
      );
    }
  }

  static Future<bool> _referenceServerReachable() async {
    final api = MatrixApi(homeserver: _connectivityProbe);
    try {
      await api.getVersions().timeout(_probeTimeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      api.httpClient.close();
    }
  }

  static String _host(String homeserver) {
    final uri = Uri.tryParse(homeserver);
    return (uri == null || uri.host.isEmpty) ? homeserver : uri.host;
  }

  /// Best-effort sign-up page for [homeserver] (see `sign_up_url.dart`):
  /// fetches the OIDC auth metadata + `.well-known`, never throws.
  Future<String> _signUpUrl(String homeserver) async {
    final entered = Uri.parse(homeserver);
    final base = _client.homeserver ?? entered;
    Map<String, Object?>? metadata;
    Map<String, Object?>? wellKnown;
    final api = MatrixApi(homeserver: base);
    try {
      for (final path in const [
        '/client/v1/auth_metadata',
        '/client/unstable/org.matrix.msc2965/auth_metadata',
      ]) {
        try {
          metadata = await api
              .request(RequestType.GET, path)
              .timeout(_lookupTimeout);
          break;
        } catch (_) {}
      }
    } finally {
      api.httpClient.close();
    }
    if (metadata == null) {
      final probe = MatrixApi(homeserver: entered);
      try {
        final wk = await probe.getWellknown().timeout(_lookupTimeout);
        wellKnown = wk.toJson();
      } catch (_) {
      } finally {
        probe.httpClient.close();
      }
    }
    final url = resolveSignUpUrl(
      homeserverUrl: homeserver,
      resolvedBaseUrl: base.toString(),
      authMetadata: metadata,
      wellKnown: wellKnown,
    );
    debugPrint('[register] sign-up url for $homeserver -> $url');
    return url;
  }

  // ── login-flows parsing helpers ───────────────────────────────────────────

  static LoginFlowsResult _toResult(String resolvedUrl, List<LoginFlow> flows) {
    final hasSso = flows.any((f) => f.type == AuthenticationTypes.sso);
    final hasPassword = flows.any(
      (f) => f.type == AuthenticationTypes.password,
    );
    // Servers running native OIDC or token-only configs report no m.login.sso
    // and no m.login.password (e.g. mozilla.modular.im returns [m.login.token]).
    // In that case, offer SSO — the generic SSO redirect endpoint still works.
    final ssoAvailable = hasSso || !hasPassword;
    final ssoFlow = flows.cast<LoginFlow?>().firstWhere(
      (f) => f?.type == AuthenticationTypes.sso,
      orElse: () => null,
    );
    final providers =
        (ssoFlow?.additionalProperties['identity_providers'] as List?)
            ?.cast<Map>()
            .map(
              (p) => SsoProvider(
                id: p['id'] as String? ?? '',
                name: p['name'] as String? ?? 'SSO',
                brand: p['brand'] as String?,
              ),
            )
            .toList() ??
        [];
    return LoginFlowsResult(
      resolvedUrl: resolvedUrl,
      hasPassword: hasPassword,
      hasSso: ssoAvailable,
      ssoProviders: providers,
    );
  }

  /// Turns arbitrary user input into a well-formed Uri, or null if unparseable.
  static Uri? _normalise(String raw) {
    raw = raw.trim();
    if (raw.isEmpty) return null;
    // Strip leading "@user:" to extract just the domain from a Matrix ID.
    if (raw.startsWith('@')) {
      final colon = raw.indexOf(':');
      if (colon == -1) return null;
      raw = raw.substring(colon + 1);
    }
    // Add https:// if no scheme.
    if (!raw.startsWith('http')) raw = 'https://$raw';
    return Uri.tryParse(raw);
  }
}
