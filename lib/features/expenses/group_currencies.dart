import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/currencies.dart';
import '../../core/widgets/currency_field.dart' show deviceRegionProvider;
import 'expenses_provider.dart';

/// G66: the currency picker's suggestions for group [groupId]: [selected],
/// the group's currency, the currencies its live expenses / payments use
/// (most frequent first), the device region's, then the common ones. Reads
/// the DB once (a picker opened from a form / dialog).
Future<List<String>> groupCurrencySuggestions(
  WidgetRef ref,
  String groupId, {
  String? selected,
  String? groupCurrency,
}) async {
  final dao = ref.read(expensesDaoProvider);
  final region = ref.read(deviceRegionProvider);
  final expenses = await dao.getExpensesForRoom(groupId);
  final settlements = await dao.getSettlementsForRoom(groupId);
  return suggestedCurrencies(
    selected: selected,
    groupCurrency: groupCurrency,
    used: byFrequency([
      for (final e in expenses) e.currency,
      for (final s in settlements) s.currency,
    ]),
    region: region,
  );
}
