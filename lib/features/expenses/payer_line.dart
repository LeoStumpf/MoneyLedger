import '../../l10n/app_localizations.dart';
import '../../models/expense_model.dart';
import '../../models/expense_payers.dart';

/// The ledger row's payer line (G17; G76 several payers): "You paid" /
/// "Paid by Anna" for one payer, "Paid by you and Ben" for two (you first),
/// "Paid by 3 people" for more. [myId]: this account's participant id.
String payerLineOf(
  ExpenseModel e, {
  required String? myId,
  required String Function(String id) nameOf,
  required AppLocalizations l,
}) {
  if (!hasSeveralPayers(e)) {
    return e.paidBy == myId ? l.youPaid : l.paidByName(nameOf(e.paidBy));
  }
  final payers = paidAmountsOf(e).keys.toList();
  if (payers.length != 2) return l.paidByMany(payers.length);
  if (payers.last == myId) payers.insert(0, payers.removeLast());
  String label(String id) => id == myId ? l.recordYou : nameOf(id);
  return l.paidByTwo(label(payers.first), label(payers.last));
}
