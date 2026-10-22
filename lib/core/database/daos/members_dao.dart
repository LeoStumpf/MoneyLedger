import 'dart:convert';

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../../models/member_model.dart';
import '../../../models/payment_details.dart';
import '../../../models/record_signature.dart';
import '../../sync/record_validation.dart' show isValidMxid;
import '../../sync/ledger_payloads.dart';
import '../../sync/record_signing.dart' show RecordKind;
import '../../sync/record_version.dart';
import 'history_dao.dart';

part 'members_dao.g.dart';

@DriftAccessor(tables: [Members])
class MembersDao extends DatabaseAccessor<AppDatabase> with _$MembersDaoMixin {
  MembersDao(super.db);

  Stream<List<MemberModel>> watchMembers(String groupId) =>
      (select(members)..where((t) => t.groupId.equals(groupId))).watch().map(
        (rows) => rows.map(_toModel).toList(),
      );

  /// Every participant of every group — for cross-group views (G5 nudge).
  Stream<List<MemberModel>> watchAllMembers() =>
      select(members).watch().map((rows) => rows.map(_toModel).toList());

  /// G72: whether some group has an active participant claimed by another
  /// Matrix account than [me] (a group shared over Matrix) — the moment the
  /// notification permission is worth asking for.
  Stream<bool> watchHasOtherClaimedMember(String me) =>
      (select(members)..where(
            (t) =>
                t.status.equals('active') &
                t.matrixId.isNotNull() &
                t.matrixId.equals(me).not() &
                // Only Matrix IDs — not local mode's `local:self`.
                t.matrixId.like('@%:%'),
          ))
          .watch()
          .map((rows) => rows.any((r) => isValidMxid(r.matrixId)))
          .distinct();

  /// Participant ids of the group's currently-active participants. NOTE: these
  /// are participant ids, not necessarily MXIDs — use [activeClaimedMatrixIds]
  /// for replication targets.
  Future<List<String>> activeMemberIds(String groupId) =>
      (select(members)..where(
            (t) => t.groupId.equals(groupId) & t.status.equals('active'),
          ))
          .get()
          .then((rows) => rows.map((r) => r.userId).toList());

  /// Matrix IDs of the active, **claimed** participants — i.e. the reachable
  /// to-device sync targets. Pure-local participants (no [matrixId]) are
  /// skipped; they are ledger data only. G18 review 2: so is a claim that
  /// isn't a valid MXID (e.g. local mode's `local:self`) — it never becomes
  /// a send target / device-key lookup.
  Future<List<String>> activeClaimedMatrixIds(String groupId) =>
      (select(members)..where(
            (t) =>
                t.groupId.equals(groupId) &
                t.status.equals('active') &
                t.matrixId.isNotNull(),
          ))
          .get()
          .then(
            (rows) => [
              for (final r in rows)
                if (isValidMxid(r.matrixId)) r.matrixId!,
            ],
          );

  /// The participant in [groupId] claimed by [matrixId], if any. Tolerates
  /// duplicate claims left by the pre-G26 re-add bug (prefers active, then
  /// newest — see [claimedBy]) instead of throwing.
  Future<MemberModel?> memberByMatrixId(String groupId, String matrixId) =>
      (select(members)..where(
            (t) => t.groupId.equals(groupId) & t.matrixId.equals(matrixId),
          ))
          .get()
          .then((rows) => claimedBy(rows.map(_toModel), matrixId));

  Future<List<MemberModel>> getMembers(String groupId) =>
      (select(members)..where((t) => t.groupId.equals(groupId))).get().then(
        (rows) => rows.map(_toModel).toList(),
      );

  /// Last-writer-wins upsert with the G27 tie-break (same rule as
  /// `ExpensesDao.upsertExpenseLww`): skipped only when the stored
  /// participant is a newer version (higher clock, or same clock + higher
  /// content hash). Lets concurrent add/remove of the same member converge
  /// deterministically across devices.
  ///
  /// G48: a different stored version is appended to `record_history`.
  Future<void> upsertMemberLww(
    MembersCompanion member, {
    HistorySource source = HistorySource.local,
  }) => transaction(() async {
    SimpleSelectStatement<$MembersTable, Member> row() =>
        select(members)..where(
          (t) =>
              t.groupId.equals(member.groupId.value) &
              t.userId.equals(member.userId.value),
        );
    final old = await row().getSingleOrNull();
    final version = memberVersion(
      MemberModel(
        groupId: member.groupId.value,
        userId: member.userId.value,
        displayName: member.displayName.present ? member.displayName.value : '',
        matrixId: member.matrixId.present ? member.matrixId.value : null,
        status: member.status.present ? member.status.value : 'active',
        updatedAt: member.updatedAt.value,
        payment: member.paymentJson.present
            ? decodePayment(member.paymentJson.value)
            : null,
      ),
    );
    final oldVersion = old == null ? null : memberVersion(_toModel(old));
    if (oldVersion != null && compareVersions(version, oldVersion) < 0) {
      return;
    }
    await into(members).insertOnConflictUpdate(member);
    if (oldVersion != null && compareVersions(version, oldVersion) == 0) {
      return;
    }
    final stored = _toModel(await row().getSingle());
    await appendRecordHistory(
      attachedDatabase,
      groupId: stored.groupId,
      kind: RecordKind.member,
      recordId: stored.userId,
      version: memberVersion(stored),
      content: memberPayload(stored),
      source: source,
    );
  });

  static MemberModel _toModel(Member m) => MemberModel(
    groupId: m.groupId,
    userId: m.userId,
    displayName: m.displayName,
    matrixId: m.matrixId,
    status: m.status,
    updatedAt: m.updatedAt,
    sig: RecordSignature.decode(m.sig),
    pendingSign: m.pendingSign,
    linkAuthor: m.linkAuthor,
    payment: decodePayment(m.paymentJson),
  );
}

/// G74: the stored `payment_json` (NULL → none; unreadable → an invalid
/// entry, like a malformed wire value).
PaymentDetails? decodePayment(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    return PaymentDetails.fromWire(jsonDecode(json));
  } catch (_) {
    return PaymentDetails.invalid;
  }
}

/// G74: [p] as stored (none → NULL).
String? encodePayment(PaymentDetails? p) =>
    p == null ? null : jsonEncode(p.toJson());

/// Maps a [MemberModel] to a fully-populated companion (all columns set) for an
/// LWW upsert.
MembersCompanion memberCompanion(MemberModel m) => MembersCompanion(
  groupId: Value(m.groupId),
  userId: Value(m.userId),
  displayName: Value(m.displayName),
  matrixId: Value(m.matrixId),
  status: Value(m.status),
  updatedAt: Value(m.updatedAt),
  sig: Value(m.sig?.encode()),
  pendingSign: Value(m.pendingSign),
  // G52: always set (also to null) — an absent value would keep the
  // previous version's hint on update.
  linkAuthor: Value(m.linkAuthor),
  // G74: always set (also to null) — removing the details must clear them.
  paymentJson: Value(encodePayment(m.payment)),
);
