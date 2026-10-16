import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';
import '../../core/sync/record_validation.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/person_avatar.dart';
import '../../models/member_model.dart';
import 'split_calculator.dart';

/// How an expense is divided. Persisted only as the resolved cents map — the
/// mode itself is not stored; on edit it is inferred (see [SplitEditor]).
enum SplitMode { equal, exact, shares, percent }

/// A resolved split: the `{participantId: cents}` map and whether it is valid.
class SplitResult {
  final Map<String, int> shares;
  final bool isValid;
  const SplitResult(this.shares, this.isValid);
}

/// An immutable snapshot of the editor's mode + raw inputs that can resolve to a
/// [SplitResult] for **any** total. The parent holds this and resolves it
/// against the live amount on demand, so changing the amount never leaves a
/// stale split behind. All modes resolve through `split_calculator.dart`, so the
/// shares always sum to the total exactly.
class SplitPlan {
  final SplitMode mode;
  final List<String> included; // equal
  final Map<String, int> exact; // exact: participant -> cents
  final Map<String, int> weights; // shares
  final Map<String, num> percents; // percent

  const SplitPlan({
    required this.mode,
    this.included = const [],
    this.exact = const {},
    this.weights = const {},
    this.percents = const {},
  });

  /// The split of [total] — never valid for a total outside 1 cent …
  /// [kMaxAmountCents] (G18 review: no zero / negative expenses).
  SplitResult resolve(int total) {
    final r = _resolve(total);
    return isValidAmountCents(total) ? r : SplitResult(r.shares, false);
  }

  SplitResult _resolve(int total) {
    switch (mode) {
      case SplitMode.equal:
        return SplitResult(splitEqually(total, included), included.isNotEmpty);
      case SplitMode.exact:
        final valid = exact.isNotEmpty && remainingForExact(total, exact) == 0;
        return SplitResult(Map.of(exact), valid);
      case SplitMode.shares:
        return SplitResult(splitByShares(total, weights), weights.isNotEmpty);
      case SplitMode.percent:
        final sum = percents.values.fold<num>(0, (a, b) => a + b);
        final valid = percents.isNotEmpty && (sum - 100).abs() < 0.01;
        return SplitResult(splitByPercent(total, percents), valid);
    }
  }
}

/// Lets the user divide an expense one of four ways — equally (with per-person
/// include checkboxes), by exact amounts, by integer weights, or by percentage.
/// Reports a [SplitPlan] via [onPlanChanged] whenever the user changes anything;
/// the parent resolves it against the current amount. [totalCents] is used only
/// for the live per-person previews. Excluded participants are absent from the
/// resolved map.
class SplitEditor extends StatefulWidget {
  final List<MemberModel> members;
  final int totalCents;
  final String currency;

  /// Resolved cents map of the expense being edited; drives mode inference and
  /// prefill. Null for a new expense (defaults to Equal across everyone).
  final Map<String, int>? initialSplit;
  final ValueChanged<SplitPlan> onPlanChanged;

  const SplitEditor({
    super.key,
    required this.members,
    required this.totalCents,
    required this.currency,
    required this.onPlanChanged,
    this.initialSplit,
  });

  @override
  State<SplitEditor> createState() => _SplitEditorState();
}

