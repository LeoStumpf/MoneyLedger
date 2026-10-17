/// G52 step 2: NIP-01 frames — filters, client → relay `EVENT` / `REQ` /
/// `CLOSE`, relay → client `EVENT` / `OK` / `EOSE` / `CLOSED` / `NOTICE`
/// (design doc `docs/design/no-login-sharing.md` §4.3, §4.4).
///
/// Parsing is tolerant: [parseRelayMessage] returns null for anything it
/// doesn't understand (malformed JSON, unknown types such as `AUTH` /
/// `COUNT`, wrong field types, a structurally invalid event) and never
/// throws — the pool logs and ignores it.
///
/// Pure Dart, no Flutter, no I/O.
library;

import 'dart:convert';

import 'nostr_event.dart';

/// A NIP-01 subscription filter. Lists are "any of"; all set conditions must
/// hold. [tags] maps a single-letter tag name (without `#`) to its values,
/// e.g. `{'d': [topic]}` → `"#d": [topic]`.
class NostrFilter {
  final List<String>? ids;
  final List<String>? authors;
  final List<int>? kinds;
  final Map<String, List<String>> tags;
  final int? since;
  final int? until;
  final int? limit;

  const NostrFilter({
    this.ids,
    this.authors,
    this.kinds,
    this.tags = const {},
    this.since,
    this.until,
    this.limit,
  });

  /// The same filter with another [since] (live re-subscribe, §4.3).
  NostrFilter withSince(int? since) => NostrFilter(
    ids: ids,
    authors: authors,
    kinds: kinds,
    tags: tags,
    since: since,
    until: until,
    limit: limit,
  );

  Map<String, dynamic> toJson() => {
    if (ids != null) 'ids': ids,
    if (authors != null) 'authors': authors,
    if (kinds != null) 'kinds': kinds,
    for (final e in tags.entries) '#${e.key}': e.value,
    if (since != null) 'since': since,
    if (until != null) 'until': until,
    if (limit != null) 'limit': limit,
  };

  /// Parses a filter object; null when it is malformed. (Used by the fake
  /// relay; unknown keys are ignored, as relays do.)
  static NostrFilter? tryParse(Object? json) {
    if (json is! Map) return null;
    List<T>? list<T>(Object? v) {
      if (v == null) return null;
      if (v is! List || v.any((x) => x is! T)) throw const FormatException();
      return v.cast<T>().toList();
    }

    int? integer(Object? v) {
      if (v == null) return null;
      if (v is! int) throw const FormatException();
      return v;
    }

    try {
      final tags = <String, List<String>>{};
      for (final e in json.entries) {
        final k = e.key;
        if (k is String && k.length == 2 && k.startsWith('#')) {
          tags[k.substring(1)] = list<String>(e.value)!;
        }
      }
      return NostrFilter(
        ids: list<String>(json['ids']),
        authors: list<String>(json['authors']),
        kinds: list<int>(json['kinds']),
        tags: tags,
        since: integer(json['since']),
        until: integer(json['until']),
        limit: integer(json['limit']),
      );
    } on FormatException {
      return null;
    }
  }

  /// Whether [event] matches (ignores [limit], which only bounds a relay's
  /// stored-events answer).
  bool matches(NostrEvent event) {
    if (ids != null && !ids!.contains(event.id)) return false;
    if (authors != null && !authors!.contains(event.pubkey)) return false;
    if (kinds != null && !kinds!.contains(event.kind)) return false;
    if (since != null && event.createdAt < since!) return false;
    if (until != null && event.createdAt > until!) return false;
    for (final e in tags.entries) {
      final hit = event.tags.any(
        (t) => t.length > 1 && t[0] == e.key && e.value.contains(t[1]),
      );
      if (!hit) return false;
    }
    return true;
  }

  @override
  String toString() => 'NostrFilter(${jsonEncode(toJson())})';
}

/// Whether [event] matches any of [filters].
bool nostrFiltersMatch(List<NostrFilter> filters, NostrEvent event) =>
    filters.any((f) => f.matches(event));

// ---------------------------------------------------------- client → relay

/// `["EVENT", <event>]`.
String encodeEventFrame(NostrEvent event) =>
    jsonEncode(['EVENT', event.toJson()]);

/// `["REQ", <subId>, <filter>…]`.
String encodeReqFrame(String subscriptionId, List<NostrFilter> filters) =>
    jsonEncode(['REQ', subscriptionId, for (final f in filters) f.toJson()]);

/// `["CLOSE", <subId>]`.
String encodeCloseFrame(String subscriptionId) =>
    jsonEncode(['CLOSE', subscriptionId]);

// ---------------------------------------------------------- relay → client

/// A parsed relay → client message.
sealed class RelayMessage {
  const RelayMessage();
}

