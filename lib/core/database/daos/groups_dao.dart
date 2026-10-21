import 'dart:convert';

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../../models/expense_category.dart';
import '../../../models/group_model.dart';
import '../../../models/record_signature.dart';
import '../../sync/ledger_payloads.dart';
import '../../sync/record_signing.dart' show RecordKind;
import '../../sync/record_version.dart';
import 'history_dao.dart';

part 'groups_dao.g.dart';

@DriftAccessor(tables: [Groups])
class GroupsDao extends DatabaseAccessor<AppDatabase> with _$GroupsDaoMixin {
  GroupsDao(super.db);

  Stream<List<GroupModel>> watchAllGroups() =>
      select(groups).watch().map((rows) => rows.map(_toModel).toList());

  Future<List<GroupModel>> getAllGroups() =>
      select(groups).get().then((rows) => rows.map(_toModel).toList());

  /// Last-writer-wins upsert with the G27 tie-break (same rule as
  /// `ExpensesDao.upsertExpenseLww`): skipped only when the stored meta is a
  /// newer version (higher clock, or same clock + higher content hash).
  /// G48: a different stored version is appended to `record_history`.
  Future<void> upsertGroupLww(
    GroupsCompanion group, {
    HistorySource source = HistorySource.local,
  }) => transaction(() async {
    final old = await (select(
      groups,
    )..where((t) => t.roomId.equals(group.roomId.value))).getSingleOrNull();
    final version = groupMetaVersion(
      GroupModel(
        roomId: group.roomId.value,
        name: group.name.present ? group.name.value : '',
        currency: group.currency.present ? group.currency.value : '',
        updatedAt: group.updatedAt.value,
        categories: group.categoriesJson.present
            ? decodeCategories(group.categoriesJson.value)
            : const [],
        link: group.linkSecret.present
            ? linkFromColumns(group.linkEpoch.value, group.linkSecret.value)
            : null,
        lockedAt: group.lockedAt.present ? group.lockedAt.value : null,
      ),
    );
    final oldVersion = old == null ? null : groupMetaVersion(_toModel(old));
    if (oldVersion != null && compareVersions(version, oldVersion) < 0) {
      return;
    }
    await into(groups).insertOnConflictUpdate(group);
    if (oldVersion != null && compareVersions(version, oldVersion) == 0) {
      return;
    }
    final stored = _toModel(
      await (select(
        groups,
      )..where((t) => t.roomId.equals(group.roomId.value))).getSingle(),
    );
    await appendRecordHistory(
      attachedDatabase,
      groupId: stored.roomId,
      kind: RecordKind.meta,
      recordId: stored.roomId,
      version: groupMetaVersion(stored),
      content: groupMetaPayload(stored),
      source: source,
    );
  });

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
    categories: decodeCategories(g.categoriesJson),
    link: linkFromColumns(g.linkEpoch, g.linkSecret),
    lockedAt: g.lockedAt,
    sig: RecordSignature.decode(g.sig),
    pendingSign: g.pendingSign,
    linkAuthor: g.linkAuthor,
  );
}

/// G53: the stored `link_epoch` / `link_secret` (no secret → no link).
GroupLink? linkFromColumns(int? epoch, String? secret) =>
    secret == null ? null : GroupLink(epoch: epoch ?? 0, secret: secret);

/// G47: the stored `categories_json` (NULL / unreadable → none).
List<CustomCategory> decodeCategories(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    return parseCustomCategories(jsonDecode(json));
  } catch (_) {
    return const [];
  }
}

/// G47: [categories] as stored (none → NULL).
String? encodeCategories(List<CustomCategory> categories) => categories.isEmpty
    ? null
    : jsonEncode([for (final c in categories) c.toJson()]);

/// A fully-populated companion for an LWW upsert of [g] (G6 fields included).
GroupsCompanion groupCompanion(GroupModel g) => GroupsCompanion(
  roomId: Value(g.roomId),
  name: Value(g.name),
  currency: Value(g.currency),
  updatedAt: Value(g.updatedAt),
  categoriesJson: Value(encodeCategories(g.categories)),
  sig: Value(g.sig?.encode()),
  pendingSign: Value(g.pendingSign),
  // G52: always set (also to null) — an absent value would keep the
  // previous version's hint on update.
  linkAuthor: Value(g.linkAuthor),
  // G53: always set (also to null) — a lock must clear the link.
  linkEpoch: Value(g.link?.epoch),
  linkSecret: Value(g.link?.secret),
  lockedAt: Value(g.lockedAt),
);
