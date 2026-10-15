import 'package:flutter/material.dart';

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
  late final TextEditingController _amount = TextEditingController(
      text: widget.initialCents == null
          ? ''
          : (widget.initialCents! / 100).toStringAsFixed(2));

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _cents {
    final v = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (v == null) return null;
    final c = (v * 100).round();
    return c > 0 ? c : null;
  }

  String? get _problem {
    if (_from == null || _to == null) return 'Choose who paid whom';
    if (_from == _to) return 'Payer and recipient must differ';
    if (_cents == null) return 'Enter an amount';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.participants.keys.toList();
    final currencies = [
      ...kGroupCurrencies,
      if (!kGroupCurrencies.contains(widget.currency)) widget.currency,
    ];
    final cents = _cents;
    final debt = widget.debtCents;
    final exceeds = debt != null &&
        cents != null &&
        _currency == widget.currency &&
        cents > debt;
    final problem = _problem;

    DropdownMenuItem<String> item(String id) => DropdownMenuItem(
          value: id,
          child: Text(widget.participants[id] ?? id,
              overflow: TextOverflow.ellipsis),
        );

    return AlertDialog(
      title: const Text('Record payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('paymentFrom'),
              initialValue: _from,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'From (paid)'),
              items: [for (final id in ids) item(id)],
              onChanged: (v) => setState(() => _from = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('paymentTo'),
              initialValue: _to,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'To (received)'),
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
                    decoration: const InputDecoration(labelText: 'Amount'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  child: DropdownButtonFormField<String>(
                    key: const Key('paymentCurrency'),
                    initialValue: _currency,
                    decoration: const InputDecoration(labelText: 'Currency'),
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
                'More than the ${(debt / 100).toStringAsFixed(2)} '
                '${widget.currency} owed',
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: problem != null
              ? null
              : () => Navigator.of(context).pop(PaymentDraft(
                    from: _from!,
                    to: _to!,
                    cents: cents!,
                    currency: _currency,
                  )),
          child: const Text('Record'),
        ),
      ],
    );
  }
}
