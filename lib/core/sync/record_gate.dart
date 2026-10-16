import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/record_signature.dart';
import '../database/daos/expenses_dao.dart';
import '../database/daos/groups_dao.dart';
import '../database/daos/members_dao.dart';
import '../database/daos/signing_dao.dart';
import 'ledger_payloads.dart';
import 'record_signing.dart';
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
/// 2. Not newer than a version we already refused → dropped silently (by
///    clock only: a refusal at `T` also blocks other versions stamped `T`).
/// 3. [RecordVerifier] decides; a refused version is logged and — for the
///    recorded reasons — stored in `rejected_versions`, so our digest tells
///    peers to stop re-sending it (no repair loop).
/// 4. Accepted → LWW upsert with its `sig` / `origin` (the clock is never
///    clamped: the verifier already refused clocks too far in the future).
///
/// [acceptUnsigned] is for a user-started **backup restore** only: an
/// unsigned record (a pre-G6 row in the user's own backup) is stored as
/// legacy instead of refused. Bad signatures are refused there as well.
class RecordGate {
  RecordGate({
    required this.verifier,
    required this.signing,
    required this.groups,
    required this.members,
    required this.expenses,
    this.acceptUnsigned = false,
    bool Function()? isAlive,
    this.onRefused,
  }) : _isAlive = isAlive ?? (() => true);

  final RecordVerifier verifier;
  final SigningDao signing;
  final GroupsDao groups;
  final MembersDao members;
  final ExpensesDao expenses;
  final bool acceptUnsigned;
  final bool Function() _isAlive;

  /// Called for every refused version (after logging) — the syncer uses it
  /// to surface refused **unsigned** (pre-G6) records to the user (G35).
  final void Function(
    String groupId,
    RecordKind kind,
    RejectReason reason,
    String relayedBy,
  )?
  onRefused;

  /// Clamp for the unsigned (restored legacy) clocks — same bound as
  /// `LedgerSyncer.clampInboundClock`.
  int _clamp(int t) {
    final ceiling =
        DateTime.now().millisecondsSinceEpoch +
        kSignedClockSkewTolerance.inMilliseconds;
    return t > ceiling ? ceiling : t;
  }

  Future<bool> _refusedBefore(
    String group,
    RecordKind kind,
    String id,
    int updatedAt,
  ) async {
    final rej = await signing.rejectedClock(group, kind.wire, id);
    return rej != null && updatedAt <= rej;
  }

  /// Whether to store an unsigned version anyway (restore only).
  bool _legacyOk(RecordSignature? sig, Verdict v) =>
      acceptUnsigned && sig == null && v.reason == RejectReason.unsigned;

  Future<void> _refuse(
    String group,
    RecordKind kind,
    String id,
    int updatedAt,
    Verdict v,
    String relayedBy,
    RecordSignature? sig,
  ) async {
    final reason = v.reason!;
    debugPrint(
      '[g6] refused ${kind.wire} $id@$updatedAt in $group '
      '(${reason.wire}, via $relayedBy, signer ${sig?.user}/${sig?.device})',
    );
    onRefused?.call(group, kind, reason, relayedBy);
    if (!reason.recorded || !_isAlive()) return;
    await signing.recordRejected(
      RefusedVersion(
        groupId: group,
        kind: kind.wire,
        recordId: id,
        updatedAt: updatedAt,
        reason: reason.wire,
        relayedBy: relayedBy,
        claimedSigner: sig?.user,
      ),
    );
  }

  /// An inbound expense payload. Returns whether it was stored.
  Future<bool> expense(
    Map<String, dynamic> content, {
    required String relayedBy,
  }) async {
    final e = expenseFromPayload(content);
    if (e == null) return false;
    final stored = await expenses.getExpenseById(e.id);
    if (!_isAlive()) return false;
    if (stored != null &&
        !versionWins(expenseVersion(e), expenseVersion(stored))) {
      return false;
    }
    if (await _refusedBefore(e.roomId, RecordKind.expense, e.id, e.updatedAt)) {
      return false;
    }
    final v = await verifier.expense(e, stored: stored);
    if (!_isAlive()) return false;
    if (!v.accepted && !_legacyOk(e.sig, v)) {
      await _refuse(
        e.roomId,
        RecordKind.expense,
        e.id,
        e.updatedAt,
        v,
        relayedBy,
        e.sig,
      );
      return false;
    }
    final row = expenseCompanion(e);
    await expenses.upsertExpenseLww(
      v.accepted ? row : row.copyWith(updatedAt: Value(_clamp(e.updatedAt))),
    );
    return true;
  }

