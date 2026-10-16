import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/auth/sso_url.dart';

void main() {
  group('buildSsoRedirectUrl', () {
    test('uses the generic redirect endpoint without a provider', () {
      final url = buildSsoRedirectUrl(
        homeserver: 'https://matrix.org',
        callbackUrl: 'moneyledger://sso-callback/?hs=x',
      );
      final uri = Uri.parse(url);
      expect(uri.path, '/_matrix/client/v3/login/sso/redirect');
      expect(
        uri.queryParameters['redirectUrl'],
        'moneyledger://sso-callback/?hs=x',
      );
    });

    test('targets a specific provider when given', () {
      final url = buildSsoRedirectUrl(
        homeserver: 'https://matrix.org',
        callbackUrl: 'https://app/',
        providerId: 'oidc-google',
      );
      expect(
        Uri.parse(url).path,
        '/_matrix/client/v3/login/sso/redirect/oidc-google',
      );
    });

    test('preserves the homeserver host and scheme', () {
      final url = buildSsoRedirectUrl(
        homeserver: 'https://chat.example.com',
        callbackUrl: 'https://app/',
      );
      final uri = Uri.parse(url);
      expect(uri.scheme, 'https');
      expect(uri.host, 'chat.example.com');
    });
  });
}
