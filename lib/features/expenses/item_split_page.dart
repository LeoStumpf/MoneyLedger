import 'package:flutter/material.dart';

import '../../core/widgets/large_text.dart';
import '../../core/l10n/l10n.dart';
import '../../core/sync/record_validation.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/person_avatar.dart';
import '../../models/member_model.dart';
import 'split_calculator.dart';

/// G77: one receipt line as typed — kept by the [SplitEditor] while the
/// expense form is open (so *Back* or reopening the item editor loses
/// nothing), never stored: only the resolved split is saved.
class ItemDraft {
  String name;
  String amountText;
  Set<String> people;
  ItemDraft({this.name = '', this.amountText = '', required this.people});
}

/// G77: the item editor's inputs (owned by the [SplitEditor], mutated by
/// [ItemSplitPage]).
class ItemSplitDraft {
  final List<ItemDraft> items = [];
  ItemRestMode restMode = ItemRestMode.proportional;
}

/// What *Use this split* returns: the receipt [total] (changed when the user
/// chose *Set total to the sum*) and the Exact [split] summing to it.
class ItemizedSplit {
  final int total;
  final Map<String, int> split;
  const ItemizedSplit(this.total, this.split);
}

/// G77: splits a receipt item by item. Each item (name optional, amount —
/// the G75 calculator works — and who shares it, default everyone) is split
/// equally among its people; the rest (tax, tip, what wasn't itemized) is
/// spread proportionally to each person's items or equally
/// ([splitByItems]). Pops with an [ItemizedSplit]; the [SplitEditor] shows
/// it as Exact amounts.
class ItemSplitPage extends StatefulWidget {
  /// Who can share an item (the expense's active participants).
  final List<MemberModel> members;
  final int totalCents;
  final String currency;
  final ItemSplitDraft draft;

  /// Whether *Set total to the sum* is offered (the form owns the amount).
  final bool canSetTotal;

  const ItemSplitPage({
    super.key,
    required this.members,
    required this.totalCents,
    required this.currency,
    required this.draft,
    this.canSetTotal = true,
  });

  @override
  State<ItemSplitPage> createState() => _ItemSplitPageState();
}

class _ItemSplitPageState extends State<ItemSplitPage> {
  late int _total = widget.totalCents;
  final _nameCtrl = <ItemDraft, TextEditingController>{};
  final _amountCtrl = <ItemDraft, TextEditingController>{};

  List<ItemDraft> get _items => widget.draft.items;

  @override
  void initState() {
    super.initState();
    if (_items.isEmpty) _items.add(_newItem());
    for (final item in _items) {
      _controllersFor(item);
    }
  }

  ItemDraft _newItem() =>
      ItemDraft(people: {for (final m in widget.members) m.userId});

  void _controllersFor(ItemDraft item) {
    _nameCtrl[item] = TextEditingController(text: item.name)
      ..addListener(() => item.name = _nameCtrl[item]!.text);
    _amountCtrl[item] = TextEditingController(text: item.amountText);
  }

