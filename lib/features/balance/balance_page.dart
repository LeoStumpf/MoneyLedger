import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/matrix/transport_provider.dart';
import '../expenses/expenses_provider.dart';
import 'balance_calculator.dart';
import 'balance_provider.dart';

class BalancePage extends ConsumerStatefulWidget {
  final String roomId;
  const BalancePage({super.key, required this.roomId});

  @override
  ConsumerState<BalancePage> createState() => _BalancePageState();
}

class _BalancePageState extends ConsumerState<BalancePage> {
  @override
  Widget build(BuildContext context) {
    final debts = ref.watch(balanceForRoomProvider(widget.roomId));
    final transport = ref.watch(ledgerTransportProvider).value;
    final currency = transport?.room(widget.roomId)?.currency ?? '';
    final myId = transport?.userId ?? '';
    final adderState = ref.watch(expenseAdderProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Balance')),
      body: Stack(
        children: [
          debts.isEmpty
              ? const Center(child: Text('All settled up!'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: debts.length,
                  itemBuilder: (context, i) {
                    final d = debts[i];
                    final amount = (d.cents / 100).toStringAsFixed(2);
                    final isMine = d.from == myId;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.arrow_forward,
                          color: isMine ? Colors.red : Colors.grey,
                        ),
                        title: Text(
                          d.from,
                          style: TextStyle(
                            fontWeight: isMine
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text('owes ${d.to}'),
                        trailing: Text(
                          '$amount $currency',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color: isMine
                                      ? Colors.red
                                      : Colors.grey[700]),
                        ),
                        // Only the current user can settle their own debts.
                        onTap: isMine && !adderState.isLoading
                            ? () => _settle(context, d, currency, myId)
                            : null,
                      ),
                    );
                  },
                ),
          // Overlay spinner while the settlement event is being sent.
          if (adderState.isLoading)
            const ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Future<void> _settle(
    BuildContext context,
    DebtEntry debt,
    String currency,
    String myId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final amount = (debt.cents / 100).toStringAsFixed(2);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record settlement'),
        content: Text(
            'Mark that you paid $amount $currency to ${debt.to}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(expenseAdderProvider.notifier).addSettlement(
          roomId: widget.roomId,
          amountCents: debt.cents,
          currency: currency,
          fromUser: myId,
          toUser: debt.to,
        );

    if (!mounted) return;
    final error = ref.read(expenseAdderProvider).error;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $error')));
    } else {
      messenger.showSnackBar(
          const SnackBar(content: Text('Settlement recorded')));
    }
  }
}
