import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../../models/group_model.dart';
import '../../../models/record_signature.dart';

part 'groups_dao.g.dart';

@DriftAccessor(tables: [Groups])
class GroupsDao extends DatabaseAccessor<AppDatabase> with _$GroupsDaoMixin {
  GroupsDao(super.db);

  Stream<List<GroupModel>> watchAllGroups() =>
      select(groups).watch().map((rows) => rows.map(_toModel).toList());

  Future<List<GroupModel>> getAllGroups() =>
      select(groups).get().then((rows) => rows.map(_toModel).toList());

  /// Last-writer-wins upsert: writes only when no existing row has a newer
  /// [Groups.updatedAt]. The companion must set `updatedAt`. Lets concurrent
  /// renames/currency changes converge deterministically across devices.
  Future<void> upsertGroupLww(GroupsCompanion group) => into(groups).insert(
    group,
    onConflict: DoUpdate(
      (_) => group,
      where: (old) =>
          old.updatedAt.isSmallerOrEqualValue(group.updatedAt.value),
    ),
  );

  Future<GroupModel?> getGroup(String roomId) =>
      (select(groups)..where((t) => t.roomId.equals(roomId)))
          .getSingleOrNull()
          .then((row) => row == null ? null : _toModel(row));

  Future<void> deleteGroup(String roomId) =>
      (delete(groups)..where((t) => t.roomId.equals(roomId))).go();

  static GroupModel _toModel(Group g) => GroupModel(
    roomId: g.roomId,
    name: g.name,
    currency: g.currency,
    updatedAt: g.updatedAt,
    sig: RecordSignature.decode(g.sig),
    pendingSign: g.pendingSign,
  );
}

/// A fully-populated companion for an LWW upsert of [g] (G6 fields included).
GroupsCompanion groupCompanion(GroupModel g) => GroupsCompanion(
  roomId: Value(g.roomId),
  name: Value(g.name),
  currency: Value(g.currency),
  updatedAt: Value(g.updatedAt),
  sig: Value(g.sig?.encode()),
  pendingSign: Value(g.pendingSign),
);
