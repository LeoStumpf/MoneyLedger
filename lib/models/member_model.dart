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

/// The participant in [members] claimed by the Matrix account [matrixId]
/// (G26). Normally there is at most one, but DBs written before the re-add fix
/// may hold duplicates (a second participant with the same `matrixId`): then
/// prefer an **active** one, then the **newest** clock — every "who is this
/// account?" lookup goes through here so they all agree.
MemberModel? claimedBy(Iterable<MemberModel> members, String matrixId) {
  MemberModel? best;
  for (final m in members) {
    if (m.matrixId != matrixId) continue;
    if (best == null ||
        (m.isActive && !best.isActive) ||
        (m.isActive == best.isActive && m.updatedAt > best.updatedAt)) {
      best = m;
    }
  }
  return best;
}

/// A fresh LWW clock for a local edit of a record whose current clock is
/// [previous]: the wall clock, but always strictly newer than [previous] — so
/// an edit made on a device whose clock lags the record's last writer still
/// wins locally and on peers (e.g. re-adding someone whose `removed` record
/// was stamped by a fast clock, G26).
int nextLwwClock(int previous, {int? now}) {
  final t = now ?? DateTime.now().millisecondsSinceEpoch;
  return t > previous ? t : previous + 1;
}
