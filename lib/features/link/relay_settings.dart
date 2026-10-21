/// G52 step 9: the pure part of the relay settings (design doc
/// `docs/design/no-login-sharing.md` §4.6, §9.2, §9.4) — what the user typed
/// as a relay, each relay's status line and its terms link. No Flutter, no
/// DB; the page is `relay_settings_page.dart`.
library;

import '../../core/link/link_sync_engine.dart' show LinkRelayView;
import '../../core/link/nostr/nip11.dart';
import '../../core/link/nostr/nostr_relay_pool.dart' show kDefaultLinkRelays;

/// The default relays' terms (§9.4: their NIP-11 `terms_of_service`), shown
/// before a NIP-11 document was ever fetched (G43: the settings page itself
/// contacts nobody).
const kDefaultRelayTerms = {
  'wss://nos.lol': 'https://wikifreedia.xyz/nos.lol/',
  'wss://nostr.mom': 'https://wikifreedia.xyz/nostr.mom/',
};

/// Whether [relays] is exactly the default list (the disclosure then says
/// "one operator", §9.2).
bool isDefaultRelayList(List<String> relays) =>
    relays.length == kDefaultLinkRelays.length &&
    relays.toSet().containsAll(kDefaultLinkRelays);

/// The host name shown for [relay] (`wss://nos.lol` → `nos.lol`; a port or
/// path is kept so two relays on one host stay apart).
String relayLabel(String relay) {
  final uri = Uri.tryParse(relay);
  if (uri == null || uri.host.isEmpty) return relay;
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path == '/' ? '' : uri.path;
  return '${uri.host}$port$path';
}

/// Why a typed relay address can't be added.
enum RelayInputProblem {
  /// Not a relay address at all.
  invalid,

  /// `ws://` (unencrypted connection) — only `wss://` is accepted.
  notSecure,

  /// Already in the list.
  duplicate,
}

final _hostChars = RegExp(r'^[A-Za-z0-9.-]+$');

/// [input] as a relay URL (`nos.lol` → `wss://nos.lol`), or the reason it
/// isn't one ([existing] = the current list, for duplicates).
({String? url, RelayInputProblem? problem}) parseRelayInput(
  String input,
  List<String> existing,
) {
  var text = input.trim();
  if (text.isEmpty) return (url: null, problem: RelayInputProblem.invalid);
  if (!text.contains('://')) text = 'wss://$text';
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (!uri.host.contains('.') && uri.host != 'localhost') ||
      !_hostChars.hasMatch(uri.host)) {
    return (url: null, problem: RelayInputProblem.invalid);
  }
  if (uri.scheme == 'ws') {
    return (url: null, problem: RelayInputProblem.notSecure);
  }
  if (uri.scheme != 'wss') {
    return (url: null, problem: RelayInputProblem.invalid);
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path == '/' ? '' : uri.path;
  final url = 'wss://${uri.host.toLowerCase()}$port$path';
  if (existing.any((r) => relayLabel(r) == relayLabel(url))) {
    return (url: null, problem: RelayInputProblem.duplicate);
  }
  return (url: url, problem: null);
}

/// What a relay row says.
enum RelayStatusKind {
  /// It refused our events this run (`blocked:` / `restricted:` / …) —
  /// skipped until the next app start.
  rejects,

  /// It asked us to slow down (`rate-limited:`); used again at [at].
  rateLimited,

  /// Its NIP-11 document rules it out (needs an account / no NIP-40).
  unsuitable,

  /// Its last answer was a refusal (an earlier run).
  lastRefused,

  /// It accepted our last update at [at].
  ok,

  /// Nothing sent to it yet.
  unused,
}

/// A relay row's status (pure; [RelayStatusKind]).
class RelayStatus {
  final RelayStatusKind kind;

  /// When (ms epoch): accepted / used again.
  final int? at;

  /// The relay's own message (rejections) — shown as is, it's the relay's
  /// text, not ours.
  final String? message;

  /// [RelayStatusKind.unsuitable]: why.
  final RelayInfoProblem? problem;

  const RelayStatus(this.kind, {this.at, this.message, this.problem});

  /// Whether the row is shown as a problem (error colour).
  bool get isProblem =>
      kind == RelayStatusKind.rejects ||
      kind == RelayStatusKind.unsuitable ||
      kind == RelayStatusKind.lastRefused;
}

/// The status line of [relay].
RelayStatus relayStatusOf(LinkRelayView relay) {
  if (relay.rejectingMessage != null) {
    return RelayStatus(
      RelayStatusKind.rejects,
      message: relay.rejectingMessage,
    );
  }
  if (relay.rateLimitedUntil != null) {
    return RelayStatus(RelayStatusKind.rateLimited, at: relay.rateLimitedUntil);
  }
  final s = relay.state;
  final info = s.info;
  final problem = info == null ? null : relayInfoProblem(info);
  if (problem != null) {
    return RelayStatus(RelayStatusKind.unsuitable, problem: problem);
  }
  final ok = s.lastOkAt;
  final refused = s.lastRejectionAt;
  if (refused != null &&
      (ok == null || refused > ok) &&
      s.lastRejection == 'rejects') {
    return RelayStatus(
      RelayStatusKind.lastRefused,
      at: refused,
      message: s.lastRejectionMessage,
    );
  }
  if (ok != null) return RelayStatus(RelayStatusKind.ok, at: ok);
  return const RelayStatus(RelayStatusKind.unused);
}

/// The terms link of [relay]: its NIP-11 `terms_of_service`, else the
/// known one of a default relay, else null.
String? relayTermsUrl(LinkRelayView relay) =>
    relay.state.info?.termsOfService ?? kDefaultRelayTerms[relay.url];
