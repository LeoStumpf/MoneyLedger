import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/expense_model.dart';
import '../groups/group_provider.dart';
import 'expenses_provider.dart';

/// Add (default) or edit an expense — pass [initial] to prefill the form and
/// save the submit as an LWW edit of the same record.
class AddExpensePage extends ConsumerStatefulWidget {
  final String roomId;
  final ExpenseModel? initial;
  const AddExpensePage({super.key, required this.roomId, this.initial});

  @override
  ConsumerState<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends ConsumerState<AddExpensePage> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  bool get _isEdit => widget.initial != null;

  // null = still loading. Loaded from the local DB (roomless).
  List<String>? _memberIds;
  String _currency = 'EUR';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _descCtrl.text = initial.description;
      _amountCtrl.text = (initial.amountCents / 100).toStringAsFixed(2);
    }
    _loadData();
  }

  Future<void> _loadData() async {
    final memberIds =
        await ref.read(membersDaoProvider).activeMemberIds(widget.roomId);
    final group = await ref.read(groupsDaoProvider).getGroup(widget.roomId);
    if (mounted) {
      setState(() {
        _memberIds = memberIds;
        _currency = group?.currency ?? 'EUR';
      });
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(List<String> members) async {
    if (!_formKey.currentState!.validate()) return;

    final amountCents =
        (double.parse(_amountCtrl.text.replaceAll(',', '.')) * 100).round();
    final share = (amountCents / members.length).round();
    final splits = {for (final m in members) m: share};

    final initial = widget.initial;
    if (initial != null) {
      // Edit: same record id (and original payer/creation time), fresh clock.
      await ref.read(expenseAdderProvider.notifier).updateExpense(
            id: initial.id,
            roomId: widget.roomId,
            description: _descCtrl.text.trim(),
            amountCents: amountCents,
            currency: _currency,
            paidBy: initial.paidBy,
            splits: splits,
            createdAt: initial.createdAt,
          );
    } else {
      await ref.read(expenseAdderProvider.notifier).addExpense(
            roomId: widget.roomId,
            description: _descCtrl.text.trim(),
            amountCents: amountCents,
            currency: _currency,
            paidBy: ref.read(currentUserIdProvider),
            splits: splits,
          );
    }

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
    final adderState = ref.watch(expenseAdderProvider);
    final members = _memberIds;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit expense' : 'Add expense')),
      body: members == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
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
                        suffixText: _currency,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
                          : () => _submit(members),
                      child: adderState.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isEdit ? 'Save' : 'Add'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
