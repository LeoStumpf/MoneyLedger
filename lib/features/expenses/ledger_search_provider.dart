import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'expense_filter.dart';

part 'ledger_search_provider.g.dart';

/// G16: the expense list's search / filter state for one group — null while
/// the search bar is closed (everything shown). Auto-disposed with the
/// group page, so leaving the group resets it.
@riverpod
class LedgerSearch extends _$LedgerSearch {
  @override
  LedgerFilter? build(String roomId) => null;

  void open() => state ??= LedgerFilter.none;

  void close() => state = null;

  void setQuery(String query) =>
      state = (state ?? LedgerFilter.none).copyWith(query: query);

  /// Toggles the category filter key [c] (built-in wire id or custom id).
  void toggleCategory(String c) =>
      state = (state ?? LedgerFilter.none).toggleCategory(c);

  void toggleInvolvingMe() {
    final s = state ?? LedgerFilter.none;
    state = s.copyWith(involvingMe: !s.involvingMe);
  }

  /// Clears query and chips but keeps the search bar open.
  void clear() => state = LedgerFilter.none;
}
