import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/expense_date.dart';

/// G49 / G60: the *Date* field of the expense form and the payment dialog —
/// the picked day ("Today" / "Yesterday" / the date), tap → date picker
/// (year [kMinExpenseDateYear] … [kMaxExpenseDateAheadDays] ahead), plus
/// *Today* / *Yesterday* chips. [day] is local midnight; [onChanged] gets
/// the new day (local midnight). Keys: `<keyPrefix>`, `<keyPrefix>Value`,
/// `<keyPrefix>Today`, `<keyPrefix>Yesterday`.
class RecordDateField extends StatelessWidget {
  final DateTime day;
  final ValueChanged<DateTime> onChanged;
  final String keyPrefix;

  const RecordDateField({
    super.key,
    required this.day,
    required this.onChanged,
    this.keyPrefix = 'expenseDate',
  });

  Future<void> _pick(BuildContext context) async {
    final today = dayOf(DateTime.now());
    final last = DateTime(
      today.year,
      today.month,
      today.day + kMaxExpenseDateAheadDays,
    );
    final first = DateTime(kMinExpenseDateYear);
    final initial = day.isBefore(first)
        ? first
        : day.isAfter(last)
        ? last
        : day;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: context.l10n.expenseDatePickerHelp,
    );
    if (picked != null) onChanged(dayOf(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final today = dayOf(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: Key(keyPrefix),
          borderRadius: BorderRadius.circular(Radii.m),
          onTap: () => _pick(context),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: l.expenseDateLabel,
              prefixIcon: const Icon(Icons.event_outlined),
            ),
            child: Text(
              context.dayHeader(day.millisecondsSinceEpoch),
              key: Key('${keyPrefix}Value'),
            ),
          ),
        ),
        const SizedBox(height: Insets.s),
        Wrap(
          spacing: Insets.s,
          children: [
            ChoiceChip(
              key: Key('${keyPrefix}Today'),
              label: Text(l.today),
              selected: day == today,
              onSelected: (_) => onChanged(today),
            ),
            ChoiceChip(
              key: Key('${keyPrefix}Yesterday'),
              label: Text(l.yesterday),
              selected: day == yesterday,
              onSelected: (_) => onChanged(yesterday),
            ),
          ],
        ),
      ],
    );
  }
}
