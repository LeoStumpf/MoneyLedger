/// G52 step 5: how the link sync engine treats each relay's answers to its
/// publishes (design doc `docs/design/no-login-sharing.md` §4.4), and the
/// per-relay state it keeps for the settings page (§7.1, G52 step 9).
///
/// [LinkRelayPolicy] (pure, clock injected):
/// - `OK true` / `duplicate:` → success; the rate-limit streak resets;
/// - `replaced:` → not a failure (the caller bumps `created_at` and
///   republishes once, §4.5);
/// - `rate-limited:` → the relay is skipped for 1 min, doubling per
///   further rate limit up to 1 h;
/// - `blocked:` / `restricted:` / `invalid:` / `pow:` / `auth-required:` →
///   the relay "rejects our events": skipped until the next app start (=
///   this policy object's lifetime). `invalid: event too large: <n>` is the
///   exception — a sharding bug (§5.4), never a reason to block a relay;
/// - timeouts / offline / `error:` → transient (the pool reconnects; the
///   engine retries the publish later).
///
/// [LinkRelayState] is what survives a restart, stored per relay in the
/// ledger DB's `AppSettings` (`link_relay_state:<url>`): the cached NIP-11
/// document, the last success and the last rejection. Pure Dart.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'nostr/nip11.dart';
import 'nostr/nostr_frames.dart';
import 'nostr/nostr_relay_pool.dart' show NostrPublishResult;

/// First back-off after `rate-limited:` (§4.4), doubling per repeat …
const kRelayRateLimitMin = Duration(minutes: 1);

/// … up to this.
const kRelayRateLimitMax = Duration(hours: 1);

/// What one relay answer means for that relay.
enum RelayAnswer {
  /// Accepted (incl. `duplicate:`).
  ok,

  /// `replaced:` — republish with a newer `created_at` (§4.5).
  replaced,

  /// `rate-limited:` — backed off.
  rateLimited,

  /// The relay refuses our events — skipped until the next app start.
  rejects,

  /// `invalid: event too large` / not sent (too large): a budget bug.
  tooLarge,

  /// Timeout, offline, `error:` — try again later.
  transient,
}

/// Classifies one [NostrPublishResult].
RelayAnswer classifyRelayAnswer(NostrPublishResult r) => switch (r.status) {
  NostrPublishStatus.accepted || NostrPublishStatus.duplicate => RelayAnswer.ok,
  NostrPublishStatus.replaced => RelayAnswer.replaced,
  NostrPublishStatus.rateLimited => RelayAnswer.rateLimited,
  NostrPublishStatus.tooLarge => RelayAnswer.tooLarge,
  NostrPublishStatus.invalid when r.message.contains('too large') =>
    RelayAnswer.tooLarge,
  NostrPublishStatus.invalid ||
  NostrPublishStatus.blocked ||
  NostrPublishStatus.restricted ||
  NostrPublishStatus.pow ||
  NostrPublishStatus.authRequired => RelayAnswer.rejects,
  NostrPublishStatus.error ||
  NostrPublishStatus.timeout ||
  NostrPublishStatus.offline => RelayAnswer.transient,
};

/// In-memory per-relay back-off / block state (see the library doc).
class LinkRelayPolicy {
  LinkRelayPolicy({
    required this._clock,
    this.rateLimitMin = kRelayRateLimitMin,
    this.rateLimitMax = kRelayRateLimitMax,
  });

  final int Function() _clock;
  final Duration rateLimitMin;
  final Duration rateLimitMax;

  final Map<String, int> _rateLimitedUntil = {};
  final Map<String, int> _rateLimitStreak = {};
  final Map<String, String> _rejecting = {};

  /// Relays that refused our events this run, with their message.
  Map<String, String> get rejecting => Map.unmodifiable(_rejecting);

  bool rejects(String relay) => _rejecting.containsKey(relay);

  /// Until when (ms epoch) [relay] is backed off; null when it isn't.
  int? rateLimitedUntil(String relay) {
    final until = _rateLimitedUntil[relay];
    return until != null && until > _clock() ? until : null;
  }

  /// Whether a publish may go to [relay] now.
  bool canPublish(String relay) =>
      !rejects(relay) && rateLimitedUntil(relay) == null;

  /// How long until the first of [relays] that isn't blocked becomes
  /// available again; [Duration.zero] when one is available now, null when
  /// every one rejects our events.
  Duration? nextAvailableIn(Iterable<String> relays) {
    final now = _clock();
    int? best;
    for (final r in relays) {
      if (rejects(r)) continue;
      final until = rateLimitedUntil(r) ?? now;
      if (best == null || until < best) best = until;
    }
    return best == null ? null : Duration(milliseconds: best - now);
  }

