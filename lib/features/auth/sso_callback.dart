/// Pure parsing for the SSO login-token callback. Works for both the web
/// redirect (`https://app/?loginToken=…&hs=…`) and the native deep link
/// (`moneyledger://sso-callback?loginToken=…&hs=…`). No platform imports.
class SsoCallback {
  final String loginToken;

  /// Homeserver hint we attached to the redirect URL, if present.
  final String? homeserver;

  const SsoCallback({required this.loginToken, this.homeserver});
}

/// Extracts the SSO callback from [uri], or null if it carries no login token.
SsoCallback? parseSsoCallback(Uri uri) {
  final token = uri.queryParameters['loginToken'];
  if (token == null || token.isEmpty) return null;
  final hs = uri.queryParameters['hs'];
  return SsoCallback(
    loginToken: token,
    homeserver: (hs != null && hs.isNotEmpty) ? hs : null,
  );
}
