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

  /// G66: the currency's smallest amount in cents (`currencyStep`, 100 for
  /// JPY) — Equal / Shares / Percent hand out whole steps.
  final int step;

  const SplitPlan({
    required this.mode,
    this.included = const [],
    this.exact = const {},
    this.weights = const {},
    this.percents = const {},
    this.step = 1,
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
        return SplitResult(
          splitEqually(total, included, step: step),
          included.isNotEmpty,
        );
      case SplitMode.exact:
        final valid = exact.isNotEmpty && remainingForExact(total, exact) == 0;
        return SplitResult(Map.of(exact), valid);
      case SplitMode.shares:
        return SplitResult(
          splitByShares(total, weights, step: step),
          weights.isNotEmpty,
        );
      case SplitMode.percent:
        final sum = percents.values.fold<num>(0, (a, b) => a + b);
        final valid = percents.isNotEmpty && (sum - 100).abs() < 0.01;
        return SplitResult(splitByPercent(total, percents, step: step), valid);
    }
  }
}

/// Lets the user divide an expense one of four ways — equally (with per-person
/// include checkboxes), by exact amounts, by integer weights, or by percentage.
/// Reports a [SplitPlan] via [onPlanChanged] whenever the user changes anything;
/// the parent resolves it against the current amount. [totalCents] drives the
/// live per-person previews, the mode-switch prefill and the "fill the rest"
/// actions. Excluded participants are absent from the resolved map.
///
/// G59 defaults:
/// - **Switching mode converts the current split** (Equal → Exact: the equal
///   cents; → Shares: the simplest whole shares, 1 each for an equal split;
///   → Percent: matching percentages summing to exactly 100). Only a split that
///   is complete converts; an incomplete one leaves the target mode's own
///   inputs. A mere peek (switch away and back with no change and the same
///   total) returns to exactly what was there.
/// - **Exact / Percent: blank = open, 0 = not involved.** Rows the editor
///   filled itself (prefill, *Distribute*) count as open too until the user
///   types in them. *Distribute* spreads the total minus the typed rows over
///   the open rows (largest remainder); the per-row button puts the whole
///   remainder on that row; *Rescale proportionally* scales every amount when
///   no open row can absorb the difference (e.g. after the total changed).
///
/// G61 follow-ups:
/// - The remainder ("X left" / "X too much") is shown prominently in one
///   wrapping row with the actions, live on every keystroke.
/// - **Set total to the sum** (Exact, the rows add up to more than the amount
///   — or there is no amount yet): calls [onSetTotal] with the sum, so the
///   parent sets its amount field and the split adds up.
/// - **Fine-tune as amounts** (Shares, with an amount and at least one share):
///   switches to Exact with the shares converted to amounts.
class SplitEditor extends StatefulWidget {
  final List<MemberModel> members;
  final int totalCents;
  final String currency;

  /// Resolved cents map of the expense being edited; drives mode inference and
  /// prefill. Null for a new expense (defaults to Equal across every active member).
  final Map<String, int>? initialSplit;
  final ValueChanged<SplitPlan> onPlanChanged;

  /// Sets the expense amount (the parent owns that field) — enables *Set
  /// total to the sum* in Exact mode. Null → the action isn't offered.
  final ValueChanged<int>? onSetTotal;

