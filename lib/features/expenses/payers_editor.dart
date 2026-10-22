import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/large_text.dart';
import '../../core/widgets/person_avatar.dart';
import '../../models/member_model.dart';

/// G76: who paid how much of an expense several people paid — one amount
/// field per person (blank = didn't pay), the live remainder ("X left" /
/// "X too much" / "Adds up to the total") and a per-row *Put the rest
/// here*. Reports the typed amounts through [onChanged]: `{participant:
/// cents}` of the non-blank rows, or null while a field can't be read. The
/// parent decides validity (sum = total, someone paid) and stores the map
/// (`payerFields` — one payer left is stored as a plain `paid_by`).
class PayersEditor extends StatefulWidget {
  const PayersEditor({
    super.key,
    required this.members,
    required this.totalCents,
    required this.currency,
    required this.onChanged,
    this.initial,
  });

  final List<MemberModel> members;
  final int totalCents;
  final String currency;

  /// The amounts to start with (an edited multi-payer expense), else blank.
  final Map<String, int>? initial;
  final ValueChanged<Map<String, int>?> onChanged;

  @override
  State<PayersEditor> createState() => _PayersEditorState();
}

class _PayersEditorState extends State<PayersEditor> {
  final _ctrl = <String, TextEditingController>{};
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    for (final m in widget.members) {
      _ctrl[m.userId] = TextEditingController();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final initial = widget.initial;
    if (initial == null) return;
    for (final MapEntry(:key, :value) in initial.entries) {
      _ctrl[key]?.text = formatAmountInput(
        value,
        context.localeName,
        currency: widget.currency,
      );
    }
  }

  @override
  void didUpdateWidget(PayersEditor old) {
    super.didUpdateWidget(old);
    // Another currency reads the typed amounts with its own step (whole
    // yen) — report them again once this frame is built.
    if (old.currency != widget.currency) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(_amounts);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The typed amounts, or null while a non-blank field can't be read.
  Map<String, int>? get _amounts {
    final out = <String, int>{};
    for (final MapEntry(:key, value: c) in _ctrl.entries) {
      final text = c.text.trim();
      if (text.isEmpty) continue;
      final cents = parseAmountCents(
        text,
        locale: context.localeName,
        currency: widget.currency,
      );
      if (cents == null || cents < 0) return null;
      out[key] = cents;
    }
    return out;
  }

  void _changed() {
    setState(() {});
    widget.onChanged(_amounts);
  }

  void _restHere(String id, int remaining) {
    final current = parseAmountCents(
      _ctrl[id]!.text,
      locale: context.localeName,
      currency: widget.currency,
    );
    _ctrl[id]!.text = formatAmountInput(
      (current ?? 0) + remaining,
      context.localeName,
      currency: widget.currency,
    );
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final amounts = _amounts;
    final sum = amounts?.values.fold<int>(0, (a, b) => a + b);
    final remaining = sum == null ? 0 : widget.totalCents - sum;
    final small = theme.textTheme.bodySmall;
    Widget status;
    if (widget.totalCents <= 0) {
      status = Text(l.splitEnterAmountFirst, style: small);
    } else if (sum == null) {
      status = Text(
        l.invalidNumber,
        style: small?.copyWith(color: theme.colorScheme.error),
      );
    } else if (remaining == 0) {
      status = Text(
        l.splitAddsUpToTotal,
        style: small?.copyWith(color: theme.colorScheme.primary),
      );
    } else {
      status = Text(
        remaining > 0
            ? l.splitLeft(context.money(remaining, widget.currency))
            : l.splitTooMuch(context.money(-remaining, widget.currency)),
        key: const Key('payersRemaining'),
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.error,
          fontWeight: FontWeight.w600,
          fontFeatures: kTabularFigures,
        ),
      );
    }
    final cellWidth = scaledCellWidth(context, 96, 128);
    final restLeft = widget.totalCents > 0 && sum != null && remaining > 0;
    return Column(
      key: const Key('payersEditor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.payersHint, style: small),
        for (final m in widget.members)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
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
                      if (!m.isActive)
                        Text(
                          l.formerMemberTag,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: cellWidth,
                  child: TextField(
                    key: Key('payerAmount-${m.userId}'),
                    controller: _ctrl[m.userId],
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '0',
                      // G71: 48 dp high — a full tap target.
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Insets.s,
                        vertical: Insets.m,
                      ),
                    ),
                    onChanged: (_) => _changed(),
                  ),
                ),
                // "Put the rest here" — space kept so the column doesn't jump.
                Visibility(
                  visible: restLeft,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: IconButton(
                    key: Key('payersRest-${m.userId}'),
                    tooltip: l.splitPutRestHere,
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: restLeft
                        ? () => _restHere(m.userId, remaining)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: Insets.xs),
        status,
      ],
    );
  }
}
