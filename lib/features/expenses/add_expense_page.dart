import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/expense_model.dart';
import '../../models/member_model.dart';
import '../groups/create_group_page.dart' show kGroupCurrencies;
import '../groups/group_provider.dart';
import 'expenses_provider.dart';
import 'split_editor.dart';

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
  List<MemberModel>? _members;
  String? _paidBy; // participant id of the payer
  String _currency = 'EUR';
  String _initialCurrency = 'EUR'; // as loaded — stays selectable

  // The SplitEditor's current mode + inputs; resolved against the live amount.
  SplitPlan? _plan;

  int get _amountCents {
    final v = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    return v == null ? 0 : (v * 100).round();
  }

  Map<String, int>? get _initialSplit {
    final json = widget.initial?.splitsJson;
    if (json == null) return null;
    return (jsonDecode(json) as Map)
        .map((k, v) => MapEntry(k as String, (v as num).toInt()));
  }

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
    final members = (await ref.read(membersDaoProvider).getMembers(widget.roomId))
        .where((m) => m.isActive)
        .toList();
    final group = await ref.read(groupsDaoProvider).getGroup(widget.roomId);
    // Default payer: the edited expense's payer, else this device's participant.
    final self = await ref.read(currentParticipantProvider(widget.roomId).future);
    final defaultPayer = widget.initial?.paidBy ??
        self?.userId ??
        (members.isNotEmpty ? members.first.userId : null);
    if (mounted) {
      setState(() {
        _members = members;
        // Edit keeps the expense's own currency; new ones default to the
        // group's (G29 — each expense may use any currency).
        _currency = widget.initial?.currency ?? group?.currency ?? 'EUR';
        _initialCurrency = _currency;
        _paidBy = defaultPayer;
      });
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(List<MemberModel> members) async {
    if (!_formKey.currentState!.validate()) return;
    final paidBy = _paidBy;
    final amountCents = _amountCents;
    final result = _plan?.resolve(amountCents);
    if (paidBy == null || result == null || !result.isValid) return;

    final splits = result.shares;

    final initial = widget.initial;
    if (initial != null) {
      // Edit: same record id and creation time, fresh clock; payer editable.
      await ref.read(expenseAdderProvider.notifier).updateExpense(
            id: initial.id,
            roomId: widget.roomId,
            description: _descCtrl.text.trim(),
            amountCents: amountCents,
            currency: _currency,
            paidBy: paidBy,
            splits: splits,
            createdAt: initial.createdAt,
          );
    } else {
      await ref.read(expenseAdderProvider.notifier).addExpense(
            roomId: widget.roomId,
            description: _descCtrl.text.trim(),
            amountCents: amountCents,
            currency: _currency,
            paidBy: paidBy,
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
    final members = _members;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit expense' : 'Add expense')),
      body: members == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _amountCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Amount'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            // re-split on amount edit
                            onChanged: (_) => setState(() {}),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              if (double.tryParse(v.replaceAll(',', '.')) ==
                                  null) {
                                return 'Invalid number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: DropdownButtonFormField<String>(
                            key: const Key('expenseCurrency'),
                            initialValue: _currency,
                            decoration:
                                const InputDecoration(labelText: 'Currency'),
                            items: [
                              for (final c in [
                                ...kGroupCurrencies,
                                // Keep an unlisted currency (edit / group).
                                if (!kGroupCurrencies.contains(_initialCurrency))
                                  _initialCurrency,
                              ])
                                DropdownMenuItem(value: c, child: Text(c)),
                            ],
                            onChanged: (v) =>
                                setState(() => _currency = v ?? _currency),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _paidBy,
                      decoration: const InputDecoration(labelText: 'Paid by'),
                      items: [
                        for (final m in members)
                          DropdownMenuItem(
                            value: m.userId,
                            child: Text(m.displayName.isNotEmpty
                                ? m.displayName
                                : (m.matrixId ?? m.userId)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _paidBy = v),
                    ),
                    const SizedBox(height: 16),
                    SplitEditor(
                      members: members,
                      totalCents: _amountCents,
                      currency: _currency,
                      initialSplit: _initialSplit,
                      onPlanChanged: (p) => setState(() => _plan = p),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: adderState.isLoading ||
                              members.isEmpty ||
                              !(_plan?.resolve(_amountCents).isValid ?? false)
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
