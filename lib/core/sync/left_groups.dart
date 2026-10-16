import 'dart:convert';

/// Device-local record that this account **left or deleted** a group (G9).
///
/// Leaving/deleting purges the group from the local DB, but peers may still
/// name it afterwards — a late digest (anti-entropy rule 5 would then ask for
/// a bootstrap), an in-flight bootstrap, or one of our own other devices
/// answering a `resync_request{scope: all}`. The tombstone makes the receivers
/// ignore all of that, **unless we were re-added**: a member record for our
/// MXID with `status: active` and an `updated_at` newer than [leftAt].
///
/// Stored in `AppSettings` (key `left_group:<groupId>`, JSON value) — never
/// replicated, like every other AppSettings flag.
class LeftGroupTombstone {
  /// When we left / deleted (ms epoch). For a leave this is the `updated_at`
  /// of our own `removed` member record.
  final int leftAt;

  /// Our own `removed` member payload (wire format, see `memberPayload`) for a
  /// **leave**; null for a local **delete**. Re-sent to any peer whose digest
  /// still lists us as active with an older clock — so a lost "X left" notice
  /// is repaired even though the group is gone locally (SyncEngine rule 7).
  final Map<String, dynamic>? removalNotice;

  const LeftGroupTombstone({required this.leftAt, this.removalNotice});

  String encode() => jsonEncode({
    'left_at': leftAt,
    if (removalNotice != null) 'member': removalNotice,
  });

  static LeftGroupTombstone? decode(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final member = m['member'];
      return LeftGroupTombstone(
        leftAt: m['left_at'] as int? ?? 0,
        removalNotice: member is Map ? Map<String, dynamic>.from(member) : null,
      );
    } catch (_) {
      // A corrupt value still means "left" — never resurrect on parse errors.
      return const LeftGroupTombstone(leftAt: 0);
    }
  }
}

/// How a peer's view of **our** membership relates to a [LeftGroupTombstone].
enum PeerViewOfMe {
  /// The peer doesn't list our MXID (or lists it removed) — nothing to do.
  unaware,

  /// The peer still has us `active` with a clock ≤ the tombstone: it missed
  /// our leave notice (stale).
  staleActive,

  /// The peer has us `active` with a clock newer than the tombstone: we were
  /// **re-added** after leaving.
  readded,
}

/// Classifies member records (a bootstrap's `members` list or a digest's
/// `members` map values — both carry `matrix_id`/`status`/`updated_at`)
/// against our tombstone. Pure, unit-testable.
PeerViewOfMe classifyPeerViewOfMe({
  required Iterable<Object?> memberRecords,
  required String myMxid,
  required int leftAt,
}) {
  var result = PeerViewOfMe.unaware;
  for (final r in memberRecords) {
    if (r is! Map || r['matrix_id'] != myMxid) continue;
    if ((r['status'] as String? ?? 'active') != 'active') continue;
    final at = r['updated_at'] as int? ?? 0;
    if (at > leftAt) return PeerViewOfMe.readded;
    result = PeerViewOfMe.staleActive;
  }
  return result;
}
