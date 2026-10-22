/// G52 step 12 follow-up (design doc `docs/design/no-login-sharing.md`
/// §7.3, Leo 2026-10-22): what this device learned from a **"this link was
/// replaced" marker** on its link's topic — someone reset the invite link
/// (or switched to a new one) and left this topic. Device-local
/// (`AppSettings` `link_replaced:<group>`), never synced; cleared when this
/// device's channel is replaced or dropped.
///
/// A hint only: anyone holding the link can post a marker, so it changes
/// nothing but the group page's "ask for the new link" banner.
library;

import 'dart:convert';

import '../../models/link_model.dart';

class LinkReplacedNotice {
  /// The epoch of this device's channel the marker arrived on (a notice of
  /// an earlier channel never shows).
  final int epoch;

  /// The newest marker event seen (Nostr event id) and its `created_at`
  /// (seconds).
  final String eventId;
  final int createdAt;

  /// The publisher's participant (the header's `me`), null if unknown.
  final String? by;

  /// The user closed the banner — stays closed for this channel.
  final bool dismissed;

  const LinkReplacedNotice({
    required this.epoch,
    required this.eventId,
    required this.createdAt,
    this.by,
    this.dismissed = false,
  });

  String encode() => jsonEncode({
    'epoch': epoch,
    'event': eventId,
    'created_at': createdAt,
    'by': ?by,
    if (dismissed) 'dismissed': true,
  });

  /// Null for anything unreadable (a corrupt entry simply shows nothing).
  static LinkReplacedNotice? decode(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final epoch = j['epoch'];
      final event = j['event'];
      final at = j['created_at'];
      if (epoch is! int || event is! String || at is! int) return null;
      final by = j['by'];
      return LinkReplacedNotice(
        epoch: epoch,
        eventId: event,
        createdAt: at,
        by: by is String && by.isNotEmpty ? by : null,
        dismissed: j['dismissed'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  LinkReplacedNotice get asDismissed => LinkReplacedNotice(
    epoch: epoch,
    eventId: eventId,
    createdAt: createdAt,
    by: by,
    dismissed: true,
  );
}

/// Pure: the notice to store after a marker ([eventId], [createdAt], [by])
/// arrived on the channel with [epoch] — null = keep [existing] as it is
/// (the same or an older marker, or the banner was dismissed for this
/// channel).
LinkReplacedNotice? nextLinkReplacedNotice(
  LinkReplacedNotice? existing, {
  required int epoch,
  required String eventId,
  required int createdAt,
  String? by,
}) {
  final fresh = LinkReplacedNotice(
    epoch: epoch,
    eventId: eventId,
    createdAt: createdAt,
    by: by,
  );
  if (existing == null || existing.epoch != epoch) return fresh;
  if (existing.dismissed || existing.eventId == eventId) return null;
  return createdAt > existing.createdAt ? fresh : null;
}

/// Pure: the notice the group page shows for [channel] — only one that
/// arrived on this very channel and wasn't dismissed.
LinkReplacedNotice? visibleLinkReplacedNotice(
  LinkReplacedNotice? notice,
  LinkChannelModel? channel,
) {
  if (notice == null || channel == null) return null;
  if (notice.dismissed || notice.epoch != channel.epoch) return null;
  return notice;
}