  /// Applies [result] and returns what it means.
  RelayAnswer onResult(NostrPublishResult result) {
    final answer = classifyRelayAnswer(result);
    final relay = result.relay;
    switch (answer) {
      case RelayAnswer.ok:
        _rateLimitStreak.remove(relay);
        _rateLimitedUntil.remove(relay);
      case RelayAnswer.rateLimited:
        final streak = (_rateLimitStreak[relay] ?? 0) + 1;
        _rateLimitStreak[relay] = streak;
        final ms = math.min(
          rateLimitMin.inMilliseconds * math.pow(2, math.min(streak - 1, 20)),
          rateLimitMax.inMilliseconds.toDouble(),
        );
        _rateLimitedUntil[relay] = _clock() + ms.round();
      case RelayAnswer.rejects:
        _rejecting[relay] = result.message;
      case RelayAnswer.replaced:
      case RelayAnswer.tooLarge:
      case RelayAnswer.transient:
        break;
    }
    return answer;
  }
}

/// A relay's persisted state (`AppSettings` `link_relay_state:<url>`).
class LinkRelayState {
  /// Cached NIP-11 document and when it was fetched (ms epoch).
  final RelayInfo? info;
  final int? infoFetchedAt;

  /// Last `OK true` (ms epoch).
  final int? lastOkAt;

  /// Last rejection (ms epoch), its [RelayAnswer] name and message.
  final int? lastRejectionAt;
  final String? lastRejection;
  final String? lastRejectionMessage;

  const LinkRelayState({
    this.info,
    this.infoFetchedAt,
    this.lastOkAt,
    this.lastRejectionAt,
    this.lastRejection,
    this.lastRejectionMessage,
  });

  /// Whether the cached NIP-11 document is missing or older than
  /// [kRelayInfoMaxAge] at [now] (ms epoch).
  bool infoStale(int now) =>
      infoFetchedAt == null ||
      now - infoFetchedAt! > kRelayInfoMaxAge.inMilliseconds;

  LinkRelayState copyWith({
    RelayInfo? info,
    int? infoFetchedAt,
    int? lastOkAt,
    int? lastRejectionAt,
    String? lastRejection,
    String? lastRejectionMessage,
  }) => LinkRelayState(
    info: info ?? this.info,
    infoFetchedAt: infoFetchedAt ?? this.infoFetchedAt,
    lastOkAt: lastOkAt ?? this.lastOkAt,
    lastRejectionAt: lastRejectionAt ?? this.lastRejectionAt,
    lastRejection: lastRejection ?? this.lastRejection,
    lastRejectionMessage: lastRejectionMessage ?? this.lastRejectionMessage,
  );

  String encode() => jsonEncode({
    if (info != null) 'nip11': info!.toJson(),
    'nip11_at': ?infoFetchedAt,
    'last_ok_at': ?lastOkAt,
    'last_rejection_at': ?lastRejectionAt,
    'last_rejection': ?lastRejection,
    'last_rejection_message': ?lastRejectionMessage,
  });

  /// Parses [encode]'s output; anything malformed reads as an empty state.
  static LinkRelayState decode(String? raw) {
    if (raw == null) return const LinkRelayState();
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return const LinkRelayState();
      int? i(String k) => j[k] is int ? j[k] as int : null;
      String? s(String k) => j[k] is String ? j[k] as String : null;
      final info = j['nip11'];
      return LinkRelayState(
        info: info is Map<String, dynamic> ? RelayInfo.fromJson(info) : null,
        infoFetchedAt: i('nip11_at'),
        lastOkAt: i('last_ok_at'),
        lastRejectionAt: i('last_rejection_at'),
        lastRejection: s('last_rejection'),
        lastRejectionMessage: s('last_rejection_message'),
      );
    } on FormatException {
      return const LinkRelayState();
    }
  }
}

/// Parses the `link_relays` setting (a JSON list of `wss://` URLs); null /
/// malformed / empty → the defaults ([defaults]).
List<String> parseLinkRelays(String? raw, List<String> defaults) {
  if (raw == null) return defaults;
  try {
    final j = jsonDecode(raw);
    if (j is! List) return defaults;
    final relays = <String>[
      for (final r in j)
        if (r is String && relayInfoUrl(r) != null) r,
    ];
    return relays.isEmpty ? defaults : relays.toSet().toList();
  } on FormatException {
    return defaults;
  }
}
