import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/expense_model.dart';
import 'expenses_provider.dart';
import 'ledger_syncer.dart';

class ExpensesPage extends ConsumerWidget {
  final String roomId;
  const ExpensesPage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerSyncerProvider);
    final expensesAsync = ref.watch(expensesForRoomProvider(roomId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
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
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (expenses) {
          if (expenses.isEmpty) {
            return const Center(child: Text('No expenses yet.'));
          }
          return ListView.builder(
            itemCount: expenses.length,
            itemBuilder: (context, i) => _ExpenseTile(expense: expenses[i]),
          );
        },
      ),
    );
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
