import 'package:drift/drift.dart';
import '../app_database.dart';

part 'groups_dao.g.dart';

@DriftAccessor(tables: [Groups])
class GroupsDao extends DatabaseAccessor<AppDatabase> with _$GroupsDaoMixin {
  GroupsDao(super.db);

  Future<List<Group>> allGroups() => select(groups).get();

  Stream<List<Group>> watchAllGroups() => select(groups).watch();

  Future<void> upsertGroup(GroupsCompanion group) =>
      into(groups).insertOnConflictUpdate(group);

  Future<void> deleteGroup(String roomId) =>
      (delete(groups)..where((t) => t.roomId.equals(roomId))).go();
}