class _SplitEditorState extends State<SplitEditor> {
  late SplitMode _mode;
  late Set<String> _included; // Equal mode: who is in
  final _exactCtrl = <String, TextEditingController>{};
  final _shareCtrl = <String, TextEditingController>{};
  final _percentCtrl = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final m in widget.members) {
      _exactCtrl[m.userId] = TextEditingController();
      _shareCtrl[m.userId] = TextEditingController();
      _percentCtrl[m.userId] = TextEditingController();
    }

    final initial = widget.initialSplit;
    if (initial != null && initial.isNotEmpty) {
      _included = initial.keys.toSet();
      if (isEqualSplit(initial)) {
        _mode = SplitMode.equal;
      } else {
        // Any other distribution reopens as editable exact amounts
        // (prefilled in didChangeDependencies, in the locale's format).
        _mode = SplitMode.exact;
      }
    } else {
      _mode = SplitMode.equal;
      _included = {for (final m in widget.members) m.userId};
    }

    // Push the starting plan once the first frame is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPlanChanged(_plan());
    });
  }

  bool _exactPrefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final initial = widget.initialSplit;
    if (!_exactPrefilled && _mode == SplitMode.exact && initial != null) {
      _exactPrefilled = true;
      final locale = context.localeName;
      initial.forEach(
        (id, cents) => _exactCtrl[id]?.text = formatAmountInput(cents, locale),
      );
    }
  }

  String _money(int cents) => context.money(cents, widget.currency);

  @override
  void dispose() {
    for (final c in [
      ..._exactCtrl.values,
      ..._shareCtrl.values,
      ..._percentCtrl.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// setState + push the fresh plan to the parent (called from interactions).
  void _update() {
    setState(() {});
    widget.onPlanChanged(_plan());
  }

  /// Snapshots the current mode + inputs into a [SplitPlan].
  SplitPlan _plan() {
    switch (_mode) {
      case SplitMode.equal:
        return SplitPlan(
          mode: _mode,
          included: [
            for (final m in widget.members)
              if (_included.contains(m.userId)) m.userId,
          ],
        );
      case SplitMode.exact:
        final exact = <String, int>{};
        for (final m in widget.members) {
          final cents = parseAmountCents(
            _exactCtrl[m.userId]!.text,
            locale: context.localeName,
          );
          if (cents != null && cents > 0) exact[m.userId] = cents;
        }
        return SplitPlan(mode: _mode, exact: exact);
      case SplitMode.shares:
        final weights = <String, int>{};
        for (final m in widget.members) {
          final w = int.tryParse(_shareCtrl[m.userId]!.text.trim());
          if (w != null && w > 0) weights[m.userId] = w;
        }
        return SplitPlan(mode: _mode, weights: weights);
      case SplitMode.percent:
        final percents = <String, num>{};
        for (final m in widget.members) {
          final p = parseLocalizedDecimal(_percentCtrl[m.userId]!.text);
          if (p != null && p > 0) percents[m.userId] = p;
        }
        return SplitPlan(mode: _mode, percents: percents);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _plan().resolve(widget.totalCents);
    final small = Theme.of(context).textTheme.bodySmall;
    final l = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<SplitMode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: SplitMode.equal, label: Text(l.splitEqual)),
            ButtonSegment(value: SplitMode.exact, label: Text(l.splitExact)),
            ButtonSegment(value: SplitMode.shares, label: Text(l.splitShares)),
            const ButtonSegment(value: SplitMode.percent, label: Text('%')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) {
            _mode = s.first;
            _update();
          },
        ),
        const SizedBox(height: Insets.s),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.m,
              vertical: Insets.s,
            ),
            child: Column(
              children: [
                for (final m in widget.members)
                  _row(m, result.shares[m.userId] ?? 0),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.s),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
          child: _statusLine(result, small),
        ),
      ],
    );
  }

  Widget _row(MemberModel m, int cents) {
    // G17: avatar + name (one line, ellipsized) on every row.
    final name = Expanded(
      child: Row(
        children: [
          PersonAvatar(id: m.userId, name: m.label, size: 30),
          const SizedBox(width: Insets.m),
          Expanded(
            child: Text(
              m.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
    // Natural width (right-aligned, so the column still lines up): a fixed
    // 96 dp box left the long names (MXID localparts) cut short next to a
    // mostly empty amount cell (G33).
    final preview = Container(
      constraints: const BoxConstraints(minWidth: 56),
      padding: const EdgeInsetsDirectional.only(start: Insets.s),
      alignment: AlignmentDirectional.centerEnd,
      child: Text(
        _money(cents),
        maxLines: 1,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontFeatures: kTabularFigures,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
    switch (_mode) {
      case SplitMode.equal:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Checkbox(
                value: _included.contains(m.userId),
                onChanged: (v) {
                  if (v == true) {
                    _included.add(m.userId);
                  } else {
                    _included.remove(m.userId);
                  }
                  _update();
                },
              ),
              name,
              preview,
            ],
          ),
        );
      case SplitMode.exact:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              name,
              SizedBox(
                width: 96,
                child: _numField(
                  _exactCtrl[m.userId]!,
                  suffix: widget.currency,
                  decimal: true,
                ),
              ),
            ],
          ),
        );
      case SplitMode.shares:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              name,
              SizedBox(
                width: 64,
                child: _numField(_shareCtrl[m.userId]!, decimal: false),
              ),
              preview,
            ],
          ),
        );
      case SplitMode.percent:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              name,
              SizedBox(
                width: 64,
                child: _numField(
                  _percentCtrl[m.userId]!,
                  suffix: '%',
                  decimal: true,
                ),
              ),
              preview,
            ],
          ),
        );
    }
  }

  Widget _numField(
    TextEditingController c, {
    String? suffix,
    required bool decimal,
  }) {
    return TextField(
      controller: c,
      textAlign: TextAlign.right,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
        ),
      ],
      decoration: InputDecoration(
        isDense: true,
        suffixText: suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.s,
          vertical: Insets.s + 2,
        ),
      ),
      onChanged: (_) => _update(),
    );
  }

  Widget _statusLine(SplitResult result, TextStyle? small) {
    final ok = Theme.of(context).colorScheme.primary;
    final bad = Theme.of(context).colorScheme.error;
    final l = context.l10n;
    switch (_mode) {
      case SplitMode.equal:
        final n = _included.length;
        return Text(
          n == 0 ? l.splitSelectAtLeastOne : l.splitEquallyAmong(n),
          style: small?.copyWith(color: n == 0 ? bad : null),
        );
      case SplitMode.exact:
        final remaining = remainingForExact(widget.totalCents, result.shares);
        return Text(
          remaining == 0 && result.isValid
              ? l.splitAddsUpToTotal
              : l.splitRemaining(_money(remaining)),
          style: small?.copyWith(color: result.isValid ? ok : bad),
        );
      case SplitMode.shares:
        return Text(
          result.isValid ? l.splitByWeight : l.splitEnterWeight,
          style: small?.copyWith(color: result.isValid ? null : bad),
        );
      case SplitMode.percent:
        return Text(
          result.isValid ? l.splitAddsUpTo100 : l.splitPercentMustTotal100,
          style: small?.copyWith(color: result.isValid ? ok : bad),
        );
    }
  }
}
