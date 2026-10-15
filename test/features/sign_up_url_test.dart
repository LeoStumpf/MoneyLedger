/// resolveSignUpUrl (G20): where "Open homeserver website" sends the user.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/auth/sign_up_url.dart';

void main() {
  test('MAS with prompt=create → its /register page (matrix.org today)', () {
    expect(
        resolveSignUpUrl(
          homeserverUrl: 'https://matrix.org',
          resolvedBaseUrl: 'https://matrix-client.matrix.org',
          authMetadata: {
            'issuer': 'https://account.matrix.org/',
            'account_management_uri': 'https://account.matrix.org/account/',
            'prompt_values_supported': ['login', 'create'],
          },
        ),
        'https://account.matrix.org/register');
  });

  test('issuer without trailing slash', () {
    expect(
        resolveSignUpUrl(homeserverUrl: 'https://x.org', authMetadata: {
          'issuer': 'https://auth.x.org',
          'prompt_values_supported': ['create'],
        }),
        'https://auth.x.org/register');
  });

  test('auth metadata without create → account_management_uri', () {
    expect(
        resolveSignUpUrl(homeserverUrl: 'https://x.org', authMetadata: {
          'issuer': 'https://auth.x.org/',
          'account_management_uri': 'https://auth.x.org/account',
        }),
        'https://auth.x.org/account');
  });

  test('.well-known msc2965 account URL', () {
    expect(
        resolveSignUpUrl(homeserverUrl: 'https://x.org', wellKnown: {
          'm.homeserver': {'base_url': 'https://hs.x.org'},
          'org.matrix.msc2965.authentication': {
            'issuer': 'https://auth.x.org/',
            'account': 'https://auth.x.org/account',
          },
        }),
        'https://auth.x.org/account');
  });

  test('matrix.org without metadata → Element sign-up', () {
    expect(resolveSignUpUrl(homeserverUrl: 'https://matrix.org'),
        kMatrixOrgSignUpFallback);
    expect(
        resolveSignUpUrl(
            homeserverUrl: 'matrix.org',
            resolvedBaseUrl: 'https://matrix-client.matrix.org'),
        kMatrixOrgSignUpFallback);
  });

  test('otherwise the homeserver base URL', () {
    expect(
        resolveSignUpUrl(
            homeserverUrl: 'https://x.org', resolvedBaseUrl: 'https://hs.x.org'),
        'https://hs.x.org');
    expect(resolveSignUpUrl(homeserverUrl: 'https://x.org'), 'https://x.org');
  });

  test('ignores non-http URLs and garbage', () {
    expect(
        resolveSignUpUrl(homeserverUrl: 'https://x.org', authMetadata: {
          'issuer': 'javascript:alert(1)',
          'prompt_values_supported': ['create'],
          'account_management_uri': 42,
        }),
        'https://x.org');
    // A look-alike domain is not matrix.org.
    expect(resolveSignUpUrl(homeserverUrl: 'https://evilmatrix.org'),
        'https://evilmatrix.org');
  });
}
