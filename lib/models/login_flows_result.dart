/// No matrix SDK imports here — tests can use this model without hitting
/// the sqlite3/open.dart compilation issue.
class LoginFlowsResult {
  final String resolvedUrl;
  final bool hasPassword;
  final bool hasSso;
  final List<SsoProvider> ssoProviders;

  const LoginFlowsResult({
    required this.resolvedUrl,
    required this.hasPassword,
    required this.hasSso,
    required this.ssoProviders,
  });

  static const empty = LoginFlowsResult(
    resolvedUrl: '',
    hasPassword: true, // show password form by default before flows load
    hasSso: false,
    ssoProviders: [],
  );
}

class SsoProvider {
  final String id;
  final String name;
  final String? brand;
  const SsoProvider({required this.id, required this.name, this.brand});
}
