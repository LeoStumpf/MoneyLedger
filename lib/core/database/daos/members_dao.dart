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

  /// MXIDs of the group's currently-active members (for relaying changes).
  Future<List<String>> activeMemberIds(String groupId) => (select(members)
        ..where((t) => t.groupId.equals(groupId) & t.status.equals('active')))
      .get()
      .then((rows) => rows.map((r) => r.userId).toList());

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
        status: m.status,
        updatedAt: m.updatedAt,
      );
}
