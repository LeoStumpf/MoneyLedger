import 'package:flutter/material.dart';

import '../balance/balance_calculator.dart';
import 'group_provider.dart';

/// The informative "not settled up" line for the leave/delete confirmation
/// (G9): what [meId] still owes / is owed in the group, per currency, from the
/// simplified [debts]. Null when settled (or when we have no participant).
String? unsettledWarning(List<DebtEntry> debts, String? meId) {
  if (meId == null) return null;
  final net = <String, int>{}; // currency → + owed to me / − I owe
  for (final d in debts) {
    if (d.to == meId) net[d.currency] = (net[d.currency] ?? 0) + d.cents;
    if (d.from == meId) net[d.currency] = (net[d.currency] ?? 0) - d.cents;
  }
  String fmt(int cents, String currency) =>
      '${(cents.abs() / 100).toStringAsFixed(2)} $currency';
  final owe = [
    for (final e in net.entries)
      if (e.value < 0) fmt(e.value, e.key)
  ];
  final owed = [
    for (final e in net.entries)
      if (e.value > 0) fmt(e.value, e.key)
  ];
  final parts = [
    if (owe.isNotEmpty) 'You still owe ${owe.join(' + ')}.',
    if (owed.isNotEmpty) 'You are still owed ${owed.join(' + ')}.',
  ];
  return parts.isEmpty ? null : parts.join(' ');
}

/// Confirmation for leaving / deleting a group. Returns true to proceed.
/// [onExport] (optional) offers the existing CSV export right in the dialog.
Future<bool> confirmGroupExit(
  BuildContext context, {
  required GroupExitKind kind,
  required String groupName,
  required String? warning,
  Future<void> Function()? onExport,
}) async {
  final leave = kind == GroupExitKind.leave;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(leave ? 'Leave group?' : 'Delete group?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(leave
              ? '"$groupName" will be removed from this device and the other '
                  'members will see that you left. Your expenses stay in '
                  'their ledger.'
              : '"$groupName" and all its expenses will be permanently '
                  'removed from this device.'),
          if (warning != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Theme.of(ctx).colorScheme.error),
                const SizedBox(width: 8),
                Expanded(child: Text(warning)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (onExport == null)
            const Text('Tip: export a CSV backup first.')
          else
            // In the content, not the actions: three actions don't fit side
            // by side on a phone and stack awkwardly.
            TextButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.save_alt),
              label: const Text('Export a CSV backup first'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(leave ? 'Leave' : 'Delete'),
        ),
      ],
    ),
  );
  return result == true;
}
