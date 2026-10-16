import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/member_model.dart';
import '../../models/record_signature.dart';
import '../database/daos/expenses_dao.dart';
import '../database/daos/groups_dao.dart';
import '../database/daos/members_dao.dart';
import '../database/daos/signing_dao.dart';
import 'ledger_payloads.dart';
import 'record_signing.dart';
import 'record_validation.dart';
import 'record_version.dart';
import 'record_verifier.dart';

/// Applies inbound record versions to Drift **only if they verify** (G6).
/// The single path for live records, bootstraps, digest member gossip and
/// backup restores.
///
/// Per version:
/// 1. Not a newer version than what we hold → no-op, nothing is verified
///    (an unsigned relay of a legacy row we already hold at the same clock is
///    therefore harmless). "Newer" = higher `updated_at`, or the same clock
///    with a higher content hash (G27 tie-break, `record_version.dart`);
///    same clock + same hash is the same version.
/// 2. Exactly the version we already refused (clock **and** G27 hash) →
///    dropped silently. Other versions of the record — higher or lower — are
///    looked at on their own (G18 review: a refusal used to block every
///    version up to its clock, so one far-future refusal froze a record).
/// 3. Content validation (`record_validation.dart`): a malformed / out of
///    range expense or payment — or (G47) a group meta whose custom
///    categories break the bounds (`groupMetaProblem`) — is refused as
///    `invalid_record`.
/// 4. [RecordVerifier] decides; a refused version is logged and — for the
///    recorded reasons — stored in `rejected_versions` (never one with a
///    clock beyond `now + kSignedClockSkewTolerance`), so our digest tells
///    peers to stop re-sending it (no repair loop).
/// 5. (G18 review, defence in depth) The signer of an expense / payment /
///    group-meta version must be a participant claimed by that account in
///    the record's group (a removed one only for versions not newer than
///    the removal), or the account relaying it to us. Otherwise it is
///    dropped (`signer_not_member`, transient — the member record may still
///    be on its way).
/// 6. Accepted → LWW upsert with its `sig` / `origin` (the clock is never
///    clamped: the verifier already refused clocks too far in the future).
///
/// [acceptUnsigned] is for a user-started **backup restore** only: an
/// unsigned record (a pre-G6 row in the user's own backup) is stored as
/// legacy instead of refused; earlier sync refusals of a restored version
/// are bypassed and cleared; the signer rule (5) doesn't apply (the user's
/// own file). Bad signatures and invalid content are refused there as well.
/// G18 review 2: a restored unsigned version carries **no** `origin` — a
/// creation statement on an unsigned row would lend its (possibly forged)
/// content an "added by" (attribution must never lie), and the row must
/// never look like this device's to sign later.
///
/// G18 review 2: a participant version whose `matrix_id` isn't a valid MXID
/// is refused as `invalid_record` (`memberProblem`) — except a claim by local
/// mode's pseudo account when [allowLocalClaims] (a restore of local mode's
/// own backup). An expense / payment version whose id is stored for
/// **another group** is refused as `invalid_record` too (it would move or
/// overwrite that group's record).
class RecordGate {
  RecordGate({
    required this.verifier,
    required this.signing,
    required this.groups,
    required this.members,
    required this.expenses,
    this.acceptUnsigned = false,
    this.allowLocalClaims = false,
    bool Function()? isAlive,
    this.onRefused,
    int Function()? clock,
  }) : _isAlive = isAlive ?? (() => true),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final RecordVerifier verifier;
  final SigningDao signing;
  final GroupsDao groups;
  final MembersDao members;
  final ExpensesDao expenses;
  final bool acceptUnsigned;

  /// Restore of local mode's own backup only: participant claims by the
  /// local pseudo account (`local:self`) are stored, not refused.
  final bool allowLocalClaims;
  final bool Function() _isAlive;
  final int Function() _clock;

  /// Called for every refused version (after logging) — the syncer uses it
  /// to surface refused **unsigned** (pre-G6) records to the user (G35).
  final void Function(
    String groupId,
    RecordKind kind,
    RejectReason reason,
    String relayedBy,
  )?
  onRefused;

