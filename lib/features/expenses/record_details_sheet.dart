import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/sync/record_signing.dart' show RecordKind;
import '../../core/theme/app_theme.dart';
import '../../core/widgets/person_avatar.dart';
import '../../models/expense_category.dart';
import '../../models/expense_date.dart';
import '../../models/expense_model.dart';
import '../../models/expense_payers.dart';
import '../../models/member_model.dart' show localpartOf;
import 'expense_category_ui.dart';
import 'record_attribution.dart';

/// G67 (U15): a read-only look at an expense — for groups this account was
/// removed from (G26), where tapping used to do nothing: amount, who paid,
/// the day, category, who owes what, the note and "added by". [names]:
/// participant id → display name.
Future<void> showExpenseDetails(
  BuildContext context,
  ExpenseModel expense, {
  required Map<String, String> names,
  ResolvedCategory? category,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (ctx) =>
      _ExpenseDetails(expense: expense, names: names, category: category),
);

/// G67 (U15): a read-only look at a payment (see [showExpenseDetails]).
Future<void> showSettlementDetails(
  BuildContext context,
  SettlementModel settlement, {
  required String from,
  required String to,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (ctx) =>
      _SettlementDetails(settlement: settlement, from: from, to: to),
);

String _nameOf(Map<String, String> names, String id) =>
    names[id] ?? localpartOf(id);

/// The shared frame: a scrollable column with the read-only hint at the end.
class _DetailsFrame extends StatelessWidget {
  const _DetailsFrame({required this.sheetKey, required this.children});

  final Key sheetKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          key: sheetKey,
          padding: const EdgeInsets.fromLTRB(
            Insets.page,
            0,
            Insets.page,
            Insets.l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...children,
              const SizedBox(height: Insets.l),
              Text(
                context.l10n.detailsReadOnlyHint,
                key: const Key('detailsReadOnlyHint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A caption + value line ("Date — Yesterday").
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Insets.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }
}

class _ExpenseDetails extends StatelessWidget {
  const _ExpenseDetails({
    required this.expense,
    required this.names,
    required this.category,
  });

  final ExpenseModel expense;
  final Map<String, String> names;
  final ResolvedCategory? category;

  Map<String, int> get _split {
    try {
      final decoded = jsonDecode(expense.splitsJson);
      if (decoded is! Map) return const {};
      return {
        for (final e in decoded.entries)
          if (e.value is int) e.key as String: e.value as int,
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final note = expense.note;
    final category = this.category;
    return _DetailsFrame(
      sheetKey: const Key('expenseDetailsSheet'),
      children: [
        Text(l.expenseDetailsTitle, style: theme.textTheme.labelLarge),
        const SizedBox(height: Insets.s),
        Row(
          children: [
            CategoryIconTile(category: category),
            const SizedBox(width: Insets.m),
            Expanded(
              child: Text(
                expense.description,
                key: const Key('detailsDescription'),
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.s),
        Text(
          context.money(expense.amountCents, expense.currency),
          key: const Key('detailsAmount'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontFeatures: kTabularFigures,
          ),
        ),
        if (hasSeveralPayers(expense))
          // G76: several payers — who paid how much, like the split.
          _Field(
            label: l.paidByLabel,
            child: _PeopleAmounts(
              key: const Key('detailsPayers'),
              amounts: paidAmountsOf(expense),
              names: names,
              currency: expense.currency,
            ),
          )
        else
          Text(l.paidByName(_nameOf(names, expense.paidBy))),
        _Field(
          label: l.detailsDateHeading,
          child: Text(
            context.dayHeader(expense.displayDay.millisecondsSinceEpoch),
          ),
        ),
        if (category != null)
          _Field(
            label: l.detailsCategoryHeading,
            child: Text(category.label(l)),
          ),
        _Field(
          label: l.detailsSplitHeading,
          child: _PeopleAmounts(
            amounts: _split,
            names: names,
            currency: expense.currency,
          ),
        ),
        if (note != null)
          _Field(
            label: l.detailsNoteHeading,
            child: Text(note, key: const Key('detailsNote')),
          ),
        const SizedBox(height: Insets.l),
        RecordAttribution(
          groupId: expense.roomId,
          kind: RecordKind.expense,
          recordId: expense.id,
          origin: expense.origin,
          sig: expense.sig,
          linkAuthor: expense.linkAuthor,
          createdAt: expense.createdAt,
          updatedAt: expense.updatedAt,
        ),
      ],
    );
  }
}

/// One row per person: avatar, name, amount (the split; G76 the payers).
class _PeopleAmounts extends StatelessWidget {
  const _PeopleAmounts({
    super.key,
    required this.amounts,
    required this.names,
    required this.currency,
  });

  final Map<String, int> amounts;
  final Map<String, String> names;
  final String currency;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final share in amounts.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              PersonAvatar(
                id: share.key,
                name: _nameOf(names, share.key),
                size: 28,
              ),
              const SizedBox(width: Insets.m),
              Expanded(
                child: Text(
                  _nameOf(names, share.key),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Insets.s),
              Text(
                context.money(share.value, currency),
                style: const TextStyle(fontFeatures: kTabularFigures),
              ),
            ],
          ),
        ),
    ],
  );
}

class _SettlementDetails extends StatelessWidget {
  const _SettlementDetails({
    required this.settlement,
    required this.from,
    required this.to,
  });

  final SettlementModel settlement;
  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return _DetailsFrame(
      sheetKey: const Key('settlementDetailsSheet'),
      children: [
        Text(l.paymentDetailsTitle, style: theme.textTheme.labelLarge),
        const SizedBox(height: Insets.s),
        Text(
          l.settlementTitle(from, to),
          key: const Key('detailsDescription'),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: Insets.s),
        Text(
          context.money(settlement.amountCents, settlement.currency),
          key: const Key('detailsAmount'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontFeatures: kTabularFigures,
          ),
        ),
        _Field(
          label: l.detailsDateHeading,
          child: Text(
            context.dayHeader(settlement.displayDay.millisecondsSinceEpoch),
          ),
        ),
        const SizedBox(height: Insets.l),
        RecordAttribution(
          groupId: settlement.roomId,
          kind: RecordKind.settlement,
          recordId: settlement.id,
          origin: settlement.origin,
          sig: settlement.sig,
          linkAuthor: settlement.linkAuthor,
          createdAt: settlement.createdAt,
          updatedAt: settlement.updatedAt,
        ),
      ],
    );
  }
}
