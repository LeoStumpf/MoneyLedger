import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../../models/member_model.dart';
import '../../../models/record_signature.dart';
import '../../sync/record_validation.dart' show isValidMxid;
import '../../sync/record_version.dart';

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
  Future<void> upsertMemberLww(MembersCompanion member) =>
      transaction(() async {
        final old =
            await (select(members)..where(
                  (t) =>
                      t.groupId.equals(member.groupId.value) &
                      t.userId.equals(member.userId.value),
                ))
                .getSingleOrNull();
        if (old != null &&
            compareVersions(
                  memberVersion(
                    MemberModel(
                      groupId: member.groupId.value,
                      userId: member.userId.value,
                      displayName: member.displayName.present
                          ? member.displayName.value
                          : '',
                      matrixId: member.matrixId.present
                          ? member.matrixId.value
                          : null,
                      status: member.status.present
                          ? member.status.value
                          : 'active',
                      updatedAt: member.updatedAt.value,
                    ),
                  ),
                  memberVersion(_toModel(old)),
                ) <
                0) {
          return;
        }
        await into(members).insertOnConflictUpdate(member);
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
  );
}

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
);