  int get _ceiling => _clock() + kSignedClockSkewTolerance.inMilliseconds;

  /// Clamp for the unsigned (restored legacy) clocks — same bound as
  /// `LedgerSyncer.clampInboundClock`.
  int _clamp(int t) => t > _ceiling ? _ceiling : t;

  /// Whether [v] is exactly the version of record [id] we refused before.
  /// A restore ([acceptUnsigned]) bypasses earlier refusals.
  Future<bool> _refusedExactly(
    String group,
    RecordKind kind,
    String id,
    RecordVersion v,
  ) async {
    if (acceptUnsigned) return false;
    return signing.isRejected(group, kind.wire, id, v);
  }

  /// Whether to store an unsigned version anyway (restore only; a far-future
  /// legacy clock is clamped).
  bool _legacyOk(RecordSignature? sig, Verdict v) =>
      acceptUnsigned &&
      sig == null &&
      (v.reason == RejectReason.unsigned ||
          v.reason == RejectReason.futureClock);

  Future<void> _refuse(
    String group,
    RecordKind kind,
    String id,
    RecordVersion version,
    Verdict v,
    String relayedBy,
    RecordSignature? sig, {
    String? detail,
  }) async {
    final reason = v.reason!;
    debugPrint(
      '[g6] refused ${kind.wire} $id@${version.at} in $group '
      '(${reason.wire}${detail == null ? '' : ': $detail'}, via $relayedBy, '
      'signer ${sig?.user}/${sig?.device})',
    );
    onRefused?.call(group, kind, reason, relayedBy);
    // Never remember a refusal stamped beyond the clock tolerance: it could
    // only ever block (a version of) the record "from the future".
    if (!reason.recorded || !_isAlive() || version.at > _ceiling) return;
    await signing.recordRejected(
      RefusedVersion(
        groupId: group,
        kind: kind.wire,
        recordId: id,
        updatedAt: version.at,
        reason: reason.wire,
        relayedBy: relayedBy,
        claimedSigner: sig?.user,
        versionHash: version.hash,
      ),
    );
  }

  /// A restore stored [version]: forget a refusal of it (or of an older
  /// version) from sync.
  Future<void> _clearRefusal(
    String group,
    RecordKind kind,
    String id,
    RecordVersion version,
  ) async {
    if (!acceptUnsigned || !_isAlive()) return;
    await signing.clearRejectedUpTo(group, kind.wire, id, version);
  }

  /// G18 review 2: [stored] (looked up by id) belongs to another group than
  /// the inbound version — refuse it (it would move / overwrite that
  /// group's record). Returns whether it was refused.
  Future<bool> _foreignId(
    String group,
    String? storedGroup,
    RecordKind kind,
    String id,
    RecordVersion version,
    String relayedBy,
    RecordSignature? sig,
  ) async {
    if (storedGroup == null || storedGroup == group) return false;
    if (await _refusedExactly(group, kind, id, version)) return true;
    await _refuse(
      group,
      kind,
      id,
      version,
      const Verdict.reject(RejectReason.invalid),
      relayedBy,
      sig,
      detail: 'id belongs to another group',
    );
    return true;
  }

  /// Rule 5: whether [sig]'s account may have written a version stamped [at]
  /// in [group] — a participant it claims (active; or removed, for versions
  /// not newer than the removal), or the relaying account itself. [extra]
  /// are participants not stored yet (a snapshot's own members, for its
  /// meta). Legacy (unsigned) versions and restores are not checked.
  Future<bool> _signerAllowed(
    String group,
    RecordSignature? sig,
    int at,
    String relayedBy, {
    Iterable<MemberModel> extra = const [],
  }) async {
    if (sig == null || acceptUnsigned || sig.user == relayedBy) return true;
    final byId = <String, MemberModel>{};
    for (final m in [...await members.getMembers(group), ...extra]) {
      final have = byId[m.userId];
      if (have == null || m.updatedAt > have.updatedAt) byId[m.userId] = m;
    }
    final claimed = byId.values.where((m) => m.matrixId == sig.user);
    if (claimed.isEmpty) return false;
    if (claimed.any((m) => m.isActive)) return true;
    final removedAt = claimed
        .map((m) => m.updatedAt)
        .reduce((a, b) => a > b ? a : b);
    return at <= removedAt;
  }

