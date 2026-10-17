import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/sync/record_validation.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/person_avatar.dart';
import '../../models/expense_category.dart';
import '../../models/expense_date.dart';
import '../../models/expense_model.dart';
import '../../models/member_model.dart';
import '../../core/widgets/currency_field.dart';
import 'group_currencies.dart';
import '../groups/group_provider.dart';
import 'expense_category_ui.dart';
import 'expenses_provider.dart';
import 'record_date_field.dart';
import 'split_editor.dart';
import '../../core/sync/record_signing.dart' show RecordKind;
import 'record_attribution.dart';
import 'record_actions.dart';
import 'record_undo.dart' show UndoableWrite;
import '../../core/widgets/action_error.dart';

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
  final _noteCtrl = TextEditingController();

  /// G16: the category's wire id — kept verbatim on edit (an unknown id from
  /// a newer peer is shown as "other" but saved unchanged unless picked).
  String? _category;

  /// The user picked (or cleared) a category: stop suggesting one from the
  /// description. Edits never get suggestions.
  bool _categoryChosen = false;

  /// G47: the group's custom categories (hidden ones too — they label the
  /// edited expense; the selector offers only the visible ones).
  List<CustomCategory> _customCategories = const [];

  bool get _isEdit => widget.initial != null;

  /// G49: the day the expense happened (local midnight) — today for a new
  /// expense, the edited one's display day otherwise.
  late DateTime _day;
  late final DateTime _initialDay;

  // null = still loading. Loaded from the local DB (roomless).
  List<MemberModel>? _members;
  String? _paidBy; // participant id of the payer
  String _currency = 'EUR';
  String _initialCurrency = 'EUR'; // as loaded — stays selectable

  /// G66: the currency picker's first section (group currency, used ones …).
  List<String> _suggestedCurrencies = const [];

  // The SplitEditor's current mode + inputs; resolved against the live amount.
  SplitPlan? _plan;

  /// G56: the form as it opened — leaving a changed form asks first.
  String? _initialPayer;
  String _initialAmountText = '';

  /// The SplitEditor pushes its starting plan once, then only on user
  /// interaction — so a second plan means the split was touched.
  int _planUpdates = 0;

  /// Set once the expense was saved, so the page's own pop never asks.
  bool _saved = false;

  bool get _dirty {
    if (_saved || _members == null) return false;
    final initial = widget.initial;
    return _descCtrl.text != (initial?.description ?? '') ||
        _amountCtrl.text != _initialAmountText ||
        _noteCtrl.text != (initial?.note ?? '') ||
        _category != initial?.category ||
        _currency != _initialCurrency ||
        _paidBy != _initialPayer ||
        _day != _initialDay ||
        _planUpdates > 1;
  }

  /// G56: "Discard changes?" — true = leave without saving.
  Future<void> _confirmDiscard() async {
    final l = context.l10n;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.discardChangesTitle),
        content: Text(l.discardChangesBody),
        actions: [
          TextButton(
            key: const Key('keepEditing'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.keepEditing),
          ),
          FilledButton(
            key: const Key('discardChanges'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.discard),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    setState(() => _saved = true); // nothing to protect any more
    Navigator.of(context).pop();
  }

  /// Accepts `,` and `.` as decimal separator (G12) — see
  /// [parseAmountCents]; the UI locale decides a lone grouping separator
  /// (`1.234` in German = 1234, G18 review).
  ///
  /// G66: rounded to the currency's decimals (whole yen); the unchanged
  /// prefill of an edited expense is its stored amount — a legacy non-whole
  /// JPY amount (stored in hundredths before G66) isn't rounded on save.
  int? get _parsedCents {
    final initial = widget.initial;
    if (initial != null &&
        _amountPrefilled &&
        _amountCtrl.text == _initialAmountText) {
      return initial.amountCents;
    }
    return parseAmountCents(
      _amountCtrl.text,
      locale: context.localeName,
      currency: _currency,
    );
  }

  /// The amount if it is a storable one (1 cent … [kMaxAmountCents]), else
  /// 0 — which no split accepts.
  int get _amountCents {
    final c = _parsedCents;
    return c != null && isValidAmountCents(c) ? c : 0;
  }

  Map<String, int>? get _initialSplit {
    final json = widget.initial?.splitsJson;
    if (json == null) return null;
    return tryParseSplit(json) ?? const {};
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _initialDay = initial?.displayDay ?? dayOf(DateTime.now());
    _day = _initialDay;
    if (initial != null) {
      _descCtrl.text = initial.description;
      _noteCtrl.text = initial.note ?? '';
      _category = initial.category;
      _categoryChosen = true;
    }
    _loadData();
    // G56: typing changes whether leaving needs a confirmation.
    for (final c in [_descCtrl, _amountCtrl, _noteCtrl]) {
      c.addListener(_refreshDirty);
    }
  }

  /// [_dirty] as of the last build (what `PopScope.canPop` shows).
  bool _wasDirty = false;

  void _refreshDirty() {
    if (_dirty != _wasDirty && mounted) setState(() {});
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
        currency: initial.currency,
      );
      _initialAmountText = _amountCtrl.text;
    }
  }

  Future<void> _loadData() async {
    final all = await ref.read(membersDaoProvider).getMembers(widget.roomId);
    final members = editorParticipants(
      groupId: widget.roomId,
      all: all,
      initial: widget.initial,
    );
    final group = await ref.read(groupsDaoProvider).getGroup(widget.roomId);
    final currency = widget.initial?.currency ?? group?.currency ?? 'EUR';
    final suggested = await groupCurrencySuggestions(
      ref,
      widget.roomId,
      selected: currency,
      groupCurrency: group?.currency,
    );
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
        _currency = currency;
        _initialCurrency = _currency;
        _suggestedCurrencies = suggested;
        _paidBy = defaultPayer;
        _initialPayer = defaultPayer;
        _customCategories = group?.categories ?? const [];
      });
    }
  }

  /// G47: "New category…" — name + icon, written to the group meta (synced
  /// to every member), then selected for this expense.
  Future<void> _createCategory() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (_customCategories.length >= kMaxCustomCategories) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.categoryLimitReached(kMaxCustomCategories))),
      );
      return;
    }
    final errors = ActionErrors.of(context);
    final input = await showCategoryDialog(
      context,
      existing: _customCategories,
    );
    if (input == null || !mounted) return;
    final editor = ref.read(groupEditorProvider.notifier);
    final id = await editor.addCategory(
      widget.roomId,
      name: input.name,
      icon: input.icon,
    );
    if (!mounted) return;
    final error = ref.read(groupEditorProvider).error;
    if (id == null || error != null) {
      if (error != null) errors.show(error);
      return;
    }
    final group = await ref.read(groupsDaoProvider).getGroup(widget.roomId);
    if (!mounted) return;
    setState(() {
      _customCategories = group?.categories ?? _customCategories;
      _category = id;
      _categoryChosen = true;
    });
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(List<MemberModel> members) async {
    if (!_formKey.currentState!.validate()) return;
    final paidBy = _paidBy;
    final amountCents = _amountCents;
    final result = _plan?.resolve(amountCents);
    if (paidBy == null || result == null || !result.isValid) return;

    // U11: an untouched split of an unchanged amount is saved exactly as it
    // was stored (same people, cents and key order) — re-resolving it could
    // move a remainder cent (largest-remainder ties follow the row order).
    final initialSplit = _initialSplit;
    final keepSplit =
        widget.initial != null &&
        initialSplit != null &&
        initialSplit.isNotEmpty &&
        _planUpdates <= 1 &&
        amountCents == widget.initial!.amountCents &&
        initialSplit.values.fold<int>(0, (a, b) => a + b) == amountCents;
    final splits = keepSplit ? initialSplit : result.shares;

    final snack = UndoSnack.of(context, ref);
    final errors = ActionErrors.of(context);
    final l = context.l10n;
    final description = _descCtrl.text.trim();
    final initial = widget.initial;
    final UndoableWrite? write;
    if (initial != null) {
      // Edit: same record id and creation time, fresh clock; payer editable.
      write = await ref
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
            category: _category,
            note: _noteCtrl.text,
            // G49: unchanged day → keep the stored date as it is.
            date: _day == _initialDay
                ? initial.date
                : storedExpenseDate(_day, initial.createdAt),
          );
    } else {
      write = await ref
          .read(expenseAdderProvider.notifier)
          .addExpense(
            roomId: widget.roomId,
            description: _descCtrl.text.trim(),
            amountCents: amountCents,
            currency: _currency,
            paidBy: paidBy,
            splits: splits,
            category: _category,
            note: _noteCtrl.text,
            day: _day,
          );
    }

    if (write == null) {
      final error = mounted ? ref.read(expenseAdderProvider).error : null;
      if (error != null) errors.show(error);
      return;
    }
    // G67 (U13): "Added …" / "Saved …" · Undo, on the group page.
    snack.show(
      initial == null
          ? l.expenseAddedSnack(description)
          : l.expenseUpdatedSnack(description),
      write,
    );
    if (mounted) {
      setState(() => _saved = true);
      context.pop();
    }
  }

  /// G67 (U13): *Delete* from the edit form — the same confirmation and
  /// "Deleted · Undo" as the list's ⋮ → *Delete*; leaves the form.
  Future<void> _delete() async {
    final initial = widget.initial;
    if (initial == null) return;
    if (!await confirmDeleteExpense(context, initial) || !mounted) return;
    final deleted = await deleteExpenseFlow(
      context,
      ref,
      initial,
      skipConfirm: true,
    );
    if (deleted && mounted) {
      setState(() => _saved = true);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final adderState = ref.watch(expenseAdderProvider);
    ref.watch(groupEditorProvider); // G47: keep "New category…" alive
    final members = _members;
    final l = context.l10n;
    final theme = Theme.of(context);
    final canSubmit =
        members != null &&
        !adderState.isLoading &&
        members.isNotEmpty &&
        (_plan?.resolve(_amountCents).isValid ?? false);

    // G56: ← / system back on a changed form asks before throwing it away.
    _wasDirty = _dirty;
    return PopScope<Object?>(
      canPop: !_wasDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? l.editExpense : l.addExpense),
          actions: [
            if (_isEdit)
              IconButton(
                key: const Key('deleteExpenseButton'),
                tooltip: l.deleteExpenseAction,
                icon: const Icon(Icons.delete_outline),
                onPressed: adderState.isLoading ? null : _delete,
              ),
          ],
        ),
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
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  labelText: l.descriptionLabel,
                                  prefixIcon: Icon(
                                    categoryIcon(
                                      resolveCategory(
                                        _category,
                                        _customCategories,
                                      ),
                                    ),
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? l.required
                                    : null,
                                // G16: suggest a category from the description
                                // until the user picks one themselves.
                                onChanged: (v) {
                                  if (_categoryChosen) return;
                                  final s = suggestCategory(v)?.wire;
                                  if (s != _category) {
                                    setState(() => _category = s);
                                  }
                                },
                              ),
                              const SizedBox(height: Insets.m),
                              CategoryPicker(
                                selected: _category,
                                custom: _customCategories,
                                onChanged: (c) => setState(() {
                                  _categoryChosen = true;
                                  _category = c;
                                }),
                                onCreate: _createCategory,
                              ),
                              const SizedBox(height: Insets.l),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 108,
                                    // G66: any ISO-4217 currency (search);
                                    // the expense's own one stays offered.
                                    child: CurrencyField(
                                      key: const Key('expenseCurrency'),
                                      value: _currency,
                                      suggested: _suggestedCurrencies,
                                      onChanged: (c) =>
                                          setState(() => _currency = c),
                                    ),
                                  ),
                                  const SizedBox(width: Insets.m),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _amountCtrl,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontFeatures: kTabularFigures,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: l.amountLabel,
                                        hintText: formatAmountInput(
                                          0,
                                          context.localeName,
                                          currency: _currency,
                                        ),
                                        // G18 review: how the input was read
                                        // (e.g. "= 1.234,00 €").
                                        helperText: _amountCents > 0
                                            ? l.amountPreview(
                                                context.money(
                                                  _amountCents,
                                                  _currency,
                                                ),
                                              )
                                            : null,
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
                                        final c = _parsedCents;
                                        if (c == null) return l.invalidNumber;
                                        if (c < 1) {
                                          return l.amountMustBePositive;
                                        }
                                        if (c > kMaxAmountCents) {
                                          return l.amountTooLarge;
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
                                          // U11: a former member who paid
                                          // this (edited) expense.
                                          if (!m.isActive) ...[
                                            const SizedBox(width: Insets.s),
                                            Text(
                                              l.formerMemberTag,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                ],
                                onChanged: (v) => setState(() => _paidBy = v),
                              ),
                              const SizedBox(height: Insets.l),
                              RecordDateField(
                                day: _day,
                                onChanged: (d) => setState(() => _day = d),
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
                                onPlanChanged: (p) => setState(() {
                                  _plan = p;
                                  _planUpdates++;
                                }),
                                // G61: "Set total to the sum".
                                onSetTotal: (cents) => setState(
                                  () => _amountCtrl.text = formatAmountInput(
                                    cents,
                                    context.localeName,
                                    currency: _currency,
                                  ),
                                ),
                              ),
                              const SizedBox(height: Insets.xl),
                              // G16: optional free-text note.
                              TextFormField(
                                key: const Key('expenseNote'),
                                controller: _noteCtrl,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                minLines: 1,
                                maxLines: 5,
                                maxLength: kMaxNoteLength,
                                decoration: InputDecoration(
                                  labelText: l.noteLabel,
                                  prefixIcon: const Icon(Icons.notes),
                                ),
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
      ),
    );
  }
}

/// U11: the participants the expense form offers — the group's **active**
/// ones, plus (on edit) every participant [initial] itself references (its
/// payer and split keys) even if they left or were removed, so editing only
/// the description never drops them from the split or empties the payer.
/// Former ones come last; a referenced id with no participant row at all is
/// kept as a bare (former) entry. A new expense offers active ones only.
@visibleForTesting
List<MemberModel> editorParticipants({
  required String groupId,
  required List<MemberModel> all,
  ExpenseModel? initial,
}) {
  final referenced = <String>{
    if (initial != null) initial.paidBy,
    if (initial != null) ...?tryParseSplit(initial.splitsJson)?.keys,
  };
  final active = [
    for (final m in all)
      if (m.isActive) m,
  ];
  final former = [
    for (final m in all)
      if (!m.isActive && referenced.contains(m.userId)) m,
  ];
  final known = {for (final m in all) m.userId};
  return [
    ...active,
    ...former,
    for (final id in referenced)
      if (!known.contains(id))
        MemberModel(
          groupId: groupId,
          userId: id,
          status: 'removed',
          updatedAt: 0,
        ),
  ];
}
