/// G53 hardening (§10.1, Leo 2026-10-22): receivers check a **lock** — a
/// signed meta without `link`, with `locked_at` — before they store it.
library;

import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../sync/record_validation.dart';
import '../sync/record_version.dart';

/// Whether [g] locks its group anew compared to the stored meta [stored]:
/// signed, no `link`, a `locked_at` the stored meta doesn't already have
/// (a later version of an accepted lock — a rename — keeps the same
/// `locked_at` and isn't judged again).
bool isNewLock(GroupModel g, GroupModel? stored) =>
    g.sig != null &&
    g.link == null &&
    g.lockedAt != null &&
    stored?.lockedAt != g.lockedAt;

/// The participants that make a lock at [lockedAt] invalid: per
/// participant, the newest of [versions] (every participant version this
/// device knows — stored, version history, a snapshot) stamped at or
/// before [lockedAt] decides; if it is **active** and not claimed by a
/// valid Matrix ID, it blocks the lock. A participant this device knows no
/// version ≤ [lockedAt] of (it joined later, or the history was pruned)
/// doesn't block — the check never refuses a lock for missing knowledge.
/// Pure.
List<MemberModel> lockEligibilityBlockers(
  int lockedAt,
  Iterable<MemberModel> versions,
) {
  final atLock = <String, MemberModel>{};
  for (final v in versions) {
    if (v.updatedAt > lockedAt) continue;
    final have = atLock[v.userId];
    if (have == null || versionWins(memberVersion(v), memberVersion(have))) {
      atLock[v.userId] = v;
    }
  }
  return [
    for (final m in atLock.values)
      if (m.isActive && !isValidMxid(m.matrixId)) m,
  ];
}

/// Round 3 (Leo 2026-10-22): the participants whose **first** version
/// reached this device after the lock did — [entries] are this device's
/// participant history entries (`record_history`: participant id + append
/// position), [lockSeen] the highest position when the lock first arrived.
/// They don't count for the lock's eligibility (closes the trick of
/// publishing a person back-dated before an already seen lock). A
/// participant without history entries counts (it predates the history).
/// Pure.
Set<String> lateArrivals(
  Iterable<({String recordId, int position})> entries,
  int lockSeen,
) {
  final first = <String, int>{};
  for (final e in entries) {
    final have = first[e.recordId];
    if (have == null || e.position < have) first[e.recordId] = e.position;
  }
  return {
    for (final MapEntry(:key, :value) in first.entries)
      if (value > lockSeen) key,
  };
}