  Future<bool> _signerCheck(
    String group,
    RecordKind kind,
    String id,
    RecordVersion version,
    RecordSignature? sig,
    String relayedBy, {
    Iterable<MemberModel> extra = const [],
  }) async {
    if (await _signerAllowed(group, sig, version.at, relayedBy, extra: extra)) {
      return true;
    }
    if (_isAlive()) {
      await _refuse(
        group,
        kind,
        id,
        version,
        const Verdict.reject(RejectReason.signerNotMember),
        relayedBy,
        sig,
      );
    }
    return false;
  }

  /// An inbound expense payload. Returns whether it was stored.
  Future<bool> expense(
    Map<String, dynamic> content, {
    required String relayedBy,
  }) async {
    final e = expenseFromPayload(content);
    if (e == null) return false;
    final version = expenseVersion(e);
    final stored = await expenses.getExpenseById(e.id);
    if (!_isAlive()) return false;
    if (await _foreignId(
      e.roomId,
      stored?.roomId,
      RecordKind.expense,
      e.id,
      version,
      relayedBy,
      e.sig,
    )) {
      return false;
    }
    if (stored != null && !versionWins(version, expenseVersion(stored))) {
      return false;
    }
    if (await _refusedExactly(e.roomId, RecordKind.expense, e.id, version)) {
      return false;
    }
    final problem = expenseProblem(e);
    if (problem != null) {
      await _refuse(
        e.roomId,
        RecordKind.expense,
        e.id,
        version,
        const Verdict.reject(RejectReason.invalid),
        relayedBy,
        e.sig,
        detail: problem,
      );
      return false;
    }
    final v = await verifier.expense(e, stored: stored);
    if (!_isAlive()) return false;
    if (!v.accepted && !_legacyOk(e.sig, v)) {
      await _refuse(
        e.roomId,
        RecordKind.expense,
        e.id,
        version,
        v,
        relayedBy,
        e.sig,
      );
      return false;
    }
    if (!await _signerCheck(
          e.roomId,
          RecordKind.expense,
          e.id,
          version,
          e.sig,
          relayedBy,
        ) ||
        !_isAlive()) {
      return false;
    }
    final row = v.accepted
        ? expenseCompanion(e)
        : expenseCompanion(
            e.withSigning(),
          ).copyWith(updatedAt: Value(_clamp(e.updatedAt)));
    await expenses.upsertExpenseLww(row);
    await _clearRefusal(e.roomId, RecordKind.expense, e.id, version);
    return true;
  }

  Future<bool> settlement(
    Map<String, dynamic> content, {
    required String relayedBy,
  }) async {
    final s = settlementFromPayload(content);
    if (s == null) return false;
    final version = settlementVersion(s);
    final stored = await expenses.getSettlementById(s.id);
    if (!_isAlive()) return false;
    if (await _foreignId(
      s.roomId,
      stored?.roomId,
      RecordKind.settlement,
      s.id,
      version,
      relayedBy,
      s.sig,
    )) {
      return false;
    }
    if (stored != null && !versionWins(version, settlementVersion(stored))) {
      return false;
    }
    if (await _refusedExactly(s.roomId, RecordKind.settlement, s.id, version)) {
      return false;
    }
    final problem = settlementProblem(s);
    if (problem != null) {
      await _refuse(
        s.roomId,
        RecordKind.settlement,
        s.id,
        version,
        const Verdict.reject(RejectReason.invalid),
        relayedBy,
        s.sig,
        detail: problem,
      );
      return false;
    }
    final v = await verifier.settlement(s, stored: stored);
    if (!_isAlive()) return false;
    if (!v.accepted && !_legacyOk(s.sig, v)) {
      await _refuse(
        s.roomId,
        RecordKind.settlement,
        s.id,
        version,
        v,
        relayedBy,
        s.sig,
      );
      return false;
    }
    if (!await _signerCheck(
          s.roomId,
          RecordKind.settlement,
          s.id,
          version,
          s.sig,
          relayedBy,
        ) ||
        !_isAlive()) {
      return false;
    }
    final row = v.accepted
        ? settlementCompanion(s)
        : settlementCompanion(
            s.withSigning(),
          ).copyWith(updatedAt: Value(_clamp(s.updatedAt)));
    await expenses.upsertSettlementLww(row);
    await _clearRefusal(s.roomId, RecordKind.settlement, s.id, version);
    return true;
  }

