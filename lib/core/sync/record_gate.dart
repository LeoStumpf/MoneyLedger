import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/member_model.dart';
import '../../models/record_signature.dart';
import '../database/daos/expenses_dao.dart';
import '../database/daos/groups_dao.dart';
import '../database/daos/history_dao.dart' show HistorySource;
import '../database/daos/members_dao.dart';
import '../database/daos/signing_dao.dart';
import '../link/group_policy.dart';
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
///
/// **G52 link path** ([linkPolicy] set — only the link sync engine builds
/// such a gate; the Matrix path never does): per record group, the policy
/// derived from **local** state (`group_policy.dart` — inbound data can't
/// make a Matrix group link-only) decides (§6.4):
/// * `matrix` → exactly the G6 rules above (unsigned refused);
/// * `linkOnly` / `mixed` → an **unsigned** version is accepted instead of
///   refused as `unsigned` — stored unsigned, not `pendingSign`, **without
///   `origin`** (attribution never lies), its `by` hint kept as
///   `link_author`; rule 5 doesn't apply to it (it has no signer). Everything
///   else still holds: LWW / G27, exactly-refused versions, the content
///   rules, the wrong-group id rule, the future clock (> now + 5 min,
///   dropped transiently — never clamped), and a **signed** version is
///   verified as usual (a bad signature / origin / key conflict is refused:
///   a forged signature is never acceptable, even where unsigned is).
///   Additionally a participant version **claiming a Matrix ID** is refused
///   (`invalid_record`) in a `linkOnly` group, and an unsigned one in a
///   `mixed` group (G53 adds the narrow signed self-claim); an **unsigned
///   meta** is accepted only in a `linkOnly` group — never over the signed
///   meta of a `mixed` one (that would turn it link-only).
/// The `by` hint is dropped on the Matrix path (only link-path and restored
/// versions keep it — G53: and unsigned versions a mixed group accepts).
///
/// **G53 mixed groups + lock** (§10.1; policies in `group_policy.dart`):
/// * `mixed` (a signed meta with an open `link`): unsigned expense /
///   payment / participant versions are accepted on the link path **and**,
///   with [matrixPolicy] set, when an active member relays them over Matrix
///   (the membership gate in `LedgerSyncer` / `SyncEngine` still applies) —
///   stored unsigned, never re-signed, shown "via link, not verified". An
///   unsigned **meta** or Matrix-ID claim is refused on both paths.
/// * a **locked** group (a signed meta without `link`, with `locked_at`):
///   an unsigned version newer than `locked_at` is refused (`unsigned`,
///   recorded — no repair loop); older ones are history from the link time
///   and accepted.
/// * an **unsigned** version of a participant some Matrix account claims is
///   refused (it would change or drop the claim without that account).
/// * a **signed self-claim** (§10.1 "Link participant joins Matrix") on the
///   link path: a participant version claiming Matrix ID X, signed by X,
///   for a stored, active participant nobody claims yet (or X already does)
///   is accepted in a `linkOnly` or `mixed` group; any other signed claim
///   via link must be signed by an account that claims an active
///   participant of the group. (Over Matrix the sender gate decides.)
/// * an **unsigned meta** carrying `link` / `locked_at` is refused
///   (`invalid_record`): the link state only exists signed.
/// * a meta that opens a link (a new `link` secret) forgets the group's
///   earlier `unsigned` refusals, so peers re-send those versions.
class RecordGate {
  RecordGate({
    required this.verifier,
    required this.signing,
    required this.groups,
    required this.members,
    required this.expenses,
    this.acceptUnsigned = false,
    this.allowLocalClaims = false,
    this.linkPolicy,
    this.matrixPolicy,
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

  /// G52: set → this gate serves the **link path** (see the class doc); the
  /// lookup gives each record group's policy. Null on the Matrix path.
  final GroupPolicyLookup? linkPolicy;

  /// G53: set on the **Matrix** path (to-device records, bootstraps, digest
  /// gossip) — each record group's policy, so a `mixed` group accepts
  /// unsigned versions relayed by its members and a locked group keeps its
  /// link-time history (see the class doc). Ignored when [linkPolicy] is
  /// set. Null → plain G6.
  final GroupPolicyLookup? matrixPolicy;
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

  /// G48: how stored versions are labelled in the version history.
  HistorySource get _historySource =>
      acceptUnsigned ? HistorySource.restore : HistorySource.inbound;

  int get _ceiling => _clock() + kSignedClockSkewTolerance.inMilliseconds;

  /// Clamp for the unsigned (restored legacy) clocks — same bound as
  /// `LedgerSyncer.clampInboundClock`.
  int _clamp(int t) => t > _ceiling ? _ceiling : t;

  bool get _linkPath => linkPolicy != null;

  /// G52 / G53: [group]'s policy — via [linkPolicy] on the link path, via
  /// [matrixPolicy] on the Matrix path; null when neither is set (plain
  /// G6). A failing lookup counts as `matrix` (the strict rules).
  Future<GroupPolicyInfo?> _policyOf(String group) async {
    final lookup = linkPolicy ?? matrixPolicy;
    if (lookup == null) return null;
    try {
      return await lookup(group);
    } catch (_) {
      return GroupPolicyInfo.matrix;
    }
  }

  /// G52 / G53: whether the refusal [v] of a version (clock [at]) signed by
  /// [sig] is waived — an unsigned version the group's policy accepts
  /// (§6.4, §10.1). Only the `unsigned` verdict is ever waived (the future
  /// clock is checked first).
  bool _unsignedWaived(
    GroupPolicyInfo? info,
    RecordSignature? sig,
    Verdict v,
    int at, {
    bool meta = false,
  }) {
    if (info == null || sig != null || v.reason != RejectReason.unsigned) {
      return false;
    }
    switch (info.policy) {
      case GroupPolicy.linkOnly:
        return _linkPath;
      case GroupPolicy.mixed:
        return !meta;
      case GroupPolicy.matrix:
        final lockedAt = info.lockedAt;
        return !meta && lockedAt != null && at <= lockedAt;
    }
  }

  /// G52 §6.1 / §6.4 + G53 §10.1: the claim rules for participant version
  /// [m] ([current] = the stored one) wherever unsigned versions may be
  /// accepted (link path; mixed / locked groups on the Matrix path).
  Future<String?> _claimProblem(
    GroupPolicyInfo? info,
    MemberModel m,
    MemberModel? current,
  ) async {
    if (info == null) return null;
    final linkish =
        _linkPath || info.policy == GroupPolicy.mixed || info.lockedAt != null;
    if (!linkish) return null;
    if (m.sig == null) {
      if (m.matrixId != null) {
        return 'unsigned Matrix-ID claim in a link group';
      }
      if (current?.matrixId != null) {
        return 'unsigned change of a claimed participant';
      }
      return null;
    }
    // Signed versions over Matrix: the sender gate decides (unchanged).
    if (!_linkPath || m.matrixId == null) return null;
    if (info.policy == GroupPolicy.matrix) return null; // G6 as usual
    if (_isSelfClaim(m, current)) return null;
    if (info.policy == GroupPolicy.linkOnly) {
      return 'Matrix-ID claim in a link group';
    }
    // mixed: a member may assign a Matrix account (an invite).
    final signer = m.sig!.user;
    final people = await members.getMembers(m.groupId);
    final signerActive = people.any((p) => p.isActive && p.matrixId == signer);
    return signerActive ? null : 'claim by a non-member';
  }

  /// G53 §10.1: [m] claims a stored, active participant for the Matrix
  /// account that signed it, and nobody else claims it yet (or the same
  /// account does already — a later version of its own claim).
  static bool _isSelfClaim(MemberModel m, MemberModel? current) {
    final sig = m.sig;
    if (sig == null || m.matrixId == null || sig.user != m.matrixId) {
      return false;
    }
    if (current == null || !current.isActive || !m.isActive) return false;
    return current.matrixId == null || current.matrixId == m.matrixId;
  }

  /// The `by` hint is kept only for link-path and restored versions — G53:
  /// and for an unsigned version a mixed / locked group accepts ([waived]).
  bool _keepsLinkAuthor(bool waived) => _linkPath || acceptUnsigned || waived;

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
    final policy = await _policyOf(e.roomId);
    final v = await verifier.expense(e, stored: stored);
    if (!_isAlive()) return false;
    final viaLink = _unsignedWaived(policy, e.sig, v, e.updatedAt);
    if (!v.accepted && !viaLink && !_legacyOk(e.sig, v)) {
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
        : viaLink
        ? expenseCompanion(e.asLinkVersion(e.linkAuthor))
        : expenseCompanion(
            e.withSigning(),
          ).copyWith(updatedAt: Value(_clamp(e.updatedAt)));
    await expenses.upsertExpenseLww(
      _keepsLinkAuthor(viaLink)
          ? row
          : row.copyWith(linkAuthor: const Value(null)),
      source: _historySource,
    );
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
    final policy = await _policyOf(s.roomId);
    final v = await verifier.settlement(s, stored: stored);
    if (!_isAlive()) return false;
    final viaLink = _unsignedWaived(policy, s.sig, v, s.updatedAt);
    if (!v.accepted && !viaLink && !_legacyOk(s.sig, v)) {
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
        : viaLink
        ? settlementCompanion(s.asLinkVersion(s.linkAuthor))
        : settlementCompanion(
            s.withSigning(),
          ).copyWith(updatedAt: Value(_clamp(s.updatedAt)));
    await expenses.upsertSettlementLww(
      _keepsLinkAuthor(viaLink)
          ? row
          : row.copyWith(linkAuthor: const Value(null)),
      source: _historySource,
    );
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
    final policy = await _policyOf(m.groupId);
    if (!_isAlive()) return false;
    final problem =
        memberProblem(m, allowLocalClaim: allowLocalClaims) ??
        await _claimProblem(policy, m, current);
    if (!_isAlive()) return false;
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
    final viaLink = _unsignedWaived(policy, m.sig, v, m.updatedAt);
    if (!v.accepted && !viaLink && !_legacyOk(m.sig, v)) {
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
    final row = v.accepted || viaLink
        ? memberCompanion(m)
        : memberCompanion(m).copyWith(updatedAt: Value(_clamp(m.updatedAt)));
    await members.upsertMemberLww(
      _keepsLinkAuthor(viaLink)
          ? row
          : row.copyWith(linkAuthor: const Value(null)),
      source: _historySource,
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
    final problem =
        groupMetaProblem(g) ??
        (g.sig == null && (g.link != null || g.lockedAt != null)
            ? 'unsigned link state'
            : null);
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
    final policy = await _policyOf(g.roomId);
    final v = await verifier.meta(g);
    if (!_isAlive()) return false;
    final viaLink = _unsignedWaived(policy, g.sig, v, g.updatedAt, meta: true);
    if (!v.accepted && !viaLink && !_legacyOk(g.sig, v)) {
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
    final row = v.accepted || viaLink
        ? groupCompanion(g)
        : groupCompanion(g).copyWith(updatedAt: Value(_clamp(g.updatedAt)));
    await groups.upsertGroupLww(
      _keepsLinkAuthor(viaLink)
          ? row
          : row.copyWith(linkAuthor: const Value(null)),
      source: _historySource,
    );
    await _clearRefusal(g.roomId, RecordKind.meta, g.roomId, version);
    // G53: a link was opened (or replaced) — versions refused for being
    // unsigned before are acceptable now; let peers re-send them.
    final link = g.link;
    if (link != null && g.sig != null && stored?.link?.secret != link.secret) {
      if (!_isAlive()) return true;
      await signing.clearUnsignedRefusals(g.roomId);
    }
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
