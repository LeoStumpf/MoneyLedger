import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/link/link_keys.dart';
import 'package:money_ledger/core/link/link_uri.dart';

final _secret = List<int>.generate(32, (i) => i);
const _k = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';

Matcher _fails(LinkUriError kind) =>
    throwsA(isA<LinkUriException>().having((e) => e.kind, 'kind', kind));

void main() {
  group('build', () {
    test('web and app forms (exact format)', () {
      expect(encodeLinkSecret(_secret), _k);
      expect(
        buildLinkUri(_secret, name: 'Trip to Rome'),
        'https://leostumpf.github.io/moneyledger/join#v=1&k=$_k&n=Trip%20to%20Rome',
      );
      expect(
        buildLinkUri(_secret, form: LinkUriForm.app),
        'moneyledger://join#v=1&k=$_k',
      );
    });

    test('the name hint is trimmed, blank → omitted', () {
      expect(buildLinkFragment(_secret, name: '  '), 'v=1&k=$_k');
      expect(buildLinkFragment(_secret, name: ' Rom '), 'v=1&k=$_k&n=Rom');
    });

    test('reserved characters are percent-encoded', () {
      final uri = buildLinkUri(_secret, name: 'A&B=C #1 100%');
      expect(uri, endsWith('&n=A%26B%3DC%20%231%20100%25'));
      expect(parseLinkUri(uri).name, 'A&B=C #1 100%');
    });

    test('a long name is cut to 40 UTF-16 units, never inside a pair', () {
      expect(linkNameHint('x' * 50), 'x' * 40);
      // 39 × "a" + an emoji (2 units): cutting at 40 would split it.
      expect(linkNameHint('${'a' * 39}😀tail'), 'a' * 39);
      expect(linkNameHint('${'a' * 38}😀tail'), '${'a' * 38}😀');
      expect(linkNameHint(null), isNull);
    });

    test('wrong secret length is an ArgumentError', () {
      expect(() => buildLinkUri(List.filled(16, 0)), throwsArgumentError);
    });
  });

  group('round trip', () {
    for (final name in [
      'Trip to Rome',
      'Ferienwohnung Ölberg – Spaß',
      'WG 🏠🍕 & Co.',
      '👨‍👩‍👧 family',
      '日本旅行',
      null,
    ]) {
      for (final form in LinkUriForm.values) {
        test('${form.name}: $name', () {
          final secret = generateLinkSecret();
          final invite = parseLinkUri(
            buildLinkUri(secret, name: name, form: form),
          );
          expect(invite.version, kLinkVersion);
          expect(invite.secret, secret);
          expect(invite.name, name);
        });
      }
    }

    test('random secrets round-trip through k', () {
      for (var i = 0; i < 200; i++) {
        final s = generateLinkSecret();
        final k = encodeLinkSecret(s);
        expect(k, hasLength(43));
        expect(decodeLinkSecret(k), s);
      }
    });
  });

  group('parse', () {
    test('tolerates whitespace, case, trailing slash, key order, extras', () {
      for (final input in [
        '  https://leostumpf.github.io/moneyledger/join#v=1&k=$_k  ',
        'HTTPS://LeoStumpf.GitHub.io/moneyledger/join#v=1&k=$_k',
        'https://leostumpf.github.io/moneyledger/join/#v=1&k=$_k',
        'moneyledger://join#k=$_k&v=1',
        'moneyledger://join/#v=1&k=$_k&r=wss%3A%2F%2Fx&',
      ]) {
        final invite = parseLinkUri(input);
        expect(invite.secret, _secret, reason: input);
        expect(invite.name, isNull);
      }
    });

    test('decodes umlauts / emoji in n', () {
      final invite = parseLinkUri(
        'moneyledger://join#v=1&k=$_k&n=%C3%9Cberfahrt%20%F0%9F%9A%A2',
      );
      expect(invite.name, 'Überfahrt 🚢');
    });

    test('a pasted link with an unencoded name still parses', () {
      final invite = parseLinkUri(
        'moneyledger://join#v=1&k=$_k&n=Überfahrt 🚢',
      );
      expect(invite.name, 'Überfahrt 🚢');
    });

    test('parseLinkFragment accepts a leading #', () {
      expect(parseLinkFragment('#v=1&k=$_k&n=X').name, 'X');
    });

    test('not one of our links', () {
      for (final input in [
        '',
        'garbage',
        'http://leostumpf.github.io/moneyledger/join#v=1&k=$_k',
        'https://evil.example/moneyledger/join#v=1&k=$_k',
        'https://leostumpf.github.io/other/join#v=1&k=$_k',
        'https://leostumpf.github.io/moneyledger/join',
        'https://leostumpf.github.io/moneyledger/join#',
        'https://leostumpf.github.io/moneyledger/join?v=1&k=$_k',
        'moneyledger://sso#v=1&k=$_k',
        'moneyledger://join/x#v=1&k=$_k',
        'mailto:a@b.c',
        'https://[::1',
      ]) {
        expect(
          () => parseLinkUri(input),
          _fails(LinkUriError.notALink),
          reason: input,
        );
      }
    });

    test('unknown version → unsupportedVersion (before the secret)', () {
      expect(
        () => parseLinkUri('moneyledger://join#v=2&k=whatever'),
        throwsA(
          isA<LinkUriException>()
              .having((e) => e.kind, 'kind', LinkUriError.unsupportedVersion)
              .having((e) => e.version, 'version', 2),
        ),
      );
      expect(
        () => parseLinkFragment('v=0&k=$_k'),
        _fails(LinkUriError.unsupportedVersion),
      );
    });

    test('malformed fragments', () {
      for (final f in [
        'k=$_k', // no v
        'v=&k=$_k',
        'v=one&k=$_k',
        'v=-1&k=$_k',
        'v=1.0&k=$_k',
        'v=12345678&k=$_k',
        'v=1&v=1&k=$_k', // duplicate
        'v=1&k=$_k&k=$_k',
        'v=1&k=$_k&n=%zz', // bad escape
        'v=1&k=$_k&n=%C3', // invalid UTF-8
      ]) {
        expect(
          () => parseLinkFragment(f),
          _fails(LinkUriError.malformed),
          reason: f,
        );
      }
    });

    test('missing secret', () {
      expect(
        () => parseLinkFragment('v=1'),
        _fails(LinkUriError.missingSecret),
      );
      expect(
        () => parseLinkFragment('v=1&k=&n=x'),
        _fails(LinkUriError.missingSecret),
      );
    });

    test('invalid secrets', () {
      for (final k in [
        _k.substring(0, 42), // short
        '${_k}A', // long
        '$_k=', // padded
        'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh+', // std alphabet
        'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh!',
        'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh9', // non-canonical bits
        'A' * 22, // 16 bytes
      ]) {
        expect(
          () => parseLinkFragment('v=1&k=$k'),
          _fails(LinkUriError.invalidSecret),
          reason: k,
        );
      }
    });

    test('name length: 40 units ok, 41 → nameTooLong; blank → null', () {
      expect(parseLinkFragment('v=1&k=$_k&n=${'x' * 40}').name, 'x' * 40);
      expect(
        () => parseLinkFragment('v=1&k=$_k&n=${'x' * 41}'),
        _fails(LinkUriError.nameTooLong),
      );
      // 20 emoji = 40 UTF-16 units.
      final emoji = Uri.encodeComponent('😀' * 21);
      expect(
        () => parseLinkFragment('v=1&k=$_k&n=$emoji'),
        _fails(LinkUriError.nameTooLong),
      );
      expect(parseLinkFragment('v=1&k=$_k&n=%20%20').name, isNull);
      expect(parseLinkFragment('v=1&k=$_k&n').name, isNull);
    });
  });
}
