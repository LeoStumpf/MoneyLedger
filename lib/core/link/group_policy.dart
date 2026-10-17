/// G52: which sync rules apply to a group — Matrix (G6), link-only or mixed
/// (`docs/design/no-login-sharing.md` §6.4). Plain Dart, no DB.
///
/// **Why inbound data can never downgrade a Matrix group to the link
/// path.** The policy is derived from two pieces of **local** state only:
///  1. whether this device has a `link_channels` row for the group — created
///     only by this user's own action (opening an invite link for a group /
///     joining one), device-local, never synced, never read from a backup
///     file, a digest, a bootstrap or a link snapshot; without it the policy
///     is always [GroupPolicy.matrix], whatever any stored or inbound row
///     says;
///  2. with a channel, whether the **stored** meta is signed: signed →
///     [GroupPolicy.mixed], unsigned / not stored yet → [GroupPolicy.linkOnly].
///     Inbound data can only move a channel's group from linkOnly to mixed
///     (a signed meta replacing an unsigned one), i.e. towards *more* Matrix
///     rules, never the other way: a signed meta can only be replaced by
///     another verified signed meta — on the Matrix path (G6) and on the
///     link path alike (an unsigned meta is accepted via link only in a
///     linkOnly group, never over a signed one). Only a backup restore the
///     user starts can store an unsigned meta over a signed one.
///
/// On top of that, unsigned versions are only ever accepted by a
/// `RecordGate` built **for the link path** (`linkPolicy:`); the Matrix
/// (to-device) path never loosens G6 — a Matrix group stays exactly as
/// strict as before even if a peer relays unsigned versions for it.
/// (The join flow, G52 step 7, must therefore refuse to open a channel for a
/// group id this device already holds as a non-link group — otherwise the
/// user's own join would turn that group mixed.)
library;

import '../../models/group_model.dart';
import '../../models/link_model.dart';

enum GroupPolicy {
  /// No link channel on this device: G6 / G18 unchanged; the link path
  /// treats it like any Matrix group (unsigned refused).
  matrix,

  /// A link channel and an unsigned (or not yet stored) meta — created in
  /// local mode / via a link. Matrix never syncs it (no digests, bootstraps,
  /// resync answers, relays; inbound to-device records for it are dropped);
  /// on the link path unsigned versions are accepted, signed ones verified,
  /// Matrix-ID claims refused.
  linkOnly,

  /// A link channel and a signed meta (G53: the meta will carry
  /// `link: {epoch, secret}`). Matrix path unchanged for now (G53 adds the
  /// relayed-unsigned exception); the link path accepts unsigned versions.
  mixed;

  /// Whether a gate on the **link path** accepts unsigned versions.
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
  if (channel == null) return GroupPolicy.matrix;
  if (meta != null && meta.sig != null) return GroupPolicy.mixed;
  return GroupPolicy.linkOnly;
}

/// A group's policy plus who this device is in it on the link path
/// (`link_channels.my_participant_id`, null = not picked / no channel).
class GroupPolicyInfo {
  final GroupPolicy policy;
  final String? myParticipantId;

  const GroupPolicyInfo(this.policy, {this.myParticipantId});

  static const matrix = GroupPolicyInfo(GroupPolicy.matrix);

  bool get isLinkOnly => policy == GroupPolicy.linkOnly;
}

/// Looks up a group's [GroupPolicyInfo] (production: `LinkDao.policyOf`).
typedef GroupPolicyLookup = Future<GroupPolicyInfo> Function(String groupId);
