import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/expense_model.dart';
import '../../models/member_model.dart';
import '../balance/balance_calculator.dart';
import '../expenses/expenses_provider.dart';
import 'group_provider.dart';

part 'group_overview_provider.g.dart';

/// What the group card (groups list) and the group's summary card show (G17).
class GroupOverview {
  /// Active participants, in DB order.
  final List<MemberModel> members;

  /// This account's participant in the group, if it has claimed one.
  final MemberModel? me;

  /// My non-zero net balance per currency (sorted): > 0 I am owed, < 0 I owe.
  /// Empty = settled up (or not a participant).
  final Map<String, int> myBalance;

  /// Newest `createdAt` of a live expense / settlement, null if none.
  final int? lastActivityAt;

  /// Number of live expenses + settlements.
  final int recordCount;

  const GroupOverview({
    required this.members,
    required this.me,
    required this.myBalance,
    required this.lastActivityAt,
    required this.recordCount,
  });

  static const empty = GroupOverview(
      members: [], me: null, myBalance: {}, lastActivityAt: null, recordCount: 0);
}

/// [GroupOverview] of [groupId], recomputed from the Drift streams.
@riverpod
GroupOverview groupOverview(Ref ref, String groupId) {
  final all =
      ref.watch(groupMembersProvider(groupId)).value ?? const <MemberModel>[];
  final expenses =
      ref.watch(expensesForRoomProvider(groupId)).value ?? const <ExpenseModel>[];
  final settlements = ref.watch(settlementsForRoomProvider(groupId)).value ??
      const <SettlementModel>[];
  final me = claimedBy(all, ref.watch(currentUserIdProvider));
  int? last;
  for (final t in [
    for (final e in expenses) e.createdAt,
    for (final s in settlements) s.createdAt,
  ]) {
    if (last == null || t > last) last = t;
  }
  return GroupOverview(
    members: [for (final m in all) if (m.isActive) m],
    me: me,
    myBalance: me == null
        ? const {}
        : netBalanceOf(me.userId, expenses, settlements),
    lastActivityAt: last,
    recordCount: expenses.length + settlements.length,
  );
}

/// The groups page's total header (G17): what I am owed and what I owe
/// across [balances] (one per group), per currency — kept apart rather than
/// netted, like the per-group cards (being owed in one group doesn't pay a
/// debt in another). Both maps hold positive cents, sorted by currency.
({Map<String, int> owed, Map<String, int> owing}) balanceTotals(
    Iterable<Map<String, int>> balances) {
  final owed = <String, int>{};
  final owing = <String, int>{};
  for (final b in balances) {
    b.forEach((c, v) {
      if (v > 0) owed[c] = (owed[c] ?? 0) + v;
      if (v < 0) owing[c] = (owing[c] ?? 0) - v;
    });
  }
  Map<String, int> sorted(Map<String, int> m) =>
      {for (final c in m.keys.toList()..sort()) c: m[c]!};
  return (owed: sorted(owed), owing: sorted(owing));
}
