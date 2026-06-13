import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/members_dao.dart';
import 'ledger_csv.dart';

/// Reads a group's meta, participants and expenses from Drift and renders the
/// human-readable per-group CSV (see [buildGroupCsv]). Returns an empty string
/// if the group doesn't exist. The DB read is the testable seam; the file
/// save/share around it lives in the UI layer.
Future<String> buildGroupCsvForExport(
  GroupsDao groupsDao,
  MembersDao membersDao,
  ExpensesDao expensesDao,
  String groupId,
) async {
  final group = await groupsDao.getGroup(groupId);
  if (group == null) return '';
  final members = await membersDao.getMembers(groupId);
  final expenses = await expensesDao.getAllExpensesForGroup(groupId);
  return buildGroupCsv(group, members, expenses);
}

/// A filesystem-friendly file name for a group's CSV export.
String csvFileName(String groupName) {
  final safe = groupName.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
  return '${safe.isEmpty ? 'group' : safe}.csv';
}
