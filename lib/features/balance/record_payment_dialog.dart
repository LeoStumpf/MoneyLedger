import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../groups/create_group_page.dart' show kGroupCurrencies;

/// What the user confirmed in [RecordPaymentDialog].
class PaymentDraft {
  final String from;
  final String to;
  final int cents;
  final String currency;
  const PaymentDraft({
    required this.from,
    required this.to,
    required this.cents,
    required this.currency,
  });
}

/// Record a payment between **any two participants** (G28, Splitwise-style):
/// "X paid Y" — settles a debt of a local person, or a creditor records money
/// they received. Prefilled from a tapped debt row ([debtCents] set → warns
/// when the amount exceeds what is owed), or blank from the "Record payment"
/// action. Returns a [PaymentDraft] or null when cancelled.
class RecordPaymentDialog extends StatefulWidget {
  /// participant id → display name; the from/to choices.
  final Map<String, String> participants;
  final String? initialFrom;
  final String? initialTo;
  final int? initialCents;
  final String currency;

  /// The debt this dialog was opened from (same currency), if any.
  final int? debtCents;

  const RecordPaymentDialog({
    super.key,
    required this.participants,
    required this.currency,
    this.initialFrom,
    this.initialTo,
    this.initialCents,
    this.debtCents,
  });

  @override
  State<RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<RecordPaymentDialog> {
  late String? _from = widget.initialFrom;
  late String? _to = widget.initialTo;
  late String _currency = widget.currency;
  final TextEditingController _amount = TextEditingController();
  bool _amountPrefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Prefill once, with the locale's decimal separator (G12).
    final initial = widget.initialCents;
    if (!_amountPrefilled && initial != null) {
      _amountPrefilled = true;
      _amount.text = formatAmountInput(initial, context.localeName);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Accepts `,` and `.` as decimal separator (G12).
  int? get _cents {
    final c = parseAmountCents(_amount.text);
    return c != null && c > 0 ? c : null;
  }

  /// Why "Record" is disabled, or null when the draft is complete.
  bool get _hasProblem =>
      _from == null || _to == null || _from == _to || _cents == null;

  @override
  Widget build(BuildContext context) {
    final ids = widget.participants.keys.toList();
    final currencies = [
      ...kGroupCurrencies,
      if (!kGroupCurrencies.contains(widget.currency)) widget.currency,
    ];
    final cents = _cents;
    final debt = widget.debtCents;
    final exceeds =
        debt != null &&
        cents != null &&
        _currency == widget.currency &&
        cents > debt;
    final problem = _hasProblem;
    final l = context.l10n;

    DropdownMenuItem<String> item(String id) => DropdownMenuItem(
      value: id,
      child: Text(
        widget.participants[id] ?? id,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return AlertDialog(
      title: Text(l.recordPayment),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('paymentFrom'),
              initialValue: _from,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.paymentFromLabel),
              items: [for (final id in ids) item(id)],
              onChanged: (v) => setState(() => _from = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('paymentTo'),
              initialValue: _to,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.paymentToLabel),
              items: [for (final id in ids) item(id)],
              onChanged: (v) => setState(() => _to = v),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('paymentAmount'),
                    controller: _amount,
                    decoration: InputDecoration(labelText: l.amountLabel),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  child: DropdownButtonFormField<String>(
                    key: const Key('paymentCurrency'),
                    initialValue: _currency,
                    decoration: InputDecoration(labelText: l.currencyLabel),
                    items: [
                      for (final c in currencies)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) =>
                        setState(() => _currency = v ?? _currency),
                  ),
                ),
              ],
            ),
            if (exceeds) ...[
              const SizedBox(height: 12),
              Text(
                l.paymentExceedsDebt(context.money(debt, widget.currency)),
                key: const Key('paymentExceedsWarning'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: problem
              ? null
              : () => Navigator.of(context).pop(
                  PaymentDraft(
                    from: _from!,
                    to: _to!,
                    cents: cents!,
                    currency: _currency,
                  ),
                ),
          child: Text(l.record),
        ),
      ],
    );
  }
}
