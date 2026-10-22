/// G52 / G53: which sync rules apply to a group — Matrix (G6), link-only or
/// mixed (`docs/design/no-login-sharing.md` §6.4, §10.1). Plain Dart, no DB.
///
/// Derived from **local** state only — this device's `link_channels` row
/// for the group and the **stored** meta ([deriveGroupPolicy]):
///  * a **signed** meta decides on its own (G53): with an open `link` →
///    [GroupPolicy.mixed], without one → [GroupPolicy.matrix] (a Matrix
///    group, or a link group that was **locked** — its `locked_at` is kept
///    in [GroupPolicyInfo.lockedAt]; a leftover channel is then dropped by
///    the link sync engine);
///  * an unsigned (or not yet stored) meta → [GroupPolicy.linkOnly] when
///    this device has a channel, else [GroupPolicy.matrix] (legacy unsigned
///    Matrix groups and local-mode groups).
///
/// **What inbound data can change.** A stored signed meta can only be
/// replaced by another *verified* signed meta (G6 rules on both paths; an
/// unsigned meta is accepted via link only in a linkOnly group, never over
/// a signed one) whose signer claims a participant of the group (record
/// gate rule 5). So only a **member** can open a link on a Matrix group
/// (G53 *Invite by link*: → mixed) or lock a link group (→ matrix), and a
/// linkOnly group turns mixed only through a signed meta of a Matrix device
/// that claimed a participant (§10.1 "Link → Matrix"). The channel itself
/// is device-local and never read from a backup file, a digest, a bootstrap
/// or a snapshot; without one an unsigned meta never makes a group
/// link-only, so inbound data can't take a Matrix group off the G6 rules.
/// (The join flow therefore refuses to open a channel for a group id this
/// device already holds as a non-link group.)
///
/// Unsigned versions are accepted (`RecordGate`):
///  * linkOnly — on the link path (every kind; Matrix never touches it);
///  * mixed — on the link path **and** relayed over Matrix by an active
///    member (§10.1), except metas and Matrix-ID claims, which must be
///    signed there;
///  * matrix after a lock — only versions not newer than `locked_at`
///    (history from the link time); none in a Matrix group never linked.
library;

import '../../models/group_model.dart';
import '../../models/link_model.dart';

enum GroupPolicy {
  /// A Matrix group (signed meta without a link — also a locked link group)
  /// or any group without a link channel and without a signed link: G6 /
  /// G18 unchanged (see [GroupPolicyInfo.lockedAt] for a locked group's
  /// history).
  matrix,

  /// A link channel and an unsigned (or not yet stored) meta — created in
  /// local mode / via a link. Matrix never syncs it (no digests, bootstraps,
  /// resync answers, relays; inbound to-device records for it are dropped);
  /// on the link path unsigned versions are accepted, signed ones verified,
  /// Matrix-ID claims refused (except G53's signed self-claim).
  linkOnly,

  /// G53: a signed meta with an open `link: {epoch, secret}` — a Matrix
  /// group shared by link too. Matrix devices bridge (publish + read the
  /// relays); unsigned versions are accepted on both paths (not metas, not
  /// claims).
  mixed;

  /// Whether a gate on the **link path** may accept unsigned versions.
  bool get acceptsUnsignedViaLink => this != GroupPolicy.matrix;

  /// Whether the Matrix engines (`SyncEngine`, `LedgerSyncer`, relays) may
  /// touch the group at all.
  bool get matrixSyncs => this != GroupPolicy.linkOnly;
}

/// The policy of a group given this device's [channel] for it (null = none)
/// and its stored [meta] (null = not stored yet). See the library doc.
GroupPolicy deriveGroupPolicy({
  required LinkChannelModel? channel,
  required GroupModel? meta,
}) {
  if (meta != null && meta.sig != null) {
    return meta.link != null ? GroupPolicy.mixed : GroupPolicy.matrix;
  }
  return channel == null ? GroupPolicy.matrix : GroupPolicy.linkOnly;
}

/// A group's policy plus who this device is in it on the link path
/// (`link_channels.my_participant_id`, null = not picked / no channel).
class GroupPolicyInfo {
  final GroupPolicy policy;
  final String? myParticipantId;

  /// G53: the stored signed meta's `locked_at` while the group is locked
  /// (policy [GroupPolicy.matrix]); null otherwise.
  final int? lockedAt;

  /// Whether this device has a link channel of the group.
  final bool hasChannel;

  /// G53 review: the Matrix ID claiming [myParticipantId] (null = nobody /
  /// no "me") — a Matrix account whose "me" it isn't uses a mixed group
  /// from the **link side** (joined by link) and writes link versions.
  final String? myMatrixId;

  const GroupPolicyInfo(
    this.policy, {
    this.myParticipantId,
    this.lockedAt,
    this.hasChannel = false,
    this.myMatrixId,
  });

  static const matrix = GroupPolicyInfo(GroupPolicy.matrix);

  bool get isLinkOnly => policy == GroupPolicy.linkOnly;

  bool get isMixed => policy == GroupPolicy.mixed;
}

/// [deriveGroupPolicy] + the rest of [GroupPolicyInfo] (pure).
GroupPolicyInfo groupPolicyInfo({
  required LinkChannelModel? channel,
  required GroupModel? meta,
  String? myMatrixId,
}) {
  final policy = deriveGroupPolicy(channel: channel, meta: meta);
  return GroupPolicyInfo(
    policy,
    myParticipantId: channel?.myParticipantId,
    lockedAt: policy == GroupPolicy.matrix && meta?.isLocked == true
        ? meta!.lockedAt
        : null,
    hasChannel: channel != null,
    myMatrixId: channel?.myParticipantId == null ? null : myMatrixId,
  );
}

/// Looks up a group's [GroupPolicyInfo] (production: `LinkDao.policyOf`).
typedef GroupPolicyLookup = Future<GroupPolicyInfo> Function(String groupId);
