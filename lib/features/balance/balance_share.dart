/// G69 (U17): "who pays whom" as plain text for the system share sheet — e.g.
/// the message to the trip's chat group. Pure (no Flutter, no DB).
library;

import '../../core/l10n/formatting.dart';
import '../../l10n/app_localizations.dart';
import 'balance_calculator.dart';

/// The share text of [groupName]'s suggested payments [debts] (as
/// `calculateDebts` returns them: ordered by currency) in the language of
/// [l]:
///
/// ```text
/// Rom 2026 – wer zahlt wem
///
/// Ben → Anna: 42,10 €
/// Chris → Anna: 12,00 €
///
/// Erstellt mit MoneyLedger
/// ```
///
/// Several currencies get one block each ("In CHF:"), never netted (G16).
/// No debts → "Alles ausgeglichen.". People are named by [nameOf] — never
/// "you": the text is read by the others. No link, no tracking — the
/// footer is only the app name.
String buildBalanceShareText({
  required AppLocalizations l,
  required String groupName,
  required List<DebtEntry> debts,
  required String Function(String participantId) nameOf,
}) {
  final out = StringBuffer()
    ..writeln(l.shareBalanceTitle(groupName.trim()))
    ..writeln();
  if (debts.isEmpty) {
    out.writeln(l.shareAllSettled);
  } else {
    final currencies = <String>[];
    for (final d in debts) {
      if (!currencies.contains(d.currency)) currencies.add(d.currency);
    }
    final multi = currencies.length > 1;
    for (final (i, currency) in currencies.indexed) {
      if (i > 0) out.writeln();
      if (multi) out.writeln(l.shareCurrencyHeader(currency));
      for (final d in debts.where((d) => d.currency == currency)) {
        out.writeln(
          l.shareDebtLine(
            nameOf(d.from),
            nameOf(d.to),
            formatMoney(d.cents, d.currency, l.localeName),
          ),
        );
      }
    }
  }
  out
    ..writeln()
    ..write(l.shareFooter);
  return out.toString();
}
