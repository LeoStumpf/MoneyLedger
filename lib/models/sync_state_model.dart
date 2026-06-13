/// Per-(group, peer) anti-entropy bookkeeping (Phase C).
class PeerSyncStateModel {
  final String groupId;
  final String userId;

  /// Last time (ms epoch) a digest from [userId] matched our local state
  /// exactly for [groupId] — i.e. the peer provably had everything we had.
  final int lastInSyncAt;

  /// Last time (ms epoch) we sent this peer a digest for [groupId].
  final int lastDigestSentAt;

  const PeerSyncStateModel({
    required this.groupId,
    required this.userId,
    this.lastInSyncAt = 0,
    this.lastDigestSentAt = 0,
  });
}
