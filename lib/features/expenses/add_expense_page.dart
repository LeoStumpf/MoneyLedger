import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/large_text.dart';
import '../../core/l10n/l10n.dart';
import '../../core/session/app_session.dart' show localModeActiveProvider;
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
import 'split_calculator.dart' show splitEqually;
import 'split_editor.dart';
import '../../core/sync/record_signing.dart' show RecordKind;
import 'record_attribution.dart';
import 'record_actions.dart';
import 'record_undo.dart' show UndoableWrite;
import '../../core/widgets/action_error.dart';
import '../receipts/receipt_field.dart';
import '../receipts/receipt_store.dart';

/// Add (default) or edit an expense — pass [initial] to prefill the form and
/// save the submit as an LWW edit of the same record.
/// G75: the route of the add form prefilled with a copy (`extra`: the
/// [ExpenseModel] to duplicate).
String duplicateExpenseLocation(String groupId) =>
    '/groups/$groupId/expenses/duplicate';

class AddExpensePage extends ConsumerStatefulWidget {
  final String roomId;

  /// The expense being edited (null = a new one).
  final ExpenseModel? initial;

  /// G75: *Duplicate* — a **new** expense prefilled with this one's
  /// description, amount, currency, payer, split, category and note (dated
  /// today; a new id on *Add*). Nothing is written before *Add*. Ignored
  /// when [initial] is set.
  final ExpenseModel? copyFrom;

  const AddExpensePage({
    super.key,
    required this.roomId,
    this.initial,
    this.copyFrom,
  });

  @override
  ConsumerState<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends ConsumerState<AddExpensePage> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  /// G71 (U12): *Next* on the description's keyboard jumps to the amount.
  final _amountFocus = FocusNode();

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

  /// What the form is prefilled from: the edited expense, or (G75) the one
  /// being duplicated.
  ExpenseModel? get _source => widget.initial ?? widget.copyFrom;

  /// G75: the duplicated expense's split, limited to people still in the
  /// group (set in [_loadData]).
  Map<String, int>? _copySplit;

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

  /// G78: the receipt photo the form shows (this device only) — the edited
  /// expense's stored one, or a new pick. Written / deleted on save.
  Uint8List? _receipt;

  /// G78: the photo was picked, replaced or removed in this form.
  bool _receiptChanged = false;

  bool get _dirty => _formDirty || (!_saved && _receiptChanged);

  /// [_dirty] apart from the receipt photo (G78: a photo-only change of an
  /// edited expense writes no new version — the photo isn't part of it).
  bool get _formDirty {
    if (_saved || _members == null) return false;
    final initial = _source;
    return _descCtrl.text != (initial?.description ?? '') ||
        _amountCtrl.text != _initialAmountText ||
        _noteCtrl.text != (initial?.note ?? '') ||
        _category != initial?.category ||
        _currency != _initialCurrency ||
        _paidBy != _initialPayer ||
        _day != _initialDay ||
        _planUpdates > 1;
  }

  /// G75: replaces this edit form with the add form prefilled with a copy
  /// of the stored expense; a changed form asks before its edits are lost.
  Future<void> _duplicate() async {
    final initial = widget.initial;
    if (initial == null) return;
    if (_dirty) {
      if (!await _askDiscard() || !mounted) return;
    }
    setState(() => _saved = true); // leaving on purpose
    context.pushReplacement(
      duplicateExpenseLocation(widget.roomId),
      extra: initial,
    );
  }

  /// G56: "Discard changes?" — leaves without saving on *Discard*.
  Future<void> _confirmDiscard() async {
    if (!await _askDiscard() || !mounted) return;
    setState(() => _saved = true); // nothing to protect any more
    Navigator.of(context).pop();
  }

  /// G56: asks "Discard changes?" — true = throw the edits away.
  Future<bool> _askDiscard() async {
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
    return discard == true;
  }

