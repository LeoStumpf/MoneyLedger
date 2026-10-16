import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/person_avatar.dart';
import '../../models/expense_model.dart';
import '../../models/member_model.dart';
import '../groups/create_group_page.dart' show kGroupCurrencies;
import '../groups/group_provider.dart';
import 'expenses_provider.dart';
import 'split_editor.dart';
import '../../core/sync/record_signing.dart' show RecordKind;
import 'record_attribution.dart';

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

  /// Accepts `,` and `.` as decimal separator (G12) — see
  /// [parseAmountCents].
  int get _amountCents => parseAmountCents(_amountCtrl.text) ?? 0;

  Map<String, int>? get _initialSplit {
    final json = widget.initial?.splitsJson;
    if (json == null) return null;
    return (jsonDecode(json) as Map).map(
      (k, v) => MapEntry(k as String, (v as num).toInt()),
    );
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) _descCtrl.text = initial.description;
    _loadData();
  }

  bool _amountPrefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Prefill the edited amount once, with the locale's decimal separator.
    final initial = widget.initial;
    if (initial != null && !_amountPrefilled) {
      _amountPrefilled = true;
      _amountCtrl.text = formatAmountInput(
        initial.amountCents,
        context.localeName,
      );
    }
  }

  Future<void> _loadData() async {
    final members =
        (await ref.read(membersDaoProvider).getMembers(widget.roomId))
            .where((m) => m.isActive)
            .toList();
    final group = await ref.read(groupsDaoProvider).getGroup(widget.roomId);
    // Default payer: the edited expense's payer, else this device's participant.
    final self = await ref.read(
      currentParticipantProvider(widget.roomId).future,
    );
    final defaultPayer =
        widget.initial?.paidBy ??
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
      await ref
          .read(expenseAdderProvider.notifier)
          .updateExpense(
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
      await ref
          .read(expenseAdderProvider.notifier)
          .addExpense(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.failedWithError(error.toString()))),
      );
    } else if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final adderState = ref.watch(expenseAdderProvider);
    final members = _members;
    final l = context.l10n;
    final theme = Theme.of(context);
    final canSubmit =
        members != null &&
        !adderState.isLoading &&
        members.isNotEmpty &&
        (_plan?.resolve(_amountCents).isValid ?? false);
    final currencies = [
      ...kGroupCurrencies,
      // Keep an unlisted currency (edit / group).
      if (!kGroupCurrencies.contains(_initialCurrency)) _initialCurrency,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? l.editExpense : l.addExpense)),
      // G17: the form scrolls and the submit button sits below it — the body
      // shrinks with the keyboard, so the button always stays visible above
      // it (it used to be covered at the end of the form).
      body: members == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.page,
                      Insets.s,
                      Insets.page,
                      Insets.xl,
                    ),
                    child: ContentWidth(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _descCtrl,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                labelText: l.descriptionLabel,
                                prefixIcon: const Icon(
                                  Icons.receipt_long_outlined,
                                ),
                              ),
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? l.required : null,
                            ),
                            const SizedBox(height: Insets.l),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 108,
                                  child: DropdownButtonFormField<String>(
                                    key: const Key('expenseCurrency'),
                                    initialValue: _currency,
                                    decoration: InputDecoration(
                                      labelText: l.currencyLabel,
                                    ),
                                    items: [
                                      for (final c in currencies)
                                        DropdownMenuItem(
                                          value: c,
                                          child: Text(c),
                                        ),
                                    ],
                                    onChanged: (v) => setState(
                                      () => _currency = v ?? _currency,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: Insets.m),
                                Expanded(
                                  child: TextFormField(
                                    controller: _amountCtrl,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontFeatures: kTabularFigures,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: l.amountLabel,
                                      hintText: formatAmountInput(
                                        0,
                                        context.localeName,
                                      ),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    // re-split on amount edit
                                    onChanged: (_) => setState(() {}),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) {
                                        return l.required;
                                      }
                                      if (parseAmountCents(v) == null) {
                                        return l.invalidNumber;
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: Insets.l),
                            DropdownButtonFormField<String>(
                              key: const Key('expensePayer'),
                              initialValue: _paidBy,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: l.paidByLabel,
                              ),
                              items: [
                                for (final m in members)
                                  DropdownMenuItem(
                                    value: m.userId,
                                    child: Row(
                                      children: [
                                        PersonAvatar(
                                          id: m.userId,
                                          name: m.label,
                                          size: 26,
                                        ),
                                        const SizedBox(width: Insets.m),
                                        Expanded(
                                          child: Text(
                                            m.label,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _paidBy = v),
                            ),
                            const SizedBox(height: Insets.xl),
                            Text(
                              l.splitSection,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: Insets.s),
                            SplitEditor(
                              members: members,
                              totalCents: _amountCents,
                              currency: _currency,
                              initialSplit: _initialSplit,
                              onPlanChanged: (p) => setState(() => _plan = p),
                            ),
                            // G6: who added / last edited it (signed).
                            if (widget.initial case final e?) ...[
                              const SizedBox(height: Insets.xl),
                              RecordAttribution(
                                groupId: widget.roomId,
                                kind: RecordKind.expense,
                                recordId: e.id,
                                origin: e.origin,
                                sig: e.sig,
                                createdAt: e.createdAt,
                                updatedAt: e.updatedAt,
                                members: members,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Material(
                  color: theme.colorScheme.surface,
                  elevation: 3,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.page,
                        Insets.m,
                        Insets.page,
                        Insets.m,
                      ),
                      child: ContentWidth(
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            key: const Key('submitExpense'),
                            onPressed: canSubmit
                                ? () => _submit(members)
                                : null,
                            child: adderState.isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(_isEdit ? l.save : l.add),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
