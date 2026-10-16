import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../models/member_model.dart';
import '../expenses/expenses_provider.dart';
import 'ledger_csv.dart';

part 'csv_import.g.dart';

/// Imports a per-group CSV produced by [buildGroupCsv] back into the local DB.
///
/// Merge semantics (Phase D): the group is resolved by `Group ID` (created if
/// absent), participants are resolved **by display name** (an unknown name
/// becomes a new local participant), and each expense is **LWW-upserted by id**
/// using the row's `Updated At` clock — so re-importing a backup is idempotent
/// and merging into an existing group lets the newer copy win.
@riverpod
class CsvImporter extends _$CsvImporter {
  @override
  FutureOr<void> build() {}

  /// Imports [csv]; returns the number of expense rows written. On failure the
  /// notifier state carries the error.
  Future<int> importCsv(String csv) async {
    state = const AsyncLoading();
    var count = 0;
    state = await AsyncValue.guard(() async {
      count = await _doImport(csv);
    });
    return count;
  }

  Future<int> _doImport(String csv) async {
    final parsed = parseGroupCsv(csv);
    if (parsed.rows.isEmpty && parsed.participantNames.isEmpty) return 0;

    final groupsDao = ref.read(groupsDaoProvider);
    final membersDao = ref.read(membersDaoProvider);
    final expensesDao = ref.read(expensesDaoProvider);
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1) Ensure the group. New id when the CSV carries none; never clobber an
    //    existing group's meta (LWW upsert only creates it when absent).
    final groupId = parsed.groupId ?? const Uuid().v7();
    final existing = await groupsDao.getGroup(groupId);
    if (existing == null) {
      final currency = parsed.rows.isNotEmpty
          ? parsed.rows.first.currency
          : 'EUR';
      await groupsDao.upsertGroupLww(
        GroupsCompanion(
          roomId: Value(groupId),
          name: Value(parsed.groupName ?? 'Imported group'),
          currency: Value(currency),
          updatedAt: Value(now),
        ),
      );
    }

    // 2) Resolve every referenced name to a participant id, creating local
    //    participants for names not already in the group (matched by name).
    final members = await membersDao.getMembers(groupId);
    final pidByName = <String, String>{};
    for (final m in members) {
      pidByName.putIfAbsent(_label(m), () => m.userId);
    }
    final names = <String>{
      ...parsed.participantNames,
      for (final r in parsed.rows) r.paidByName,
    }..removeWhere((n) => n.isEmpty);
    for (final name in names) {
      if (pidByName.containsKey(name)) continue;
      final pid = const Uuid().v7();
      await membersDao.upsertMemberLww(
        MembersCompanion(
          groupId: Value(groupId),
          userId: Value(pid),
          displayName: Value(name),
          status: const Value('active'),
          updatedAt: Value(now),
        ),
      );
      pidByName[name] = pid;
    }

    // 3) LWW-upsert each expense by id.
    var count = 0;
    for (final row in parsed.rows) {
      final id = row.id ?? const Uuid().v7();
      final splits = <String, int>{
        for (final e in row.sharesByName.entries)
          if (pidByName[e.key] != null) pidByName[e.key]!: e.value,
      };
      await expensesDao.upsertExpenseLww(
        ExpensesCompanion(
          id: Value(id),
          roomId: Value(groupId),
          description: Value(row.description),
          amountCents: Value(row.amountCents),
          currency: Value(row.currency),
          paidBy: Value(pidByName[row.paidByName] ?? row.paidByName),
          splitsJson: Value(jsonEncode(splits)),
          createdAt: Value(row.createdAt),
          updatedAt: Value(row.updatedAt),
          deleted: const Value(false),
        ),
      );
      count++;
    }
    return count;
  }

  static String _label(MemberModel m) =>
      m.displayName.isNotEmpty ? m.displayName : (m.matrixId ?? m.userId);
}
