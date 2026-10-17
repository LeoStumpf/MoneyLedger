/// G52: the invite link of a link group (design doc
/// `docs/design/no-login-sharing.md` §2.1).
///
/// ```
/// https://leostumpf.github.io/moneyledger/join#v=1&k=<secret>&n=<name>
/// moneyledger://join#v=1&k=<secret>&n=<name>
/// ```
///
/// Everything lives in the URL **fragment**, which browsers never send to a
/// server (GitHub Pages and link-preview fetchers never see the secret).
/// `v` is the link / key-derivation version, `k` the 32-byte link secret as
/// base64url without padding (43 chars), `n` an optional group-name hint
/// (percent-encoded UTF-8, ≤ [kMaxLinkNameLength] UTF-16 units). Unknown
/// fragment keys are ignored (room for later additions such as relay hints).
///
/// Pure Dart: no Flutter, no I/O. Parse errors are [LinkUriException]s with a
/// [LinkUriError] kind — never raw exceptions — so the UI can map them to
/// localized text ("Please update the app" for [LinkUriError.unsupportedVersion]).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'link_keys.dart';

/// The link version this build writes and understands.
const kLinkVersion = 1;

/// Host + path of the https form (the GitHub Pages landing page / App Link).
const kLinkWebHost = 'leostumpf.github.io';
const kLinkWebPath = '/moneyledger/join';

/// Scheme + host of the app form (Android intent filter).
const kLinkAppScheme = 'moneyledger';
const kLinkAppHost = 'join';

/// Longest group-name hint (`n`) in UTF-16 code units — the same measure as
/// group / category names elsewhere.
const kMaxLinkNameLength = 40;

/// Which of the two equivalent link forms to build.
enum LinkUriForm {
  /// `https://leostumpf.github.io/moneyledger/join#…` — what is shared and
  /// put into the QR code (opens the app via App Link, else the landing page).
  web,

  /// `moneyledger://join#…` — opens an installed app directly.
  app,
}

/// Why a link couldn't be parsed.
enum LinkUriError {
  /// Not one of our join links (other scheme / host / path, no fragment, not
  /// a URI at all).
  notALink,

  /// Our link, but the fragment is broken (duplicate keys, a non-numeric
  /// `v`, a missing `v`, bad percent-encoding).
  malformed,

  /// A `v` this build doesn't know — "Please update the app".
  unsupportedVersion,

  /// No `k` in the fragment.
  missingSecret,

  /// `k` isn't 32 bytes of canonical unpadded base64url.
  invalidSecret,

  /// `n` is longer than [kMaxLinkNameLength].
  nameTooLong,
}

/// A link that couldn't be parsed; [version] is set for
/// [LinkUriError.unsupportedVersion].
class LinkUriException implements Exception {
  final LinkUriError kind;
  final int? version;
  const LinkUriException(this.kind, {this.version});

  @override
  String toString() =>
      'LinkUriException(${kind.name}${version == null ? '' : ', v=$version'})';
}

/// A parsed invite link.
class LinkInvite {
  /// The link version (always [kLinkVersion] for a parsed link).
  final int version;

  /// The [kLinkSecretLength]-byte link secret.
  final Uint8List secret;

  /// The group-name hint, trimmed; null when absent or blank.
  final String? name;

  const LinkInvite({
    required this.version,
    required this.secret,
    required this.name,
  });
}

/// The secret as it appears in `k`: base64url without padding (43 chars).
String encodeLinkSecret(List<int> secret) {
  _checkSecretLength(secret);
  return base64Url.encode(secret).replaceAll('=', '');
}

/// The inverse of [encodeLinkSecret]. Only the canonical encoding is
/// accepted (43 chars of the base64url alphabet, unused low bits zero), so a
/// secret has exactly one spelling. Throws [LinkUriException]
/// ([LinkUriError.invalidSecret]).
Uint8List decodeLinkSecret(String k) {
  if (k.length != 43 || !_base64UrlChars.hasMatch(k)) {
    throw const LinkUriException(LinkUriError.invalidSecret);
  }
  final Uint8List bytes;
  try {
    bytes = base64Url.decode('$k=');
  } on FormatException {
    throw const LinkUriException(LinkUriError.invalidSecret);
  }
  if (bytes.length != kLinkSecretLength || encodeLinkSecret(bytes) != k) {
    throw const LinkUriException(LinkUriError.invalidSecret);
  }
  return bytes;
}