  Future<bool> settlement(
    Map<String, dynamic> content, {
    required String relayedBy,
  }) async {
    final s = settlementFromPayload(content);
    if (s == null) return false;
    final stored = await expenses.getSettlementById(s.id);
    if (!_isAlive()) return false;
    if (stored != null &&
        !versionWins(settlementVersion(s), settlementVersion(stored))) {
      return false;
    }
    if (await _refusedBefore(
      s.roomId,
      RecordKind.settlement,
      s.id,
      s.updatedAt,
    )) {
      return false;
    }
    final v = await verifier.settlement(s, stored: stored);
    if (!_isAlive()) return false;
    if (!v.accepted && !_legacyOk(s.sig, v)) {
      await _refuse(
        s.roomId,
        RecordKind.settlement,
        s.id,
        s.updatedAt,
        v,
        relayedBy,
        s.sig,
      );
      return false;
    }
    final row = settlementCompanion(s);
    await expenses.upsertSettlementLww(
      v.accepted ? row : row.copyWith(updatedAt: Value(_clamp(s.updatedAt))),
    );
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
    final current = (await members.getMembers(
      m.groupId,
    )).where((x) => x.userId == m.userId).firstOrNull;
    if (!_isAlive()) return false;
    if (current != null &&
        !versionWins(memberVersion(m), memberVersion(current))) {
      return false;
    }
    if (await _refusedBefore(
      m.groupId,
      RecordKind.member,
      m.userId,
      m.updatedAt,
    )) {
      return false;
    }
    final v = await verifier.member(m, requiredSigner: requiredSigner);
    if (!_isAlive()) return false;
    if (!v.accepted && !_legacyOk(m.sig, v)) {
      await _refuse(
        m.groupId,
        RecordKind.member,
        m.userId,
        m.updatedAt,
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
    return true;
  }

  /// A group-meta version (a `group` payload or a bootstrap's `meta`).
  Future<bool> meta(
    Map<String, dynamic> content, {
    required String relayedBy,
  }) async {
    final g = groupMetaFromPayload(content);
    if (g == null) return false;
    final stored = await groups.getGroup(g.roomId);
    if (!_isAlive()) return false;
    if (stored != null &&
        !versionWins(groupMetaVersion(g), groupMetaVersion(stored))) {
      return false;
    }
    if (await _refusedBefore(
      g.roomId,
      RecordKind.meta,
      g.roomId,
      g.updatedAt,
    )) {
      return false;
    }
    final v = await verifier.meta(g);
    if (!_isAlive()) return false;
    if (!v.accepted && !_legacyOk(g.sig, v)) {
      await _refuse(
        g.roomId,
        RecordKind.meta,
        g.roomId,
        g.updatedAt,
        v,
        relayedBy,
        g.sig,
      );
      return false;
    }
    final row = groupCompanion(g);
    await groups.upsertGroupLww(
      v.accepted ? row : row.copyWith(updatedAt: Value(_clamp(g.updatedAt))),
    );
    return true;
  }

  /// A whole-group snapshot (bootstrap / restored backup group): the signed
  /// meta, then every member, expense and settlement — each verified on its
  /// own, so one bad record doesn't sink the snapshot.
  ///
  /// [trustAttestations]: store the snapshot's `device_keys` as vouched-for
  /// keys first — only for a sender we trust with the whole group anyway (a
  /// new group's inviter, our own devices) or a restore the user started.
  ///
  /// A group we don't know yet is only created when its meta verifies;
  /// otherwise the snapshot is dropped as a whole (no orphan rows).
  Future<void> snapshot(
    Map<String, dynamic> content, {
    required String relayedBy,
    required bool trustAttestations,
  }) async {
    final groupId = content['group'];
    if (groupId is! String) return;
    if (trustAttestations) {
      await signing.pinAttestedKeys(
        parseDeviceKeys(content['device_keys']),
        relayedBy,
      );
      if (!_isAlive()) return;
    }
    final metaContent = content['meta'] is Map
        ? Map<String, dynamic>.from(content['meta'] as Map)
        : {
            'group': groupId,
            'name': content['name'],
            'currency': content['currency'],
            'updated_at': content['updated_at'],
          };
    await meta(metaContent, relayedBy: relayedBy);
    if (!_isAlive()) return;
    if (await groups.getGroup(groupId) == null) {
      debugPrint('[g6] dropped snapshot of $groupId: group meta refused');
      return;
    }
    for (final m in (content['members'] as List? ?? const [])) {
      if (!_isAlive()) return;
      await member(Map<String, dynamic>.from(m as Map), relayedBy: relayedBy);
    }
    for (final e in (content['expenses'] as List? ?? const [])) {
      if (!_isAlive()) return;
      await expense(Map<String, dynamic>.from(e as Map), relayedBy: relayedBy);
    }
    for (final s in (content['settlements'] as List? ?? const [])) {
      if (!_isAlive()) return;
      await settlement(
        Map<String, dynamic>.from(s as Map),
        relayedBy: relayedBy,
      );
    }
  }
}
