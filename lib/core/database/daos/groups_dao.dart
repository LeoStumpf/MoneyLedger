import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../../models/group_model.dart';

part 'groups_dao.g.dart';

@DriftAccessor(tables: [Groups])
class GroupsDao extends DatabaseAccessor<AppDatabase> with _$GroupsDaoMixin {
  GroupsDao(super.db);

  Stream<List<GroupModel>> watchAllGroups() =>
      select(groups).watch().map((rows) => rows.map(_toModel).toList());

  Future<void> upsertGroup(GroupsCompanion group) =>
      into(groups).insertOnConflictUpdate(group);

  Future<void> deleteGroup(String roomId) =>
      (delete(groups)..where((t) => t.roomId.equals(roomId))).go();

  static GroupModel _toModel(Group g) =>
      GroupModel(roomId: g.roomId, name: g.name, currency: g.currency);
}
