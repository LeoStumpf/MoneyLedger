import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
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

  // null = still loading; fetched via the transport on init so the list is
  // always accurate even before the room is fully synced.
  List<TransportMember>? _members;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final transport = await ref.read(ledgerTransportProvider.future);
    if (!mounted) return;
    final members = await transport.participants(
      widget.roomId,
      memberships: {TransportMembership.join},
    );
    if (mounted) setState(() => _members = members);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(
      LedgerTransport transport, List<TransportMember> members) async {
    if (!_formKey.currentState!.validate()) return;

    final amountCents =
        (double.parse(_amountCtrl.text.replaceAll(',', '.')) * 100).round();
    final currency = transport.room(widget.roomId)?.currency ?? 'EUR';
    final paidBy = transport.userId;
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
    final transportAsync = ref.watch(ledgerTransportProvider);
    final adderState = ref.watch(expenseAdderProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add expense')),
      body: transportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (transport) {
          final members = _members;
          if (members == null) {
            return const Center(child: CircularProgressIndicator());
          }
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
                          transport.room(widget.roomId)?.currency ?? 'EUR',
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
                    onPressed: adderState.isLoading || members.isEmpty
                        ? null
                        : () => _submit(transport, members),
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
