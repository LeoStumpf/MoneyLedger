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
