import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../balance/balance_calculator.dart';
import 'group_provider.dart';

/// The informative "not settled up" line for the leave/delete confirmation
/// (G9): what [meId] still owes / is owed in the group, per currency, from the
/// simplified [debts]. Null when settled (or when we have no participant).
/// Localized through [l] (amounts in its locale) — pure, no BuildContext.
String? unsettledWarning(
  List<DebtEntry> debts,
  String? meId,
  AppLocalizations l,
) {
  if (meId == null) return null;
  final net = <String, int>{}; // currency → + owed to me / − I owe
  for (final d in debts) {
    if (d.to == meId) net[d.currency] = (net[d.currency] ?? 0) + d.cents;
    if (d.from == meId) net[d.currency] = (net[d.currency] ?? 0) - d.cents;
  }
  String fmt(int cents, String currency) =>
      formatMoney(cents.abs(), currency, l.localeName);
  final owe = [
    for (final e in net.entries)
      if (e.value < 0) fmt(e.value, e.key),
  ];
  final owed = [
    for (final e in net.entries)
      if (e.value > 0) fmt(e.value, e.key),
  ];
  final parts = [
    if (owe.isNotEmpty) l.unsettledYouOwe(owe.join(' + ')),
    if (owed.isNotEmpty) l.unsettledYouAreOwed(owed.join(' + ')),
  ];
  return parts.isEmpty ? null : parts.join(' ');
}

/// Confirmation for leaving / deleting a group. Returns true to proceed.
/// [onBackup] (optional) offers the full backup (G5, "Back up all groups")
/// right in the dialog.
Future<bool> confirmGroupExit(
  BuildContext context, {
  required GroupExitKind kind,
  required String groupName,
  required String? warning,
  Future<void> Function()? onBackup,
}) async {
  final leave = kind == GroupExitKind.leave;
  final l = context.l10n;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(leave ? l.leaveGroupTitle : l.deleteGroupTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            leave ? l.leaveGroupBody(groupName) : l.deleteGroupBody(groupName),
          ),
          if (warning != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(warning)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (onBackup == null)
            Text(l.backupBeforeExitTip)
          else
            // In the content, not the actions: three actions don't fit side
            // by side on a phone and stack awkwardly.
            TextButton.icon(
              onPressed: onBackup,
              icon: const Icon(Icons.save_alt),
              label: Text(l.backupBeforeExit),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(leave ? l.leave : l.delete),
        ),
      ],
    ),
  );
  return result == true;
}
