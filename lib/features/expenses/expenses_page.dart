import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    final expensesAsync = ref.watch(expensesForRoomProvider(roomId));
    final adderState = ref.watch(memberAdderProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
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
                itemBuilder: (context, i) =>
                    _ExpenseTile(expense: expenses[i]),
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

class _ExpenseTile extends StatelessWidget {
  final ExpenseModel expense;
  const _ExpenseTile({required this.expense});

  @override
  Widget build(BuildContext context) {
    final amount = (expense.amountCents / 100).toStringAsFixed(2);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.receipt)),
      title: Text(expense.description),
      subtitle: Text('Paid by ${expense.paidBy}'),
      trailing: Text(
        '$amount ${expense.currency}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