/// `["EVENT", <subId>, <event>]` (event structurally valid, not verified).
class RelayEventMessage extends RelayMessage {
  final String subscriptionId;
  final NostrEvent event;
  const RelayEventMessage(this.subscriptionId, this.event);
}

/// `["OK", <event id>, <true|false>, <message>]`.
class RelayOkMessage extends RelayMessage {
  final String eventId;
  final bool accepted;
  final String message;
  const RelayOkMessage(this.eventId, this.accepted, this.message);
}

/// `["EOSE", <subId>]`: stored events done, live events follow.
class RelayEoseMessage extends RelayMessage {
  final String subscriptionId;
  const RelayEoseMessage(this.subscriptionId);
}

/// `["CLOSED", <subId>, <message>]`: the relay ended the subscription.
class RelayClosedMessage extends RelayMessage {
  final String subscriptionId;
  final String message;
  const RelayClosedMessage(this.subscriptionId, this.message);
}

/// `["NOTICE", <message>]`.
class RelayNoticeMessage extends RelayMessage {
  final String message;
  const RelayNoticeMessage(this.message);
}

/// Parses one relay → client frame; null for anything malformed or unknown.
RelayMessage? parseRelayMessage(String frame) {
  final Object? json;
  try {
    json = jsonDecode(frame);
  } catch (_) {
    return null;
  }
  if (json is! List || json.isEmpty) return null;
  final List<dynamic> f = json;
  final type = f[0];
  String? str(int i) => f.length > i && f[i] is String ? f[i] as String : null;
  switch (type) {
    case 'EVENT':
      final sub = str(1);
      final event = f.length > 2 ? NostrEvent.tryParse(f[2]) : null;
      if (sub == null || event == null) return null;
      return RelayEventMessage(sub, event);
    case 'OK':
      final id = str(1);
      if (id == null || f.length < 3 || f[2] is! bool) return null;
      return RelayOkMessage(id, f[2] as bool, str(3) ?? '');
    case 'EOSE':
      final sub = str(1);
      return sub == null ? null : RelayEoseMessage(sub);
    case 'CLOSED':
      final sub = str(1);
      return sub == null ? null : RelayClosedMessage(sub, str(2) ?? '');
    case 'NOTICE':
      return RelayNoticeMessage(str(1) ?? '');
  }
  return null;
}

// ------------------------------------------------------------- OK messages

/// The outcome of publishing one event to one relay (§4.4).
enum NostrPublishStatus {
  /// `OK true`.
  accepted,

  /// `OK true|false "duplicate: …"`: the relay already holds this event.
  duplicate,

  /// `OK false "replaced: …"` (strfry, G51 E2): the relay holds a newer —
  /// or same-second lower-id — event for this address. Not a relay
  /// failure: our `created_at` wasn't ahead (§4.5) → bump past the relay's
  /// event and republish once.
  replaced,

  /// `rate-limited:` — back off this relay.
  rateLimited,

  /// `invalid:` (incl. `invalid: event too large: <n>` — a budget bug).
  invalid,

  /// `blocked:`.
  blocked,

  /// `restricted:`.
  restricted,

  /// `pow:`.
  pow,

  /// `auth-required:` (NIP-42).
  authRequired,

  /// `error:`, or `OK false` with no / an unknown prefix.
  error,

  /// Not sent: the event JSON exceeds the size cap ([kNostrMaxEventBytes]).
  tooLarge,

  /// No `OK` within the timeout.
  timeout,

  /// Couldn't connect, or the connection dropped before the `OK`.
  offline,
}

/// Whether [status] means the relay holds this event or a newer one for its
/// address — accepted-equivalent, not a relay failure (§4.4).
bool isAcceptedEquivalent(NostrPublishStatus status) => switch (status) {
  NostrPublishStatus.accepted ||
  NostrPublishStatus.duplicate ||
  NostrPublishStatus.replaced => true,
  _ => false,
};

/// Classifies an `OK` frame by its NIP-01 machine-readable prefix.
NostrPublishStatus classifyOk(bool accepted, String message) {
  final colon = message.indexOf(':');
  final prefix = colon < 0 ? '' : message.substring(0, colon).trim();
  if (prefix == 'duplicate') return NostrPublishStatus.duplicate;
  if (accepted) return NostrPublishStatus.accepted;
  return switch (prefix) {
    'replaced' => NostrPublishStatus.replaced,
    'rate-limited' => NostrPublishStatus.rateLimited,
    'invalid' => NostrPublishStatus.invalid,
    'blocked' => NostrPublishStatus.blocked,
    'restricted' => NostrPublishStatus.restricted,
    'pow' => NostrPublishStatus.pow,
    'auth-required' => NostrPublishStatus.authRequired,
    _ => NostrPublishStatus.error,
  };
}
