/// Pure builder for the homeserver SSO redirect URL — the page the user is sent
/// to to authenticate. No platform/Matrix imports, so it's unit-testable.
String buildSsoRedirectUrl({
  required String homeserver,
  required String callbackUrl,
  String? providerId,
}) {
  final base = Uri.parse(homeserver);
  final path = providerId != null
      ? '_matrix/client/v3/login/sso/redirect/$providerId'
      : '_matrix/client/v3/login/sso/redirect';
  return base
      .resolve(path)
      .replace(queryParameters: {'redirectUrl': callbackUrl})
      .toString();
}

/// The server name shown on the generic SSO button (G29): what the user
/// entered (`matrix.org`), not the `.well-known`-resolved client URL
/// (`matrix-client.matrix.org`) — so the label doesn't flip while discovery
/// runs. Scheme, path and trailing slashes are stripped.
String ssoServerLabel(String input) {
  final trimmed = input.trim();
  final uri = Uri.tryParse(
      trimmed.contains('://') ? trimmed : 'https://$trimmed');
  final host = uri?.host ?? '';
  if (host.isEmpty) return trimmed;
  return uri!.hasPort ? '$host:${uri.port}' : host;
}