  @override
  void dispose() {
    for (final c in [..._nameCtrl.values, ..._amountCtrl.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addItem() {
    final item = _newItem();
    _controllersFor(item);
    setState(() => _items.add(item));
  }

  void _removeItem(ItemDraft item) {
    setState(() {
      _items.remove(item);
      if (_items.isEmpty) {
        final fresh = _newItem();
        _controllersFor(fresh);
        _items.add(fresh);
      }
    });
    // Disposed after the frame that no longer shows their fields.
    final name = _nameCtrl.remove(item);
    final amount = _amountCtrl.remove(item);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name?.dispose();
      amount?.dispose();
    });
  }

  /// The item's amount in cents; null when blank or not a valid amount.
  int? _cents(ItemDraft item) {
    final text = item.amountText.trim();
    if (text.isEmpty) return null;
    final c = parseAmountInput(
      text,
      locale: context.localeName,
      currency: widget.currency,
    );
    return c != null && isValidAmountCents(c) ? c : null;
  }

  bool _invalid(ItemDraft item) =>
      item.amountText.trim().isNotEmpty && _cents(item) == null;

  /// The items with an amount, people in the members' order.
  List<SplitItem> _splitItems() => [
    for (final item in _items)
      if (_cents(item) case final c?)
        SplitItem(c, [
          for (final m in widget.members)
            if (item.people.contains(m.userId)) m.userId,
        ]),
  ];

  String _money(int cents) => context.money(cents, widget.currency);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final items = _splitItems();
    final sum = itemsSum(items);
    final blocked = _items.any(_invalid) || items.any((i) => i.people.isEmpty);
    final result = blocked
        ? null
        : splitByItems(
            _total,
            items,
            restMode: widget.draft.restMode,
            step: currencyStep(widget.currency),
          );

    return Scaffold(
      appBar: AppBar(title: Text(l.itemsTitle)),
      body: SafeArea(
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Insets.page,
              Insets.s,
              Insets.page,
              Insets.xl,
            ),
            children: [
              Text(
                _total > 0
                    ? l.itemsReceiptTotal(_money(_total))
                    : l.itemsNoTotal,
                key: const Key('itemsTotal'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: kTabularFigures,
                ),
              ),
              const SizedBox(height: Insets.xs),
              Text(
                l.itemsNotStoredHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Insets.m),
              for (final (i, item) in _items.indexed) _itemCard(i, item),
              const SizedBox(height: Insets.s),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: const Key('itemsAdd'),
                  onPressed: _addItem,
                  icon: const Icon(Icons.add),
                  label: Text(l.itemAdd),
                ),
              ),
              const SizedBox(height: Insets.l),
              _restSection(sum, items.isEmpty),
              if (result != null) ...[
                const SizedBox(height: Insets.l),
                Semantics(
                  header: true,
                  child: Text(l.itemsResult, style: theme.textTheme.titleSmall),
                ),
                const SizedBox(height: Insets.xs),
                for (final m in widget.members)
                  if ((result[m.userId] ?? 0) > 0)
                    _resultRow(m, result[m.userId]!),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.page,
            Insets.s,
            Insets.page,
            Insets.s,
          ),
          child: FilledButton(
            key: const Key('itemsApply'),
            onPressed: result == null
                ? null
                : () =>
                      Navigator.of(context).pop(ItemizedSplit(_total, result)),
            child: Text(l.itemsApply),
          ),
        ),
      ),
    );
  }

  Widget _itemCard(int index, ItemDraft item) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final cents = _cents(item);
    final everyone = widget.members.every(
      (m) => item.people.contains(m.userId),
    );
    final n = item.people.length;
    final preview = cents != null ? l.amountPreview(_money(cents)) : null;
    String? status;
    var statusIsError = false;
    if (n == 0) {
      status = l.splitSelectAtLeastOne;
      statusIsError = true;
    } else if (cents != null && n > 1) {
      final shares = splitEqually(
        cents,
        item.people.toList(),
        step: currencyStep(widget.currency),
      ).values;
      status = l.itemEach(_money(shares.reduce((a, b) => a > b ? a : b)));
    }
    final nameField = TextField(
      key: Key('itemName-$index'),
      controller: _nameCtrl[item],
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(labelText: l.itemLabel(index + 1)),
    );
    final amountField = TextField(
      key: Key('itemAmount-$index'),
      controller: _amountCtrl[item],
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      style: const TextStyle(fontFeatures: kTabularFigures),
      decoration: InputDecoration(
        labelText: l.amountLabel,
        suffixText: widget.currency,
        helperText: preview,
        errorText: _invalid(item) ? l.invalidNumber : null,
      ),
      onChanged: (t) => setState(() => item.amountText = t),
    );
    final removeButton = IconButton(
      key: Key('itemRemove-$index'),
      tooltip: l.itemRemove,
      icon: const Icon(Icons.delete_outline),
      onPressed: () => _removeItem(item),
    );
    return Card(
      key: ValueKey('item-$index'),
      margin: const EdgeInsets.only(bottom: Insets.s),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Insets.m, Insets.s, 0, Insets.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // DEV-I: at a large font size name and amount get a line
            // each — side by side the amount cell showed "0EUR" for 1300.
            if (isLargeText(context)) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: nameField),
                  removeButton,
                ],
              ),
              const SizedBox(height: Insets.s),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Insets.m),
                child: amountField,
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: nameField),
                  const SizedBox(width: Insets.s),
                  Expanded(flex: 2, child: amountField),
                  removeButton,
                ],
              ),
            const SizedBox(height: Insets.s),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Insets.m),
              child: Wrap(
                spacing: Insets.s,
                runSpacing: Insets.xs,
                children: [
                  FilterChip(
                    key: Key('itemEveryone-$index'),
                    label: Text(l.itemEveryone),
                    selected: everyone,
                    onSelected: (_) => setState(() {
                      item.people = everyone
                          ? <String>{}
                          : {for (final m in widget.members) m.userId};
                    }),
                  ),
                  for (final m in widget.members)
                    FilterChip(
                      key: Key('itemPerson-$index-${m.userId}'),
                      label: Text(
                        m.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: item.people.contains(m.userId),
                      onSelected: (on) => setState(() {
                        item.people = {...item.people};
                        if (on) {
                          item.people.add(m.userId);
                        } else {
                          item.people.remove(m.userId);
                        }
                      }),
                    ),
                ],
              ),
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  Insets.xs,
                  Insets.xs,
                  Insets.m,
                  0,
                ),
                child: Text(
                  status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusIsError
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The rest (or "too much") with *Set total to the sum* / the rest mode.
  Widget _restSection(int sum, bool noItems) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final strong = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: kTabularFigures,
    );
    Widget? setTotal() => widget.canSetTotal && isValidAmountCents(sum)
        ? TextButton(
            key: const Key('itemsSetTotal'),
            onPressed: () => setState(() => _total = sum),
            child: Text(l.splitSetTotalToSum),
          )
        : null;
    Widget row(Widget label, List<Widget?> actions) => Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Insets.s,
      children: [label, for (final a in actions) ?a],
    );

    if (noItems) return Text(l.itemsEnterOne, style: small);
    if (_total <= 0) {
      return row(Text(l.splitEnterAmountFirst, style: small), [setTotal()]);
    }
    final rest = _total - sum;
    if (rest < 0) {
      return row(
        Text(
          l.splitTooMuch(_money(-rest)),
          key: const Key('itemsRemaining'),
          style: strong?.copyWith(color: theme.colorScheme.error),
        ),
        [setTotal()],
      );
    }
    if (rest == 0) {
      return Text(
        l.splitAddsUpToTotal,
        style: small?.copyWith(color: theme.colorScheme.primary),
      );
    }
    final mode = widget.draft.restMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.itemsRest(_money(rest)),
          key: const Key('itemsRemaining'),
          style: strong,
        ),
        const SizedBox(height: Insets.s),
        SegmentedButton<ItemRestMode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: ItemRestMode.proportional,
              label: Text(l.itemsRestProportional),
            ),
            ButtonSegment(
              value: ItemRestMode.equal,
              label: Text(l.itemsRestEqually),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) =>
              setState(() => widget.draft.restMode = s.first),
        ),
        const SizedBox(height: Insets.xs),
        Text(
          mode == ItemRestMode.proportional
              ? l.itemsRestProportionalHint
              : l.itemsRestEqualHint,
          style: small?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _resultRow(MemberModel m, int cents) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.xs),
        child: Row(
          children: [
            PersonAvatar(id: m.userId, name: m.label, size: 30),
            const SizedBox(width: Insets.m),
            Expanded(
              child: Text(
                m.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(width: Insets.s),
            Text(
              _money(cents),
              key: Key('itemsResult-${m.userId}'),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFeatures: kTabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
