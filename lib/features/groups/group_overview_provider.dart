import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../balance/balance_calculator.dart';
import '../balance/balance_provider.dart' show groupExchangeRatesProvider;
import '../balance/settle_currency.dart';
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
    members: [],
    me: null,
    myBalance: {},
    lastActivityAt: null,
    recordCount: 0,
  );
}

/// [GroupOverview] of [groupId], recomputed from the Drift streams.
@riverpod
GroupOverview groupOverview(Ref ref, String groupId) {
  final all =
      ref.watch(groupMembersProvider(groupId)).value ?? const <MemberModel>[];
  final expenses =
      ref.watch(expensesForRoomProvider(groupId)).value ??
      const <ExpenseModel>[];
  final settlements =
      ref.watch(settlementsForRoomProvider(groupId)).value ??
      const <SettlementModel>[];
  // G52: a link group's "me" is the channel's participant (nobody is
  // claimed by this device there) — as [currentParticipantProvider] says.
  final me =
      claimedBy(all, ref.watch(currentUserIdProvider)) ??
      ref.watch(currentParticipantProvider(groupId)).value;
  int? last;
  for (final t in [
    for (final e in expenses) e.createdAt,
    for (final s in settlements) s.createdAt,
  ]) {
    if (last == null || t > last) last = t;
  }
  final settling = ledgerForSettling(
    expenses,
    settlements,
    ref.watch(groupExchangeRatesProvider(groupId)),
  );
  return GroupOverview(
    members: [
      for (final m in all)
        if (m.isActive) m,
    ],
    me: me,
    // G73: in the settle-up currency while that is on.
    myBalance: me == null
        ? const {}
        : netBalanceOf(me.userId, settling.expenses, settling.settlements),
    lastActivityAt: last,
    recordCount: expenses.length + settlements.length,
  );
}

/// The groups page's total header (G17): what I am owed and what I owe
/// across [balances] (one per group), per currency — kept apart rather than
/// netted, like the per-group cards (being owed in one group doesn't pay a
/// debt in another). Both maps hold positive cents, sorted by currency.
({Map<String, int> owed, Map<String, int> owing}) balanceTotals(
  Iterable<Map<String, int>> balances,
) {
  final owed = <String, int>{};
  final owing = <String, int>{};
  for (final b in balances) {
    b.forEach((c, v) {
      if (v > 0) owed[c] = (owed[c] ?? 0) + v;
      if (v < 0) owing[c] = (owing[c] ?? 0) - v;
    });
  }
  Map<String, int> sorted(Map<String, int> m) => {
    for (final c in m.keys.toList()..sort()) c: m[c]!,
  };
  return (owed: sorted(owed), owing: sorted(owing));
}

/// The creation time (ms) encoded in a UUIDv7 [id] (its first 48 bits), or
/// null when [id] isn't one (an old / imported group id).
int? uuidV7Millis(String id) {
  final m = RegExp(
    r'^([0-9a-fA-F]{8})-([0-9a-fA-F]{4})-7[0-9a-fA-F]{3}-',
  ).firstMatch(id);
  if (m == null) return null;
  return int.parse('${m[1]}${m[2]}', radix: 16);
}

/// G69 (U20): when a group was last active, for the groups list order —
/// the newest record ([GroupOverview.lastActivityAt], what the card shows),
/// but never earlier than the group's creation (its UUIDv7 id), so a new,
/// still empty group sits on top. Null: neither is known.
int? groupActivityAt(GroupModel group, GroupOverview overview) {
  final created = uuidV7Millis(group.roomId);
  final last = overview.lastActivityAt;
  if (created == null) return last;
  if (last == null) return created;
  return last > created ? last : created;
}

/// [entries] sorted by [groupActivityAt], newest first; groups without any
/// known activity last; ties by name (case-insensitive), then id.
List<(GroupModel, GroupOverview)> sortGroupsByActivity(
  Iterable<(GroupModel, GroupOverview)> entries,
) {
  final keyed = [for (final e in entries) (groupActivityAt(e.$1, e.$2), e)];
  keyed.sort((a, b) {
    final (ta, (ga, _)) = a;
    final (tb, (gb, _)) = b;
    if (ta != tb) {
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    }
    final n = ga.name.toLowerCase().compareTo(gb.name.toLowerCase());
    return n != 0 ? n : ga.roomId.compareTo(gb.roomId);
  });
  return [for (final (_, e) in keyed) e];
}