  const SplitEditor({
    super.key,
    required this.members,
    required this.totalCents,
    required this.currency,
    required this.onPlanChanged,
    this.initialSplit,
    this.onSetTotal,
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

  /// Rows of Exact / Percent whose value the editor wrote (prefill /
  /// distribute) and the user hasn't typed in since — open for "fill the rest".
  final _autoExact = <String>{};
  final _autoPercent = <String>{};

  /// Modes that hold inputs (shown or prefilled at least once).
  final _seeded = <SplitMode>{};

  /// Whether the user changed anything since the last mode switch, and the
  /// total at that switch — together they tell a "peek" from a real change.
  bool _changedSinceSwitch = false;
  late int _totalAtSwitch;

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
      if (isEqualSplit(initial, step: currencyStep(widget.currency))) {
        _mode = SplitMode.equal;
      } else {
        // Any other distribution reopens as editable exact amounts
        // (prefilled in didChangeDependencies, in the locale's format).
        _mode = SplitMode.exact;
      }
    } else {
      _mode = SplitMode.equal;
      // Former members (U11 — only in an edit's list) are never included
      // by default.
      _included = {
        for (final m in widget.members)
          if (m.isActive) m.userId,
      };
    }
    _seeded.add(_mode);
    _totalAtSwitch = widget.totalCents;

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
      // The stored amounts are the user's own choice (typed, not auto); people
      // outside the split are an explicit 0 (not involved).
      for (final m in widget.members) {
        final cents = initial[m.userId] ?? 0;
        _exactCtrl[m.userId]!.text = cents > 0
            ? formatAmountInput(cents, locale, currency: widget.currency)
            : '0';
      }
    }
  }

  String _money(int cents) => context.money(cents, widget.currency);

  /// G66: the currency's smallest amount in cents (100 for JPY).
  int get _step => currencyStep(widget.currency);

  String _amountText(int cents) =>
      formatAmountInput(cents, context.localeName, currency: widget.currency);

  String _percent(int hundredths) => context.l10n.splitPercentValue(
    formatDecimal(hundredthsToPercent(hundredths), context.localeName),
  );

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

  /// A user edit: no longer a mere peek, then [_update].
  void _changed() {
    _changedSinceSwitch = true;
    _update();
  }

  // --- reading the inputs -------------------------------------------------

  int? _exactCents(String id) => parseAmountCents(
    _exactCtrl[id]!.text,
    locale: context.localeName,
    currency: widget.currency,
  );

  /// Percent of [id] in hundredths, or null when blank / unparsable.
  int? _percentHundredths(String id) {
    final p = parseLocalizedDecimal(_percentCtrl[id]!.text);
    return p == null ? null : percentToHundredths(p);
  }

  bool _blank(TextEditingController c) => c.text.trim().isEmpty;

  /// Rows "fill the rest" may write: blank, or auto-filled with a value > 0.
  List<String> _openRows(
    Map<String, TextEditingController> ctrl,
    Set<String> auto,
    int? Function(String) value,
  ) => [
    for (final m in widget.members)
      if (_blank(ctrl[m.userId]!) ||
          (auto.contains(m.userId) && (value(m.userId) ?? 0) > 0))
        m.userId,
  ];

  /// Rows the user typed a positive value into (not open, not 0).
  Map<String, int> _fixedRows(
    Map<String, TextEditingController> ctrl,
    List<String> open,
    int? Function(String) value,
  ) => {
    for (final m in widget.members)
      if (!open.contains(m.userId) && (value(m.userId) ?? 0) > 0)
        m.userId: value(m.userId)!,
  };

  /// Every positive value of a mode (typed or auto).
  Map<String, int> _allValues(int? Function(String) value) => {
    for (final m in widget.members)
      if ((value(m.userId) ?? 0) > 0) m.userId: value(m.userId)!,
  };

  /// Snapshots the current mode + inputs into a [SplitPlan].
  SplitPlan _plan() {
    switch (_mode) {
      case SplitMode.equal:
        return SplitPlan(
          mode: _mode,
          step: _step,
          included: [
            for (final m in widget.members)
              if (_included.contains(m.userId)) m.userId,
          ],
        );
      case SplitMode.exact:
        return SplitPlan(
          mode: _mode,
          step: _step,
          exact: _allValues(_exactCents),
        );
      case SplitMode.shares:
        final weights = <String, int>{};
        for (final m in widget.members) {
          final w = int.tryParse(_shareCtrl[m.userId]!.text.trim());
          if (w != null && w > 0) weights[m.userId] = w;
        }
        return SplitPlan(mode: _mode, step: _step, weights: weights);
      case SplitMode.percent:
        final percents = <String, num>{};
        for (final m in widget.members) {
          final p = parseLocalizedDecimal(_percentCtrl[m.userId]!.text);
          if (p != null && p > 0) percents[m.userId] = p;
        }
        return SplitPlan(mode: _mode, step: _step, percents: percents);
    }
  }

  // --- mode switch (G59) --------------------------------------------------

  /// The current split as proportions, or null when it isn't complete (an
  /// Exact split that doesn't add up, percents not at 100 %, nothing chosen).
  Map<String, num>? _currentWeights() {
    final plan = _plan();
    switch (_mode) {
      case SplitMode.equal:
        return plan.included.isEmpty
            ? null
            : {for (final id in plan.included) id: 1};
      case SplitMode.exact:
        final ok =
            widget.totalCents > 0 &&
            plan.exact.isNotEmpty &&
            remainingForExact(widget.totalCents, plan.exact) == 0;
        return ok ? plan.exact : null;
      case SplitMode.shares:
        return plan.weights.isEmpty ? null : plan.weights;
      case SplitMode.percent:
        final sum = plan.percents.values.fold<int>(
          0,
          (a, p) => a + percentToHundredths(p),
        );
        return sum == 10000 ? plan.percents : null;
    }
  }

  /// [convert]: always convert the current split (never a peek) — *Fine-tune
  /// as amounts*.
  void _switchTo(SplitMode target, {bool convert = false}) {
    if (target == _mode) return;
    final peek =
        !convert &&
        _seeded.contains(target) &&
        !_changedSinceSwitch &&
        widget.totalCents == _totalAtSwitch;
    if (!peek) {
      final weights = _currentWeights();
      if (weights != null) {
        _fill(target, weights);
      } else if (!_seeded.contains(target)) {
        final who = _included.isEmpty
            ? [
                for (final m in widget.members)
                  if (m.isActive) m.userId,
              ]
            : _included;
        _fill(target, {for (final id in who) id: 1});
      }
    }
    _seeded.add(target);
    _mode = target;
    _changedSinceSwitch = false;
    _totalAtSwitch = widget.totalCents;
    _update();
  }

  /// Writes the proportions [weights] into [target]'s inputs (members absent
  /// from [weights] or ≤ 0 → not involved).
  void _fill(SplitMode target, Map<String, num> weights) {
    final locale = context.localeName;
    num w(String id) => weights[id] ?? 0;
    switch (target) {
      case SplitMode.equal:
        _included = {
          for (final m in widget.members)
            if (w(m.userId) > 0) m.userId,
        };
      case SplitMode.exact:
        final total = widget.totalCents;
        final cents = total > 0
            ? distributeByWeights(total, {
                for (final m in widget.members) m.userId: w(m.userId),
              }, step: _step)
            : null;
        _autoExact.clear();
        for (final m in widget.members) {
          final id = m.userId;
          if (w(id) <= 0) {
            _exactCtrl[id]!.text = '0';
          } else {
            // No amount yet → blank (open): "Distribute" fills it later.
            _exactCtrl[id]!.text = cents == null
                ? ''
                : formatAmountInput(
                    cents[id]!,
                    locale,
                    currency: widget.currency,
                  );
            _autoExact.add(id);
          }
        }
      case SplitMode.shares:
        final shares = sharesFromWeights(
          {for (final m in widget.members) m.userId: w(m.userId)},
          total: widget.totalCents,
          step: _step,
        );
        shares.forEach((id, n) => _shareCtrl[id]!.text = '$n');
      case SplitMode.percent:
        final percents = percentsFromWeights({
          for (final m in widget.members) m.userId: w(m.userId),
        });
        _autoPercent.clear();
        percents.forEach((id, p) {
          _percentCtrl[id]!.text = formatDecimal(p, locale);
          if (p > 0) _autoPercent.add(id);
        });
    }
  }

  // --- fill the rest (G59) ------------------------------------------------

  /// Spreads `total − typed` over the open rows of Exact (cents) or Percent
  /// (hundredths); the filled rows stay "auto".
  void _distribute(SplitMode mode) {
    final exact = mode == SplitMode.exact;
    final ctrl = exact ? _exactCtrl : _percentCtrl;
    final auto = exact ? _autoExact : _autoPercent;
    final value = exact ? _exactCents : _percentHundredths;
    final total = exact ? widget.totalCents : 10000;
    final open = _openRows(ctrl, auto, value);
    final fill = distributeRest(
      total,
      _fixedRows(ctrl, open, value),
      open,
      step: exact ? _step : 1,
    );
    if (fill.isEmpty) return;
    fill.forEach((id, v) {
      ctrl[id]!.text = _format(mode, v);
      auto.add(id);
    });
    _changed();
  }

  /// Scales every positive value of Exact / Percent to the total.
  void _rescale(SplitMode mode) {
    final exact = mode == SplitMode.exact;
    final ctrl = exact ? _exactCtrl : _percentCtrl;
    final value = exact ? _exactCents : _percentHundredths;
    final values = _allValues(value);
    if (values.isEmpty) return;
    rescaleProportionally(
      exact ? widget.totalCents : 10000,
      values,
      step: exact ? _step : 1,
    ).forEach((id, v) => ctrl[id]!.text = _format(mode, v));
    _changed();
  }

  /// Puts the whole remainder on [id] (on top of what it has) — a deliberate
  /// choice, so the row counts as typed.
  void _restHere(SplitMode mode, String id, int remaining) {
    final exact = mode == SplitMode.exact;
    final ctrl = exact ? _exactCtrl : _percentCtrl;
    final current = (exact ? _exactCents(id) : _percentHundredths(id)) ?? 0;
    ctrl[id]!.text = _format(mode, current + remaining);
    (exact ? _autoExact : _autoPercent).remove(id);
    _changed();
  }

  String _format(SplitMode mode, int v) => mode == SplitMode.exact
      ? _amountText(v)
      : formatDecimal(hundredthsToPercent(v), context.localeName);

  /// Exact: `total − sum(all)` in cents; Percent: `100 % − sum` in hundredths.
  int _remaining(SplitMode mode) => mode == SplitMode.exact
      ? remainingForExact(widget.totalCents, _allValues(_exactCents))
      : remainingForExact(10000, _allValues(_percentHundredths));

  void _stepShare(String id, int delta) {
    final c = _shareCtrl[id]!;
    final n = (int.tryParse(c.text.trim()) ?? 0) + delta;
    c.text = '${n < 0 ? 0 : n}';
    _changed();
  }

  // --- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final result = _plan().resolve(widget.totalCents);
    final small = Theme.of(context).textTheme.bodySmall;
    final l = context.l10n;
    final remaining = _mode == SplitMode.exact || _mode == SplitMode.percent
        ? _remaining(_mode)
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<SplitMode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: SplitMode.equal, label: Text(l.splitEqual)),
            ButtonSegment(value: SplitMode.exact, label: Text(l.splitExact)),
            ButtonSegment(value: SplitMode.shares, label: Text(l.splitShares)),
            // U14: "%" fits a phone; screen readers hear "Percent".
            ButtonSegment(
              value: SplitMode.percent,
              label: Text('%', semanticsLabel: l.splitPercent),
              tooltip: l.splitPercent,
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => _switchTo(s.first),
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
                  _row(m, result.shares[m.userId] ?? 0, remaining),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.s),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
          child: _statusLine(result, small, remaining),
        ),
        if (_mode == SplitMode.exact || _mode == SplitMode.percent)
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.xs, 2, Insets.xs, 0),
            child: Text(
              l.splitOpenFieldsHint,
              style: small?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(MemberModel m, int cents, int remaining) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // G17: avatar + name on every row. G61: the name wraps onto up to two
    // lines (like NamesLine, G33) — long MXID localparts often share a long
    // prefix ("moneyledger-test-a…" / "…-b…"), so one ellipsized line made the
    // rows indistinguishable on a phone. Shares / Percent show the resolved
    // amount *under* the name, which leaves the name the room the inputs
    // don't need.
    Widget name({bool amountBelow = false}) => Expanded(
      child: Row(
        children: [
          PersonAvatar(id: m.userId, name: m.label, size: 30),
          const SizedBox(width: Insets.m),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                // U11: a former member kept in an edited expense's split.
                if (!m.isActive)
                  Text(
                    context.l10n.formerMemberTag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                if (amountBelow)
                  Text(
                    _money(cents),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: kTabularFigures,
                      color: muted,
                    ),
                  ),
              ],
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
        style: TextStyle(fontFeatures: kTabularFigures, color: muted),
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
                  _changed();
                },
              ),
              name(),
              preview,
            ],
          ),
        );
      case SplitMode.exact:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              name(),
              SizedBox(
                width: 96,
                child: _numField(
                  _exactCtrl[m.userId]!,
                  suffix: widget.currency,
                  decimal: true,
                  onEdited: () => _autoExact.remove(m.userId),
                ),
              ),
              _restButton(
                SplitMode.exact,
                m.userId,
                widget.totalCents > 0 ? remaining : 0,
              ),
            ],
          ),
        );
      case SplitMode.shares:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              name(amountBelow: true),
              _stepButton(m.userId, -1),
              SizedBox(
                width: 48,
                child: _numField(_shareCtrl[m.userId]!, decimal: false),
              ),
              _stepButton(m.userId, 1),
            ],
          ),
        );
      case SplitMode.percent:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              name(amountBelow: true),
              SizedBox(
                width: 64,
                child: _numField(
                  _percentCtrl[m.userId]!,
                  suffix: '%',
                  decimal: true,
                  onEdited: () => _autoPercent.remove(m.userId),
                ),
              ),
              _restButton(SplitMode.percent, m.userId, remaining),
            ],
          ),
        );
    }
  }

  /// "Put the rest here" — only while something is left; the space is kept so
  /// the column doesn't jump.
  Widget _restButton(SplitMode mode, String id, int remaining) => Visibility(
    visible: remaining > 0,
    maintainSize: true,
    maintainAnimation: true,
    maintainState: true,
    child: IconButton(
      tooltip: context.l10n.splitPutRestHere,
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.add_circle_outline, size: 20),
      onPressed: remaining > 0 ? () => _restHere(mode, id, remaining) : null,
    ),
  );

  Widget _stepButton(String id, int delta) {
    final l = context.l10n;
    final n = int.tryParse(_shareCtrl[id]!.text.trim()) ?? 0;
    return IconButton(
      tooltip: delta > 0 ? l.splitShareMore : l.splitShareLess,
      visualDensity: VisualDensity.compact,
      icon: Icon(delta > 0 ? Icons.add : Icons.remove, size: 18),
      onPressed: delta < 0 && n <= 0 ? null : () => _stepShare(id, delta),
    );
  }

  Widget _numField(
    TextEditingController c, {
    String? suffix,
    required bool decimal,
    VoidCallback? onEdited,
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
      onChanged: (_) {
        onEdited?.call();
        _changed();
      },
    );
  }

  /// The status text plus, when it helps, the actions (G59 / G61).
  Widget _statusLine(SplitResult result, TextStyle? small, int remaining) {
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
        if (widget.totalCents <= 0) {
          // No amount yet: amounts typed first can become the total.
          return _actionRow(Text(l.splitEnterAmountFirst, style: small), [
            ?_setTotalButton(),
          ]);
        }
        if (remaining == 0 && result.isValid) {
          return Text(l.splitAddsUpToTotal, style: small?.copyWith(color: ok));
        }
        return _withAction(
          remaining > 0
              ? l.splitLeft(_money(remaining))
              : l.splitTooMuch(_money(-remaining)),
          SplitMode.exact,
          extra: remaining < 0 ? _setTotalButton() : null,
        );
      case SplitMode.shares:
        final text = Text(
          result.isValid ? l.splitByWeight : l.splitEnterWeight,
          style: small?.copyWith(color: result.isValid ? null : bad),
        );
        if (!result.isValid || widget.totalCents <= 0) return text;
        return _actionRow(text, [
          TextButton(
            key: const Key('splitFineTune'),
            onPressed: () => _switchTo(SplitMode.exact, convert: true),
            child: Text(l.splitFineTuneAsAmounts),
          ),
        ]);
      case SplitMode.percent:
        if (remaining == 0 && result.isValid) {
          return Text(l.splitAddsUpTo100, style: small?.copyWith(color: ok));
        }
        return _withAction(
          remaining > 0
              ? l.splitLeft(_percent(remaining))
              : l.splitTooMuch(_percent(-remaining)),
          SplitMode.percent,
        );
    }
  }

  /// *Set total to the sum* — when [SplitEditor.onSetTotal] is given and the
  /// Exact rows sum to a storable amount other than the total.
  Widget? _setTotalButton() {
    final setTotal = widget.onSetTotal;
    if (setTotal == null) return null;
    final sum = _allValues(_exactCents).values.fold<int>(0, (a, b) => a + b);
    if (!isValidAmountCents(sum) || sum == widget.totalCents) return null;
    return TextButton(
      key: const Key('splitSetTotal'),
      onPressed: () => setTotal(sum),
      child: Text(context.l10n.splitSetTotalToSum),
    );
  }

  /// [label] followed by [actions] in one row that wraps on narrow screens.
  Widget _actionRow(Widget label, List<Widget> actions) {
    if (actions.isEmpty) return label;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Insets.s,
      children: [label, ...actions],
    );
  }

  /// The live remainder [text] (G61: prominent) with *Distribute* (some open
  /// row can take `total − typed`) or else *Rescale proportionally*
  /// (something to scale), plus [extra].
  Widget _withAction(String text, SplitMode mode, {Widget? extra}) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final exact = mode == SplitMode.exact;
    final ctrl = exact ? _exactCtrl : _percentCtrl;
    final auto = exact ? _autoExact : _autoPercent;
    final value = exact ? _exactCents : _percentHundredths;
    final total = exact ? widget.totalCents : 10000;
    final open = _openRows(ctrl, auto, value);
    final canDistribute = distributeRest(
      total,
      _fixedRows(ctrl, open, value),
      open,
    ).isNotEmpty;
    final canRescale = _allValues(value).isNotEmpty;
    final action = canDistribute
        ? TextButton(
            key: const Key('splitDistribute'),
            onPressed: () => _distribute(mode),
            child: Text(l.splitDistribute),
          )
        : canRescale
        ? TextButton(
            key: const Key('splitRescale'),
            onPressed: () => _rescale(mode),
            child: Text(l.splitRescale),
          )
        : null;
    return _actionRow(
      Text(
        text,
        key: const Key('splitRemaining'),
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.error,
          fontWeight: FontWeight.w600,
          fontFeatures: kTabularFigures,
        ),
      ),
      [?action, ?extra],
    );
  }
}
