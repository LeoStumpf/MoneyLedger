import 'package:matrix/matrix.dart';

import '../../models/login_flows_result.dart';
import 'auth_gateway.dart';

/// Real [AuthGateway] backed by the Matrix SDK [Client]. The only place that
/// translates Matrix auth types into the app's plain-Dart auth port.
class MatrixAuthGateway implements AuthGateway {
  final Client _client;
  MatrixAuthGateway(this._client);

  @override
  bool get isLoggedIn => _client.isLogged();

  @override
  String? get userId => _client.userID;

  @override
  Stream<bool> get loginStateChanges =>
      _client.onLoginStateChanged.stream.map((_) => _client.isLogged());

  @override
  Future<LoginFlowsResult> loginFlows(String input) async {
    final normalised = _normalise(input);
    if (normalised == null) return LoginFlowsResult.empty;

    // Step 1: try .well-known discovery to find the real homeserver URL.
    Uri resolved = normalised;
    try {
      final probe = MatrixApi(homeserver: normalised);
      final wk = await probe.getWellknown();
      probe.httpClient.close();
      resolved = wk.mHomeserver.baseUrl;
    } catch (_) {
      // No .well-known or server doesn't support it — use the URL as-is.
    }

    // Step 2: fetch login flows from the resolved URL.
    try {
      final api = MatrixApi(homeserver: resolved);
      final rawFlows = await api.getLoginFlows() ?? [];
      api.httpClient.close();
      return _toResult(resolved.toString(), rawFlows);
    } catch (_) {
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
  }) async {
    await _client.checkHomeserver(Uri.parse(homeserver));
    await _client.login(
      AuthenticationTypes.password,
      identifier: AuthenticationUserIdentifier(user: username),
      password: password,
      initialDeviceDisplayName: 'MoneyLedger',
    );
  }

  @override
  Future<void> loginWithToken({
    required String homeserver,
    required String token,
  }) async {
    await _client.checkHomeserver(Uri.parse(homeserver));
    await _client.login(
      AuthenticationTypes.token,
      token: token,
      initialDeviceDisplayName: 'MoneyLedger',
    );
  }

  @override
  Future<void> logout() => _client.logout();

  // ── login-flows parsing helpers ───────────────────────────────────────────

  static LoginFlowsResult _toResult(String resolvedUrl, List<LoginFlow> flows) {
    final hasSso = flows.any((f) => f.type == AuthenticationTypes.sso);
    final hasPassword =
        flows.any((f) => f.type == AuthenticationTypes.password);
    // Servers running native OIDC or token-only configs report no m.login.sso
    // and no m.login.password (e.g. mozilla.modular.im returns [m.login.token]).
    // In that case, offer SSO — the generic SSO redirect endpoint still works.
    final ssoAvailable = hasSso || !hasPassword;
    final ssoFlow = flows.cast<LoginFlow?>().firstWhere(
        (f) => f?.type == AuthenticationTypes.sso,
        orElse: () => null);
    final providers =
        (ssoFlow?.additionalProperties['identity_providers'] as List?)
                ?.cast<Map>()
                .map((p) => SsoProvider(
                      id: p['id'] as String? ?? '',
                      name: p['name'] as String? ?? 'SSO',
                      brand: p['brand'] as String?,
                    ))
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