  /// Accepts `,` and `.` as decimal separator (G12) — see
  /// [parseAmountCents]; the UI locale decides a lone grouping separator
  /// (`1.234` in German = 1234, G18 review).
  ///
  /// G66: rounded to the currency's decimals (whole yen); the unchanged
  /// prefill of an edited expense is its stored amount — a legacy non-whole
  /// JPY amount (stored in hundredths before G66) isn't rounded on save.
  int? get _parsedCents {
    final initial = _source;
    if (initial != null &&
        _amountPrefilled &&
        _amountCtrl.text == _initialAmountText) {
      return initial.amountCents;
    }
    // G75: a small expression ("12,50+8") is worked out.
    return parseAmountInput(
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
    if (!_isEdit && widget.copyFrom != null) return _copySplit;
    final json = widget.initial?.splitsJson;
    if (json == null) return null;
    return tryParseSplit(json) ?? const {};
  }

  @override
  void initState() {
    super.initState();
    // G75: a duplicate is dated today, like any new expense.
    _initialDay = widget.initial?.displayDay ?? dayOf(DateTime.now());
    _day = _initialDay;
    final initial = _source;
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
    // Prefill the edited (or duplicated, G75) amount once, with the
    // locale's decimal separator.
    final initial = _source;
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
    final copy = _isEdit ? null : widget.copyFrom;
    final currency =
        widget.initial?.currency ?? copy?.currency ?? group?.currency ?? 'EUR';
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
    final activeIds = {
      for (final m in members)
        if (m.isActive) m.userId,
    };
    // G75: a duplicate keeps its payer while they are still in the group.
    final copiedPayer = copy != null && activeIds.contains(copy.paidBy)
        ? copy.paidBy
        : null;
    final defaultPayer =
        widget.initial?.paidBy ??
        copiedPayer ??
        self?.userId ??
        (members.isNotEmpty ? members.first.userId : null);
    final copySplit = copy == null
        ? null
        : duplicateSplit(copy, activeIds, step: currencyStep(currency));
    // G78: the edited expense's photo (a duplicate starts without one).
    final edited = widget.initial;
    final receipt = edited != null && ref.read(receiptsSupportedProvider)
        ? await ref.read(receiptIndexProvider.notifier).read(edited.id)
        : null;
    if (mounted) {
      setState(() {
        _members = members;
        _copySplit = copySplit;
        // Edit keeps the expense's own currency; new ones default to the
        // group's (G29 — each expense may use any currency).
        _currency = currency;
        _initialCurrency = _currency;
        _suggestedCurrencies = suggested;
        _paidBy = defaultPayer;
        _initialPayer = defaultPayer;
        _customCategories = group?.categories ?? const [];
        if (!_receiptChanged) _receipt = receipt;
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
    _amountFocus.dispose();
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
    // G78: captured before the first await (G19); applied after the write.
    final receipts = ref.read(receiptIndexProvider.notifier);
    final receipt = _receipt;
    final receiptChanged = _receiptChanged;
    final initial = widget.initial;
    if (initial != null && receiptChanged && !_formDirty) {
      // G78: only the photo changed — nothing to sync, no new version.
      try {
        if (receipt != null) {
          await receipts.save(initial.id, receipt);
        } else {
          await receipts.remove(initial.id);
        }
      } catch (e) {
        errors.show(e);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('receiptSavedSnack'),
          content: Text(
            receipt != null ? l.receiptSavedSnack : l.receiptRemovedSnack,
          ),
        ),
      );
      setState(() => _saved = true);
      context.pop();
      return;
    }
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
    // G78: the photo follows the saved expense (by its id) — a new one
    // only now that it has an id, an edit's change only on *Save*.
    if (receiptChanged || (initial == null && receipt != null)) {
      try {
        if (receipt != null) {
          await receipts.save(write.recordId, receipt);
        } else {
          await receipts.remove(write.recordId);
        }
      } catch (e) {
        errors.show(e, what: l.receiptSaveFailed);
      }
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
    final local = ref.read(localModeActiveProvider);
    if (!await confirmDeleteExpense(context, initial, localOnly: local) ||
        !mounted) {
      return;
    }
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
            // G75: *Duplicate* — the add form with a copy of the stored
            // expense (unsaved edits here are not copied; a changed form
            // asks first).
            if (_isEdit)
              IconButton(
                key: const Key('duplicateExpenseButton'),
                tooltip: l.duplicateExpense,
                icon: const Icon(Icons.copy_outlined),
                onPressed: adderState.isLoading ? null : _duplicate,
              ),
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
                                key: const Key('expenseDescription'),
                                controller: _descCtrl,
                                // G71 (U12): a new expense starts typing
                                // right away; *Next* goes to the amount.
                                autofocus: !_isEdit,
                                textInputAction: TextInputAction.next,
                                onEditingComplete: _amountFocus.requestFocus,
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
                              const SizedBox(height: Insets.l),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    // DEV-I: grows with the font size
                                    // ("EU" faded at 200 %).
                                    width: scaledCellWidth(context, 108, 150),
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
                                      key: const Key('expenseAmount'),
                                      controller: _amountCtrl,
                                      focusNode: _amountFocus,
                                      // G71 (U12): *Done* closes the
                                      // keyboard — payer, date and split
                                      // follow.
                                      textInputAction: TextInputAction.done,
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
                              // G71 (U12): after the date — it is suggested
                              // from the description anyway.
                              const SizedBox(height: Insets.l),
                              CategoryPicker(
                                selected: _category,
                                custom: _customCategories,
                                onChanged: (c) => setState(() {
                                  _categoryChosen = true;
                                  _category = c;
                                }),
                                onCreate: _createCategory,
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
                              // G78: a receipt photo, this device only
                              // (Android; hidden on the web / in the demo).
                              if (ref.watch(receiptsSupportedProvider)) ...[
                                const SizedBox(height: Insets.l),
                                ReceiptField(
                                  photo: _receipt,
                                  onChanged: (bytes) => setState(() {
                                    _receipt = bytes;
                                    _receiptChanged = true;
                                  }),
                                ),
                              ],
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

/// G75: the split a duplicate of [source] opens with — its own split while
/// everyone in it is still in the group ([activeIds]); if some left, the
/// amount spread equally over the ones still here (rounded to [step]); null
/// (the form's default: everyone, equally) when nobody of it is left or the
/// stored split can't be read.
@visibleForTesting
Map<String, int>? duplicateSplit(
  ExpenseModel source,
  Set<String> activeIds, {
  int step = 1,
}) {
  final split = tryParseSplit(source.splitsJson);
  if (split == null || split.isEmpty) return null;
  final kept = [
    for (final id in split.keys)
      if (activeIds.contains(id)) id,
  ];
  if (kept.isEmpty) return null;
  if (kept.length == split.length) return split;
  return splitEqually(source.amountCents, kept, step: step);
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
