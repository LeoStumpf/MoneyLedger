/// G52: plain models of the device-local link-group bookkeeping
/// (`link_channels` / `link_peers`, `docs/design/no-login-sharing.md` §7.1).
library;

/// This device's link channel of one group. Holds two **secrets** — the
/// link [secret] and this device's Nostr private key [nostrPriv] — so
/// [toString] leaves them out: never log them.
class LinkChannelModel {
  final String groupId;

  /// Key epoch of [secret].
  final int epoch;

  /// The link secret, base64url without padding (the link's `k`).
  final String secret;

  /// Who this device is in the group; null until picked (§6.1).
  final String? myParticipantId;

  /// This device's per-group secp256k1 Nostr private key (64 hex chars).
  final String nostrPriv;

  /// Digest of the snapshot last published (null = never published).
  final String? lastPublishedHash;

  /// When we last published (ms epoch; 0 = never).
  final int lastPublishedAt;

  /// Nostr `created_at` (seconds) of our latest event (0 = none).
  final int lastCreatedAt;

  /// Parts of the last published snapshot (1, 2, 4 or 8).
  final int parts;

  /// When this device opened / joined the channel (ms epoch).
  final int openedAt;

  const LinkChannelModel({
    required this.groupId,
    required this.epoch,
    required this.secret,
    required this.nostrPriv,
    required this.openedAt,
    this.myParticipantId,
    this.lastPublishedHash,
    this.lastPublishedAt = 0,
    this.lastCreatedAt = 0,
    this.parts = 1,
  });

  @override
  String toString() =>
      'LinkChannelModel(group: $groupId, epoch: $epoch, '
      'me: $myParticipantId, parts: $parts, '
      'lastPublishedAt: $lastPublishedAt, lastCreatedAt: $lastCreatedAt)';
}

/// Another publisher seen on a link group's channel.
class LinkPeerModel {
  final String groupId;

  /// The publisher's Nostr pubkey (x-only hex).
  final String pubkey;

  /// The participant its latest event names as `me` (hint only).
  final String? me;

  /// Latest processed event id per part index.
  final Map<int, String> eventIds;

  /// Newest Nostr `created_at` (seconds) seen from it.
  final int lastCreatedAt;

  /// When this device last received an event of it (ms epoch).
  final int lastSeenAt;

  /// Digest of its snapshot as last merged (null = unknown).
  final String? snapshotDigest;

  const LinkPeerModel({
    required this.groupId,
    required this.pubkey,
    this.me,
    this.eventIds = const {},
    this.lastCreatedAt = 0,
    this.lastSeenAt = 0,
    this.snapshotDigest,
  });
}
