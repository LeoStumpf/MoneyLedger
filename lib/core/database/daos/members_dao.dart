import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../../models/member_model.dart';

part 'members_dao.g.dart';

@DriftAccessor(tables: [Members])
class MembersDao extends DatabaseAccessor<AppDatabase> with _$MembersDaoMixin {
  MembersDao(super.db);

  Stream<List<MemberModel>> watchMembers(String groupId) =>
      (select(members)..where((t) => t.groupId.equals(groupId)))
          .watch()
          .map((rows) => rows.map(_toModel).toList());

  /// Participant ids of the group's currently-active participants. NOTE: these
  /// are participant ids, not necessarily MXIDs — use [activeClaimedMatrixIds]
  /// for replication targets.
  Future<List<String>> activeMemberIds(String groupId) => (select(members)
        ..where((t) => t.groupId.equals(groupId) & t.status.equals('active')))
      .get()
      .then((rows) => rows.map((r) => r.userId).toList());

  /// Matrix IDs of the active, **claimed** participants — i.e. the reachable
  /// to-device sync targets. Pure-local participants (no [matrixId]) are
  /// skipped; they are ledger data only.
  Future<List<String>> activeClaimedMatrixIds(String groupId) =>
      (select(members)
            ..where((t) =>
                t.groupId.equals(groupId) &
                t.status.equals('active') &
                t.matrixId.isNotNull()))
          .get()
          .then((rows) => rows.map((r) => r.matrixId!).toList());

  /// The participant in [groupId] claimed by [matrixId], if any. Tolerates
  /// duplicate claims left by the pre-G26 re-add bug (prefers active, then
  /// newest — see [claimedBy]) instead of throwing.
  Future<MemberModel?> memberByMatrixId(String groupId, String matrixId) =>
      (select(members)
            ..where(
                (t) => t.groupId.equals(groupId) & t.matrixId.equals(matrixId)))
          .get()
          .then((rows) => claimedBy(rows.map(_toModel), matrixId));

  Future<List<MemberModel>> getMembers(String groupId) =>
      (select(members)..where((t) => t.groupId.equals(groupId)))
          .get()
          .then((rows) => rows.map(_toModel).toList());

  /// Last-writer-wins upsert: writes only when no existing row has a newer
  /// [updatedAt]. Lets concurrent add/remove of the same member converge
  /// deterministically across devices.
  Future<void> upsertMemberLww(MembersCompanion member) =>
      into(members).insert(
        member,
        onConflict: DoUpdate(
          (_) => member,
          where: (old) =>
              old.updatedAt.isSmallerOrEqualValue(member.updatedAt.value),
        ),
      );

  static MemberModel _toModel(Member m) => MemberModel(
        groupId: m.groupId,
        userId: m.userId,
        displayName: m.displayName,
        matrixId: m.matrixId,
        status: m.status,
        updatedAt: m.updatedAt,
      );
}
