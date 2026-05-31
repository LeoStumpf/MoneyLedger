import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import '../../core/matrix/matrix_service.dart';
import '../auth/auth_provider.dart';
import 'expenses_provider.dart';

class AddExpensePage extends ConsumerStatefulWidget {
  final String roomId;
  const AddExpensePage({super.key, required this.roomId});

  @override
  ConsumerState<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends ConsumerState<AddExpensePage> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(Client client, List<User> members) async {
    if (!_formKey.currentState!.validate()) return;

    final amountCents =
        (double.parse(_amountCtrl.text.replaceAll(',', '.')) * 100).round();
    final currency = client.groupCurrency(widget.roomId) ?? 'EUR';
    final paidBy = client.userID ?? '';
    final share = (amountCents / members.length).round();
    final splits = {for (final m in members) m.id: share};

    await ref.read(expenseAdderProvider.notifier).addExpense(
          roomId: widget.roomId,
          description: _descCtrl.text.trim(),
          amountCents: amountCents,
          currency: currency,
          paidBy: paidBy,
          splits: splits,
        );

    final error = ref.read(expenseAdderProvider).error;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } else if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientAsync = ref.watch(matrixClientProvider);
    final adderState = ref.watch(expenseAdderProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add expense')),
      body: clientAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (client) {
          final room = client.getRoomById(widget.roomId);
          final members = room?.getParticipants() ?? [];
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _descCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Description'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountCtrl,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      suffixText:
                          client.groupCurrency(widget.roomId) ?? 'EUR',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (double.tryParse(v.replaceAll(',', '.')) == null) {
                        return 'Invalid number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Split equally among ${members.length} member(s)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: adderState.isLoading
                        ? null
                        : () => _submit(client, members),
                    child: adderState.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