final _base64UrlChars = RegExp(r'^[A-Za-z0-9_-]+$');

/// The `n` hint for a group named [groupName]: trimmed, cut to
/// [kMaxLinkNameLength] UTF-16 units (never inside a surrogate pair), null
/// when nothing is left.
String? linkNameHint(String? groupName) {
  var name = groupName?.trim() ?? '';
  if (name.length > kMaxLinkNameLength) {
    var end = kMaxLinkNameLength;
    final last = name.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--; // high surrogate: keep pair
    name = name.substring(0, end).trimRight();
  }
  return name.isEmpty ? null : name;
}

/// The fragment `v=1&k=<secret>[&n=<name>]` (without `#`). [name] goes
/// through [linkNameHint] and is percent-encoded.
String buildLinkFragment(List<int> secret, {String? name}) {
  final hint = linkNameHint(name);
  return [
    'v=$kLinkVersion',
    'k=${encodeLinkSecret(secret)}',
    if (hint != null) 'n=${Uri.encodeComponent(hint)}',
  ].join('&');
}

/// The full invite link (§2.1) in the chosen [form].
String buildLinkUri(
  List<int> secret, {
  String? name,
  LinkUriForm form = LinkUriForm.web,
}) {
  final fragment = buildLinkFragment(secret, name: name);
  return switch (form) {
    LinkUriForm.web => 'https://$kLinkWebHost$kLinkWebPath#$fragment',
    LinkUriForm.app => '$kLinkAppScheme://$kLinkAppHost#$fragment',
  };
}

/// Parses a pasted / opened invite link (surrounding whitespace is ignored;
/// host and scheme are case-insensitive, a trailing `/` on the path is
/// tolerated). Throws [LinkUriException].
LinkInvite parseLinkUri(String input) {
  final Uri uri;
  try {
    uri = Uri.parse(input.trim());
  } on FormatException {
    throw const LinkUriException(LinkUriError.notALink);
  }
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final path = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  final ours = switch (scheme) {
    'https' => host == kLinkWebHost && path == kLinkWebPath,
    kLinkAppScheme => host == kLinkAppHost && path.isEmpty,
    _ => false,
  };
  if (!ours || !uri.hasFragment || uri.fragment.isEmpty) {
    throw const LinkUriException(LinkUriError.notALink);
  }
  return parseLinkFragment(uri.fragment);
}

/// Parses the fragment part alone (`v=1&k=…&n=…`, a leading `#` is
/// allowed) — also the seam for the web app's `#/join?…` route. Throws
/// [LinkUriException].
LinkInvite parseLinkFragment(String fragment) {
  final raw = fragment.startsWith('#') ? fragment.substring(1) : fragment;
  final params = <String, String>{};
  for (final pair in raw.split('&')) {
    if (pair.isEmpty) continue;
    final eq = pair.indexOf('=');
    final key = eq < 0 ? pair : pair.substring(0, eq);
    final String value;
    try {
      value = Uri.decodeComponent(eq < 0 ? '' : pair.substring(eq + 1));
    } catch (_) {
      // Bad `%` escapes / invalid UTF-8 (ArgumentError or FormatException).
      throw const LinkUriException(LinkUriError.malformed);
    }
    if (params.containsKey(key)) {
      throw const LinkUriException(LinkUriError.malformed);
    }
    params[key] = value;
  }

  final v = params['v'];
  if (v == null || !RegExp(r'^[0-9]{1,6}$').hasMatch(v)) {
    throw const LinkUriException(LinkUriError.malformed);
  }
  final version = int.parse(v);
  if (version != kLinkVersion) {
    throw LinkUriException(LinkUriError.unsupportedVersion, version: version);
  }

  final k = params['k'];
  if (k == null || k.isEmpty) {
    throw const LinkUriException(LinkUriError.missingSecret);
  }
  final secret = decodeLinkSecret(k);

  final name = params['n']?.trim();
  if (name != null && name.length > kMaxLinkNameLength) {
    throw const LinkUriException(LinkUriError.nameTooLong);
  }
  return LinkInvite(
    version: version,
    secret: secret,
    name: name == null || name.isEmpty ? null : name,
  );
}

void _checkSecretLength(List<int> secret) {
  if (secret.length != kLinkSecretLength) {
    throw ArgumentError.value(
      secret.length,
      'secret',
      'a link secret has $kLinkSecretLength bytes',
    );
  }
}
