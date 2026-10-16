import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/auth/sso_callback.dart';

void main() {
  group('parseSsoCallback', () {
    test('extracts token and homeserver from a native deep link', () {
      final cb = parseSsoCallback(
        Uri.parse(
          'moneyledger://sso-callback/?loginToken=abc123&hs=https://matrix.org',
        ),
      );
      expect(cb, isNotNull);
      expect(cb!.loginToken, 'abc123');
      expect(cb.homeserver, 'https://matrix.org');
    });

    test('extracts token from a web redirect URL', () {
      final cb = parseSsoCallback(
        Uri.parse('https://app.example/?loginToken=xyz'),
      );
      expect(cb!.loginToken, 'xyz');
      expect(cb.homeserver, isNull);
    });

    test('returns null when there is no login token', () {
      expect(
        parseSsoCallback(Uri.parse('moneyledger://sso-callback/')),
        isNull,
      );
      expect(parseSsoCallback(Uri.parse('https://app.example/?hs=x')), isNull);
    });

    test('treats an empty token as no token', () {
      expect(
        parseSsoCallback(Uri.parse('moneyledger://sso-callback/?loginToken=')),
        isNull,
      );
    });

    test('ignores an empty homeserver hint', () {
      final cb = parseSsoCallback(
        Uri.parse('moneyledger://sso-callback/?loginToken=t&hs='),
      );
      expect(cb!.homeserver, isNull);
    });
  });

  group('redactSsoUri (G15: no login token in logs)', () {
    test('replaces the token, keeps the rest', () {
      final out = redactSsoUri(
        Uri.parse('moneyledger://sso-callback?loginToken=s3cr3t&hs=x.org'),
      );
      expect(out, isNot(contains('s3cr3t')));
      expect(out, contains('loginToken=%3Credacted%3E'));
      expect(out, contains('hs=x.org'));
    });

    test('a URI without a token is unchanged', () {
      expect(
        redactSsoUri(Uri.parse('https://app.example/?hs=x.org')),
        'https://app.example/?hs=x.org',
      );
    });
  });
}
