import 'package:flutter/material.dart';

import '../../core/widgets/large_text.dart';
import '../../core/l10n/l10n.dart';
import '../../core/sync/record_validation.dart';
import '../../models/expense_date.dart' show dayOf;
import '../expenses/record_date_field.dart';
import '../../core/widgets/currency_field.dart';

/// What the user confirmed in [RecordPaymentDialog].
class PaymentDraft {
  final String from;
  final String to;
  final int cents;
  final String currency;

  /// G60: the day the payment happened (local midnight) — today unless the
  /// user picked another.
  final DateTime day;

  const PaymentDraft({
    required this.from,
    required this.to,
    required this.cents,
    required this.currency,
    required this.day,
  });
}

/// G67: returned by [RecordPaymentDialog] in edit mode when the user chose
/// *Delete payment* (the caller confirms and deletes).
class PaymentDeleteRequest {
  const PaymentDeleteRequest();
}

/// Record a payment between **any two participants** (G28, Splitwise-style):
/// "X paid Y" — settles a debt of a local person, or a creditor records money
/// they received. Prefilled from a tapped debt row ([debtCents] set → warns
/// when the amount exceeds what is owed), or blank from the "Record payment"
/// action. Returns a [PaymentDraft] or null when cancelled.
///
/// G60 **edit mode** ([editing]): prefilled from a recorded payment (incl.
/// its day, [initialDay]), titled "Edit payment", *Save* stays disabled
/// until something changed; [footer] shows who recorded / last edited it
/// (G6 attribution).
class RecordPaymentDialog extends StatefulWidget {
  /// participant id → display name; the from/to choices.
  final Map<String, String> participants;
  final String? initialFrom;
  final String? initialTo;
  final int? initialCents;
  final String currency;

  /// The debt this dialog was opened from (same currency), if any.
  final int? debtCents;

  /// G60: the payment's day (local midnight); null = today.
  final DateTime? initialDay;

  /// G60: editing a recorded payment (see the class doc).
  final bool editing;

  /// G60: shown under the fields (edit mode: the attribution footer).
  final Widget? footer;

  /// G66: the currency picker's first section (group currency, used ones,
  /// region …); [currency] is always offered.
  final List<String> suggestedCurrencies;

  /// G67 (edit mode): offer *Delete payment* — pops a
  /// [PaymentDeleteRequest] instead of a [PaymentDraft].
  final bool canDelete;

  const RecordPaymentDialog({
    super.key,
    required this.participants,
    required this.currency,
    this.initialFrom,
    this.initialTo,
    this.initialCents,
    this.debtCents,
    this.initialDay,
    this.editing = false,
    this.footer,
    this.suggestedCurrencies = const [],
    this.canDelete = false,
  });

  @override
  State<RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<RecordPaymentDialog> {
  late String? _from = widget.initialFrom;
  late String? _to = widget.initialTo;
  late String _currency = widget.currency;
  late DateTime _day = dayOf(widget.initialDay ?? DateTime.now()); // G60
  final TextEditingController _amount = TextEditingController();
  bool _amountPrefilled = false;
  String? _prefillText;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Prefill once, with the locale's decimal separator (G12).
    final initial = widget.initialCents;
    if (!_amountPrefilled && initial != null) {
      _amountPrefilled = true;
      _amount.text = formatAmountInput(
        initial,
        context.localeName,
        currency: widget.currency,
      );
      _prefillText = _amount.text;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Accepts `,` and `.` as decimal separator (G12); the UI locale decides a
  /// lone grouping separator (G18 review). Null unless a storable amount
  /// (1 cent … [kMaxAmountCents]).
  int? get _cents {
    final c = _parsed;
    return c != null && isValidAmountCents(c) ? c : null;
  }

  /// G66: the typed amount rounded to the currency's decimals; the unchanged
  /// prefill is [RecordPaymentDialog.initialCents] itself (a legacy
  /// non-whole JPY amount isn't rounded).
  int? get _parsed {
    if (_prefillText != null && _amount.text == _prefillText) {
      return widget.initialCents;
    }
    // G75: a small expression ("12,50+8") is worked out.
    return parseAmountInput(
      _amount.text,
      locale: context.localeName,
      currency: _currency,
    );
  }

  /// Why the typed amount can't be recorded.
  String _amountError(AppLocalizations l) {
    final c = _parsed;
    if (c == null) return l.invalidNumber;
    return c < 1 ? l.amountMustBePositive : l.amountTooLarge;
  }

  /// Why "Record" is disabled, or null when the draft is complete.
  bool get _hasProblem =>
      _from == null || _to == null || _from == _to || _cents == null;

  /// G60 edit mode: nothing differs from the recorded payment.
  bool get _unchanged =>
      widget.editing &&
      _from == widget.initialFrom &&
      _to == widget.initialTo &&
      _cents == widget.initialCents &&
      _currency == widget.currency &&
      _day == dayOf(widget.initialDay ?? DateTime.now());

  /// G71: *Done* on the amount keyboard — records a complete draft.
  void _submitIfReady() {
    final cents = _cents;
    if (_hasProblem || _unchanged || cents == null) return;
    _submit(cents);
  }

  void _submit(int cents) => Navigator.of(context).pop(
    PaymentDraft(
      from: _from!,
      to: _to!,
      cents: cents,
      currency: _currency,
      day: _day,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ids = widget.participants.keys.toList();
    final cents = _cents;
    final debt = widget.debtCents;
    final exceeds =
        debt != null &&
        cents != null &&
        _currency == widget.currency &&
        cents > debt;
    final problem = _hasProblem || _unchanged;
    final l = context.l10n;

    DropdownMenuItem<String> item(String id) => DropdownMenuItem(
      value: id,
      child: Text(
        widget.participants[id] ?? id,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return AlertDialog(
      title: Text(widget.editing ? l.editPayment : l.recordPayment),
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
                    // G71 (U12): blank amount → type it right away; *Done*
                    // records the payment when it is complete.
                    autofocus: widget.initialCents == null,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submitIfReady(),
                    decoration: InputDecoration(
                      labelText: l.amountLabel,
                      // G18 review: how the input was read.
                      helperText: cents != null
                          ? l.amountPreview(context.money(cents, _currency))
                          : null,
                      errorText: _amount.text.trim().isNotEmpty && cents == null
                          ? _amountError(l)
                          : null,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  // DEV-I: grows with the font size (code faded at 200 %).
                  width: scaledCellWidth(context, 96, 140),
                  child: CurrencyField(
                    key: const Key('paymentCurrency'),
                    value: _currency,
                    suggested: widget.suggestedCurrencies,
                    onChanged: (c) => setState(() => _currency = c),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RecordDateField(
              keyPrefix: 'paymentDate',
              day: _day,
              onChanged: (d) => setState(() => _day = d),
            ),
            if (exceeds) ...[
              const SizedBox(height: 12),
              Text(
                l.paymentExceedsDebt(context.money(debt, widget.currency)),
                key: const Key('paymentExceedsWarning'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (widget.footer != null) ...[
              const SizedBox(height: 16),
              widget.footer!,
            ],
          ],
        ),
      ),
      actions: [
        if (widget.editing && widget.canDelete)
          TextButton(
            key: const Key('paymentDelete'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () =>
                Navigator.of(context).pop(const PaymentDeleteRequest()),
            child: Text(l.deletePayment),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('paymentSubmit'),
          onPressed: problem ? null : () => _submit(cents!),
          child: Text(widget.editing ? l.save : l.record),
        ),
      ],
    );
  }
}
