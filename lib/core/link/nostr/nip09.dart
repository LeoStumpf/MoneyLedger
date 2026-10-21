/// G52 step 5: NIP-09 deletion requests for our own addressable events
/// (design doc `docs/design/no-login-sharing.md` §7.3 — leaving a link group
/// unpublishes this device's snapshot).
///
/// ```json
/// { "kind": 5, "pubkey": "<per-group device key>", "created_at": …,
///   "tags": [ ["a", "31847:<pubkey>:<d>"], …, ["k", "31847"] ],
///   "content": "" }
/// ```
///
/// An `a` tag asks the relay to delete every version of that address up to
/// the request's `created_at` (NIP-09), so it must not be older than the
/// events it deletes — the caller passes the channel's next monotonic
/// `created_at` (§4.5). Deletion is a **request**: relays MAY ignore it,
/// which is why the caller first overwrites each part with a header-only
/// snapshot that expires after a day (§7.3). Pure Dart.
library;

import 'nostr_event.dart';

/// NIP-09 deletion request kind.
const kNostrDeletionKind = 5;

/// The `a` tag value of the addressable event of [kind] / [pubkey] / [d].
String nostrAddress(int kind, String pubkey, String d) => '$kind:$pubkey:$d';

/// Builds and signs a deletion request for the addresses (`kind`, our
/// pubkey, each of [dTags]) of [privateKey]'s events.
NostrEvent buildNostrDeletion({
  required String privateKey,
  required int kind,
  required Iterable<String> dTags,
  required int createdAt,
  List<int>? aux,
}) {
  final pubkey = nostrPublicKey(privateKey);
  return signNostrEvent(
    privateKey: privateKey,
    kind: kNostrDeletionKind,
    tags: [
      for (final d in dTags) ['a', nostrAddress(kind, pubkey, d)],
      ['k', '$kind'],
    ],
    content: '',
    createdAt: createdAt,
    aux: aux,
  );
}
