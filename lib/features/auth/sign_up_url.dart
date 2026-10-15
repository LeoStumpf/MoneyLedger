/// Where to send a user who must create their account on the web (G20).
///
/// Pure Dart (no Flutter / `package:matrix`) — the real gateway fetches the
/// raw JSON and this decides. Order:
/// 1. **OIDC auth metadata** (`GET /_matrix/client/v1/auth_metadata`, MSC2965
///    / Matrix 1.15): a Matrix Authentication Service that supports
///    `prompt=create` serves its sign-up page at `<issuer>register`; otherwise
///    its `account_management_uri` (the account portal, which links sign-up).
/// 2. `.well-known/matrix/client` → `org.matrix.msc2965.authentication.account`.
/// 3. matrix.org without any of the above → Element's web sign-up.
/// 4. The homeserver's base URL.
library;

/// Element's sign-up flow — the fallback for matrix.org (G20).
const kMatrixOrgSignUpFallback = 'https://app.element.io/#/register';

String resolveSignUpUrl({
  required String homeserverUrl,
  String? resolvedBaseUrl,
  Map<String, Object?>? authMetadata,
  Map<String, Object?>? wellKnown,
}) {
  if (authMetadata != null) {
    final issuer = _httpUrl(authMetadata['issuer']);
    final prompts = authMetadata['prompt_values_supported'];
    if (issuer != null && prompts is List && prompts.contains('create')) {
      final base = issuer.endsWith('/') ? issuer : '$issuer/';
      return '${base}register';
    }
    final account = _httpUrl(authMetadata['account_management_uri']);
    if (account != null) return account;
  }
  if (wellKnown != null) {
    final auth = wellKnown['org.matrix.msc2965.authentication'];
    if (auth is Map) {
      final account = _httpUrl(auth['account']);
      if (account != null) return account;
    }
  }
  if (_isMatrixOrg(homeserverUrl) ||
      (resolvedBaseUrl != null && _isMatrixOrg(resolvedBaseUrl))) {
    return kMatrixOrgSignUpFallback;
  }
  return resolvedBaseUrl ?? homeserverUrl;
}

bool _isMatrixOrg(String url) {
  final host = Uri.tryParse(url.contains('://') ? url : 'https://$url')?.host;
  return host != null && (host == 'matrix.org' || host.endsWith('.matrix.org'));
}

/// [v] if it's an absolute http(s) URL, else null (never open odd schemes).
String? _httpUrl(Object? v) {
  if (v is! String) return null;
  final uri = Uri.tryParse(v);
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    return null;
  }
  return uri.host.isEmpty ? null : v;
}