  /// A participant version — a live `member` payload, a bootstrap entry or a
  /// digest's member gossip. [requiredSigner]: see [RecordVerifier.member].
  Future<bool> member(
    Map<String, dynamic> content, {
    required String relayedBy,
    String? requiredSigner,
  }) async {
    final m = memberFromPayload(content);
    if (m == null) return false;
    final version = memberVersion(m);
    final current = (await members.getMembers(
      m.groupId,
    )).where((x) => x.userId == m.userId).firstOrNull;
    if (!_isAlive()) return false;
    if (current != null && !versionWins(version, memberVersion(current))) {
      return false;
    }
    if (await _refusedExactly(
      m.groupId,
      RecordKind.member,
      m.userId,
      version,
    )) {
      return false;
    }
    final problem = memberProblem(m, allowLocalClaim: allowLocalClaims);
    if (problem != null) {
      await _refuse(
        m.groupId,
        RecordKind.member,
        m.userId,
        version,
        const Verdict.reject(RejectReason.invalid),
        relayedBy,
        m.sig,
        detail: problem,
      );
      return false;
    }
    final v = await verifier.member(m, requiredSigner: requiredSigner);
    if (!_isAlive()) return false;
    if (!v.accepted && !_legacyOk(m.sig, v)) {
      await _refuse(
        m.groupId,
        RecordKind.member,
        m.userId,
        version,
        v,
        relayedBy,
        m.sig,
      );
      return false;
    }
    final row = memberCompanion(m);
    await members.upsertMemberLww(
      v.accepted ? row : row.copyWith(updatedAt: Value(_clamp(m.updatedAt))),
    );
    await _clearRefusal(m.groupId, RecordKind.member, m.userId, version);
    return true;
  }

  /// A group-meta version (a `group` payload or a bootstrap's `meta`).
  /// [snapshotMembers]: the participants of the snapshot carrying it (they
  /// count for the signer rule before they are stored).
  Future<bool> meta(
    Map<String, dynamic> content, {
    required String relayedBy,
    Iterable<MemberModel> snapshotMembers = const [],
  }) async {
    final g = groupMetaFromPayload(content);
    if (g == null) return false;
    final version = groupMetaVersion(g);
    final stored = await groups.getGroup(g.roomId);
    if (!_isAlive()) return false;
    if (stored != null && !versionWins(version, groupMetaVersion(stored))) {
      return false;
    }
    if (await _refusedExactly(g.roomId, RecordKind.meta, g.roomId, version)) {
      return false;
    }
    final problem = groupMetaProblem(g);
    if (problem != null) {
      await _refuse(
        g.roomId,
        RecordKind.meta,
        g.roomId,
        version,
        const Verdict.reject(RejectReason.invalid),
        relayedBy,
        g.sig,
        detail: problem,
      );
      return false;
    }
    final v = await verifier.meta(g);
    if (!_isAlive()) return false;
    if (!v.accepted && !_legacyOk(g.sig, v)) {
      await _refuse(
        g.roomId,
        RecordKind.meta,
        g.roomId,
        version,
        v,
        relayedBy,
        g.sig,
      );
      return false;
    }
    if (!await _signerCheck(
          g.roomId,
          RecordKind.meta,
          g.roomId,
          version,
          g.sig,
          relayedBy,
          extra: snapshotMembers,
        ) ||
        !_isAlive()) {
      return false;
    }
    final row = groupCompanion(g);
    await groups.upsertGroupLww(
      v.accepted ? row : row.copyWith(updatedAt: Value(_clamp(g.updatedAt))),
    );
    await _clearRefusal(g.roomId, RecordKind.meta, g.roomId, version);
    return true;
  }

