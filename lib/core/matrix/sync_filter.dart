/// G45: the minimal Matrix footprint — what `/sync` asks the homeserver for.
///
/// Matrix-free on purpose (plain JSON + strings), so tests can pin it without
/// importing `package:matrix`; `buildMatrixClient` converts it into the SDK's
/// `Filter` / `PresenceType`.
///
/// The app is roomless: it only needs the **to-device** section (encrypted
/// ledger messages, SAS verification, Olm key traffic), `device_lists` and the
/// one-time-key counts (E2EE key management). None of these is filterable in
/// the Matrix spec, so they arrive whatever the filter says. Everything else
/// the SDK's default filter would pull in — the account's rooms (incl. invites
/// and rooms of the same account used in Element), presence and global account
/// data (push rules, ignored users, …) — is excluded, so it is neither
/// transferred nor cached in the SDK's local store.
library;

import 'dart:convert';

/// The `/sync` filter (spec "Filter" object). `rooms: []` excludes every room
/// (joined, invited, left); the room sub-filters with `types: []` are a second
/// line of defence for a server that ignored the empty room list. `types: []`
/// on presence / account data matches no event type.
Map<String, Object?> minimalSyncFilterJson() => {
  'account_data': {'types': <String>[]},
  'presence': {'types': <String>[]},
  'room': {
    'rooms': <String>[],
    'include_leave': false,
    'account_data': {'types': <String>[]},
    'ephemeral': {'types': <String>[]},
    'state': {'types': <String>[]},
    'timeline': {'types': <String>[]},
  },
};

/// `/sync`'s `set_presence`: `offline` = polling never marks the user online
/// (omitted, the server marks the user online on every sync).
const String kSyncPresence = 'offline';

/// The SDK defines the sync filter on the server once and caches its id in
/// its own store (`sync_filter_id`) — it never re-checks it. Installs from
/// before G45 therefore hold the id of the SDK's default filter (rooms,
/// presence, account data). We record which filter id is *ours* in a
/// **device-local** entry of the SDK store (an account-data box entry that is
/// never uploaded; the filter excludes server account data, so nothing
/// overwrites it; it is wiped with the session on logout) and make the SDK
/// define the minimal filter again whenever the stored id isn't the one
/// recorded for the current filter.
const String kSyncFilterMarkerType =
    'io.github.leostumpf.moneyledger.sync_filter';

/// Canonical text of the current filter (stored in the marker, so a future
/// change of [minimalSyncFilterJson] defines the filter again).
String minimalSyncFilterText() => jsonEncode(minimalSyncFilterJson());

/// The marker content recorded after the server assigned [filterId] to the
/// current filter.
Map<String, Object?> syncFilterMarker(String filterId) => {
  'filter_id': filterId,
  'filter': minimalSyncFilterText(),
};

/// The filter id a stored marker vouches for — null when there is no marker,
/// it is malformed, or it was recorded for another filter.
String? markedSyncFilterId(Map<String, Object?>? marker) {
  if (marker == null) return null;
  final id = marker['filter_id'];
  if (id is! String || id.isEmpty) return null;
  if (marker['filter'] != minimalSyncFilterText()) return null;
  return id;
}

/// The sync filter id the client should use: the SDK's stored id only when
/// it is the one recorded as ours; null makes the SDK define (and store) the
/// minimal filter before its next `/sync`.
String? effectiveSyncFilterId({
  required String? stored,
  required String? marked,
}) => stored != null && stored == marked ? stored : null;

/// Whether the SDK store still holds data synced with **another** filter (a
/// pre-G45 install: the default filter's rooms, room members, presence and
/// account data — e.g. of rooms the same account uses in Element). Those
/// would never be updated again, and the SDK would keep querying the device
/// keys of everyone in those (stale) encrypted rooms, so `buildMatrixClient`
/// clears the SDK's cache once before the client loads it (the session, Olm
/// sessions and device keys are kept; the next `/sync` starts afresh with the
/// minimal filter — undelivered to-device messages are still delivered).
bool syncCacheFromOtherFilter({
  required String? stored,
  required String? marked,
}) => stored != null && stored != marked;
