/// A group participant, projected from the Members table.
///
/// [userId] is the **stable participant id** (per-group), not necessarily a
/// Matrix ID — for a Tricount-style local participant it is a UUID; for one
/// created from / claimed by a real account it equals the MXID. The claimed
/// Matrix account, if any, is [matrixId] (null = pure-local, never a sync
/// target). [displayName] is the human-facing name. [status] is `active` or
/// `removed`; [updatedAt] is the LWW logical clock (ms epoch).
class MemberModel {
  final String groupId;
  final String userId;
  final String displayName;
  final String? matrixId;
  final String status;
  final int updatedAt;

  const MemberModel({
    required this.groupId,
    required this.userId,
    this.displayName = '',
    this.matrixId,
    required this.status,
    required this.updatedAt,
  });

  bool get isActive => status == 'active';

  /// Whether this participant is linked to a Matrix account (and thus a
  /// reachable sync target).
  bool get isClaimed => matrixId != null;
}

/// A friendly default display name for a Matrix ID — its localpart
/// (`@alice:server` → `alice`) — or the input unchanged if it isn't an MXID.
String localpartOf(String matrixId) =>
    (matrixId.startsWith('@') && matrixId.contains(':'))
        ? matrixId.substring(1, matrixId.indexOf(':'))
        : matrixId;
