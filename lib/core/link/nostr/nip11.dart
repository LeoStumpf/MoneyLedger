/// G52 step 5: NIP-11 relay information documents (design doc
/// `docs/design/no-login-sharing.md` §4.6).
///
/// `GET https://<relay>` with `Accept: application/nostr+json` → the
/// `limitation` fields and `supported_nips`. Used for two things:
/// - **the size budget per relay** ([relayContentBudget]): the default relays
///   advertise only a 131 072-byte frame but refuse events over 65 536 bytes
///   (G51, §16), so every relay gets [kLinkContentBudget] at most, and a
///   relay advertising a smaller `max_message_length` / `max_content_length`
///   lowers it;
/// - **a usability check for custom relays** ([relayInfoProblem], the relay
///   settings of G52 step 9): `auth_required` / `payment_required` → "this
///   relay needs an account"; no NIP-40 → expirations wouldn't be honoured.
///
/// The document is cached for [kRelayInfoMaxAge] (7 days) in the relay's
/// state (`link_relay_state:<url>`, see `link_relay_policy.dart`). Fetching it
/// is best-effort: a relay without NIP-11 just gets the default budget.
/// Parsing is pure Dart and tolerant (wrong types read as absent); the HTTP
/// adapter is [HttpRelayInfoFetcher] (`package:http`, works on the web — the
/// relays answer CORS for NIP-11).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../link_snapshot.dart' show kLinkContentBudget;

/// How long a fetched NIP-11 document stays valid (§4.6).
const kRelayInfoMaxAge = Duration(days: 7);

/// How long one NIP-11 request may take.
const kRelayInfoTimeout = Duration(seconds: 10);

/// Bytes an `EVENT` frame carries besides `content` (id, pubkey, sig,
/// `created_at`, kind, the `d` / `expiration` / `alt` tags, the frame
/// wrapper — ≈ 500 B measured in G51, §5.4) plus headroom for a part suffix.
const kLinkEventOverheadBytes = 1024;

/// The parts of a relay's NIP-11 document the link sync uses.
class RelayInfo {
  final String? name;
  final String? software;
  final List<int> supportedNips;
  final int? maxMessageLength;
  final int? maxContentLength;
  final int? maxSubscriptions;
  final bool authRequired;
  final bool paymentRequired;
  final bool restrictedWrites;

  /// The relay's terms (`terms_of_service`, an http(s) URL) — linked in the
  /// relay settings (G52 step 9, §9.4).
  final String? termsOfService;

  const RelayInfo({
    this.name,
    this.software,
    this.supportedNips = const [],
    this.maxMessageLength,
    this.maxContentLength,
    this.maxSubscriptions,
    this.authRequired = false,
    this.paymentRequired = false,
    this.restrictedWrites = false,
    this.termsOfService,
  });

  /// Parses a NIP-11 document; fields with a wrong type read as absent.
  factory RelayInfo.fromJson(Map<String, dynamic> json) {
    final lim = json['limitation'];
    final limitation = lim is Map ? lim : const {};
    int? posInt(Object? v) => v is int && v > 0 ? v : null;
    String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
    final nips = json['supported_nips'];
    return RelayInfo(
      name: str(json['name']),
      software: str(json['software']),
      supportedNips: [
        if (nips is List)
          for (final n in nips)
            if (n is int) n,
      ],
      maxMessageLength: posInt(limitation['max_message_length']),
      maxContentLength: posInt(limitation['max_content_length']),
      maxSubscriptions: posInt(limitation['max_subscriptions']),
      authRequired: limitation['auth_required'] == true,
      paymentRequired: limitation['payment_required'] == true,
      restrictedWrites: limitation['restricted_writes'] == true,
      termsOfService: _httpUrl(json['terms_of_service']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': ?name,
    'terms_of_service': ?termsOfService,
    'software': ?software,
    'supported_nips': supportedNips,
    'limitation': {
      'max_message_length': ?maxMessageLength,
      'max_content_length': ?maxContentLength,
      'max_subscriptions': ?maxSubscriptions,
      'auth_required': authRequired,
      'payment_required': paymentRequired,
      'restricted_writes': restrictedWrites,
    },
  };

  bool supportsNip(int nip) => supportedNips.contains(nip);
}

/// [v] when it is an absolute http(s) URL, else null (a relay's document
/// is untrusted — never link anything else).
String? _httpUrl(Object? v) {
  if (v is! String) return null;
  final uri = Uri.tryParse(v.trim());
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  return uri.toString();
}

/// The `content` budget (chars) for events to a relay described by [info]
/// (null = unknown → [kLinkContentBudget]): never more than
/// [kLinkContentBudget] (the 65 536-byte event cap no relay advertises),
/// lowered by an advertised `max_content_length`, or `max_message_length`
/// minus [kLinkEventOverheadBytes].
int relayContentBudget(RelayInfo? info) {
  var budget = kLinkContentBudget;
  final content = info?.maxContentLength;
  if (content != null && content < budget) budget = content;
  final frame = info?.maxMessageLength;
  if (frame != null && frame - kLinkEventOverheadBytes < budget) {
    budget = frame - kLinkEventOverheadBytes;
  }
  return budget < 0 ? 0 : budget;
}

/// Why a relay can't serve link groups (custom relays, G52 step 9).
enum RelayInfoProblem {
  /// `auth_required` / `payment_required`: "this relay needs an account".
  needsAccount,

  /// `supported_nips` is given and lacks 40 (expiration).
  noExpiration,
}

/// The first reason [info] rules a relay out, or null when it looks usable.
/// A relay that lists no NIPs at all isn't refused for it (many don't).
RelayInfoProblem? relayInfoProblem(RelayInfo info) {
  if (info.authRequired || info.paymentRequired) {
    return RelayInfoProblem.needsAccount;
  }
  if (info.supportedNips.isNotEmpty && !info.supportsNip(40)) {
    return RelayInfoProblem.noExpiration;
  }
  return null;
}

/// The HTTP URL of a relay's NIP-11 document: `wss://` → `https://`,
/// `ws://` → `http://`; null for anything else.
Uri? relayInfoUrl(String relay) {
  final uri = Uri.tryParse(relay);
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = switch (uri.scheme) {
    'wss' => 'https',
    'ws' => 'http',
    _ => null,
  };
  return scheme == null ? null : uri.replace(scheme: scheme);
}

/// Fetches NIP-11 documents (port; tests use a fake).
abstract interface class RelayInfoFetcher {
  /// The document of [relay], or throws (offline, not NIP-11, …).
  Future<RelayInfo> fetch(String relay);
}

/// The real fetcher: one HTTP GET with `Accept: application/nostr+json`.
class HttpRelayInfoFetcher implements RelayInfoFetcher {
  final http.Client Function() _client;
  final Duration timeout;

  HttpRelayInfoFetcher({
    http.Client Function()? client,
    this.timeout = kRelayInfoTimeout,
  }) : _client = client ?? http.Client.new;

  @override
  Future<RelayInfo> fetch(String relay) async {
    final url = relayInfoUrl(relay);
    if (url == null) throw ArgumentError.value(relay, 'relay', 'not ws(s)://');
    final client = _client();
    try {
      final res = await client
          .get(url, headers: const {'Accept': 'application/nostr+json'})
          .timeout(timeout);
      if (res.statusCode != 200) {
        throw StateError('NIP-11: HTTP ${res.statusCode}');
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! Map<String, dynamic>) {
        throw const FormatException('NIP-11: not a JSON object');
      }
      return RelayInfo.fromJson(json);
    } finally {
      client.close();
    }
  }
}