  /// A whole-group snapshot (bootstrap / restored backup group): the signed
  /// meta, then every member, expense and settlement — each verified on its
  /// own, so one bad record doesn't sink the snapshot.
  ///
  /// G18 review: every nested entry must belong to the snapshot's own group
  /// ([snapshotEntries]) — entries naming another group are dropped (the
  /// sender gate only checked the snapshot's group: a stranger's TOFU
  /// bootstrap could otherwise write into any group we know). Members are
  /// applied before the records (each chunked part carries all members), so
  /// the signer rule sees the snapshot's participants.
  ///
  /// [trustAttestations]: store the snapshot's `device_keys` as vouched-for
  /// keys first — only for a sender we trust with the whole group anyway (a
  /// new group's inviter, our own devices) or a restore the user started.
  /// They are scoped to this group: they vouch for its records only.
  ///
  /// A group we don't know yet is only created when its meta verifies;
  /// otherwise the snapshot is dropped as a whole (no orphan rows).
  Future<void> snapshot(
    Map<String, dynamic> content, {
    required String relayedBy,
    required bool trustAttestations,
  }) async {
    final s = snapshotEntries(content);
    if (s == null) {
      debugPrint('[g6] dropped malformed snapshot via $relayedBy');
      return;
    }
    if (s.droppedForeign > 0) {
      debugPrint(
        '[g6] snapshot of ${s.groupId} via $relayedBy: dropped '
        '${s.droppedForeign} entries of other groups',
      );
    }
    if (trustAttestations) {
      await signing.pinAttestedKeys(
        parseDeviceKeys(content['device_keys']),
        relayedBy,
        group: s.groupId,
      );
      if (!_isAlive()) return;
    }
    await meta(
      s.meta,
      relayedBy: relayedBy,
      snapshotMembers: [for (final m in s.members) ?memberFromPayload(m)],
    );
    if (!_isAlive()) return;
    if (await groups.getGroup(s.groupId) == null) {
      debugPrint('[g6] dropped snapshot of ${s.groupId}: group meta refused');
      return;
    }
    for (final m in s.members) {
      if (!_isAlive()) return;
      await member(m, relayedBy: relayedBy);
    }
    for (final e in s.expenses) {
      if (!_isAlive()) return;
      await expense(e, relayedBy: relayedBy);
    }
    for (final st in s.settlements) {
      if (!_isAlive()) return;
      await settlement(st, relayedBy: relayedBy);
    }
  }
}

/// The parts of a snapshot payload that belong to **its own group** (G18
/// review): the meta (the signed `meta`, else the legacy top-level fields)
/// and the member / expense / settlement entries whose `group` is the
/// snapshot's — every other entry is dropped and counted. Null when the
/// snapshot has no group id or its `meta` names another group.
({
  String groupId,
  Map<String, dynamic> meta,
  List<Map<String, dynamic>> members,
  List<Map<String, dynamic>> expenses,
  List<Map<String, dynamic>> settlements,
  int droppedForeign,
})?
snapshotEntries(Map<String, dynamic> content) {
  final groupId = content['group'];
  if (groupId is! String || groupId.isEmpty) return null;
  final rawMeta = content['meta'];
  final Map<String, dynamic> meta;
  if (rawMeta is Map) {
    if (rawMeta['group'] != groupId) return null;
    meta = Map<String, dynamic>.from(rawMeta);
  } else {
    meta = {
      'group': groupId,
      'name': content['name'],
      'currency': content['currency'],
      'updated_at': content['updated_at'],
    };
  }
  var dropped = 0;
  List<Map<String, dynamic>> own(Object? raw) {
    final out = <Map<String, dynamic>>[];
    for (final r in raw is List ? raw : const []) {
      if (r is Map && r['group'] == groupId) {
        out.add(Map<String, dynamic>.from(r));
      } else {
        dropped++;
      }
    }
    return out;
  }

  final members = own(content['members']);
  final expenses = own(content['expenses']);
  final settlements = own(content['settlements']);
  return (
    groupId: groupId,
    meta: meta,
    members: members,
    expenses: expenses,
    settlements: settlements,
    droppedForeign: dropped,
  );
}
