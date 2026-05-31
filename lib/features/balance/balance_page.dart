import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/matrix/matrix_service.dart';
import '../auth/auth_provider.dart';
import 'balance_calculator.dart';
import 'balance_provider.dart';

class BalancePage extends ConsumerWidget {
  final String roomId;
  const BalancePage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(balanceForRoomProvider(roomId));
    final clientAsync = ref.watch(matrixClientProvider);
    final currency = clientAsync.value?.groupCurrency(roomId) ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Balance')),
      body: debts.isEmpty
          ? const Center(child: Text('All settled up!'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: debts.length,
              itemBuilder: (context, i) {
                final d = debts[i];
                final amount = (d.cents / 100).toStringAsFixed(2);
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.arrow_forward, color: Colors.red),
                    title: Text(d.from),
                    subtitle: Text('owes ${d.to}'),
                    trailing: Text(
                      '$amount $currency',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: Colors.red),
                    ),
                    onTap: () => _showSettleDialog(context, ref, d, currency),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showSettleDialog(
    BuildContext context,
    WidgetRef ref,
    DebtEntry debt,
    String currency,
  ) async {
    final myId =
        ref.read(matrixClientProvider).value?.userID ?? '';
    if (debt.from != myId) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record settlement'),
        content: Text(
          'Record that you paid ${(debt.cents / 100).toStringAsFixed(2)} $currency to ${debt.to}?',
        ),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => ctx.pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settlement recorded')),
    );
  }
}
