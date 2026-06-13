import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_status_provider.dart';
import '../../models/expense_model.dart';
import '../groups/group_provider.dart';
import 'expenses_provider.dart';
import 'ledger_syncer.dart';

class ExpensesPage extends ConsumerWidget {
  final String roomId;
  const ExpensesPage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerSyncerProvider);
    ref.watch(syncEngineProvider); // run anti-entropy while this group is open
    final expensesAsync = ref.watch(expensesForRoomProvider(roomId));
    final syncStatus = ref.watch(groupSyncStatusProvider(roomId));
    final names = ref.watch(participantNamesProvider(roomId));
    final adderState = ref.watch(memberAdderProvider);
    // Keep the (auto-dispose) expense notifier alive while this page can
    // trigger deletes — a bare `read` in the dialog callback would let it be
    // disposed mid-delete.
    ref.watch(expenseAdderProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          _SyncStatusIcon(status: syncStatus),
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add member',
            onPressed: adderState.isLoading
                ? null
                : () => _showAddMemberDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'Members',
            onPressed: () => context.push('/groups/$roomId/members'),
          ),
          IconButton(
            icon: const Icon(Icons.balance),
            tooltip: 'Balance',
            onPressed: () => context.push('/groups/$roomId/balance'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/groups/$roomId/expenses/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: Stack(
        children: [
          expensesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (expenses) {
              if (expenses.isEmpty) {
                return const Center(child: Text('No expenses yet.'));
              }
              return ListView.builder(
                itemCount: expenses.length,
                itemBuilder: (context, i) => _ExpenseTile(
                  expense: expenses[i],
                  paidByName:
                      names[expenses[i].paidBy] ?? expenses[i].paidBy,
                  pending: syncStatus.isRecordPending(expenses[i].updatedAt),
                  onTap: () => context.push('/groups/$roomId/expenses/edit',
                      extra: expenses[i]),
                  onDelete: () => _confirmDelete(context, ref, expenses[i]),
                ),
              );
            },
          ),
          if (adderState.isLoading)
            const ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ExpenseModel expense) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
            '"${expense.description}" will be removed for all members.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(expenseAdderProvider.notifier)
        .deleteExpense(expense.id, roomId);
    final error = ref.read(expenseAdderProvider).error;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $error')));
    }
  }

  Future<void> _showAddMemberDialog(
      BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    final userId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add member'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Matrix ID',
            hintText: '@user:matrix.org',
          ),
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final id = ctrl.text.trim();
              if (id.startsWith('@') && id.contains(':')) {
                Navigator.of(ctx).pop(id);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    ctrl.dispose();
    if (userId == null) return;

    await ref.read(memberAdderProvider.notifier).add(roomId, userId);

    final error = ref.read(memberAdderProvider).error;
    messenger.showSnackBar(SnackBar(
        content:
            Text(error != null ? 'Failed: $error' : 'Added $userId')));
  }
}

/// App-bar indicator: a filled cloud once every active peer has acknowledged
/// the group's latest record, an outlined cloud (with the first waiting peer in
/// the tooltip) while replication is still pending.
class _SyncStatusIcon extends StatelessWidget {
  final GroupSyncStatus status;
  const _SyncStatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status.synced) {
      return const IconButton(
        icon: Icon(Icons.cloud_done_outlined),
        tooltip: 'Synced with all members',
        onPressed: null,
      );
    }
    final waitingFor = status.pendingPeers.first;
    return IconButton(
      icon: const Icon(Icons.cloud_queue),
      tooltip: 'Waiting for $waitingFor…',
      onPressed: null,
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final ExpenseModel expense;
  final String paidByName;
  final bool pending;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _ExpenseTile(
      {required this.expense,
      required this.paidByName,
      required this.pending,
      required this.onTap,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final amount = (expense.amountCents / 100).toStringAsFixed(2);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.receipt)),
      title: Text(expense.description),
      subtitle: Text('Paid by $paidByName'),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.cloud_queue,
                size: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          Text(
            '$amount ${expense.currency}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          PopupMenuButton<String>(
            tooltip: 'Expense options',
            onSelected: (action) {
              if (action == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
