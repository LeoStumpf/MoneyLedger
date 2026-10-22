import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/action_error.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/currency_field.dart';
import '../../core/widgets/large_text.dart';
import '../../models/exchange_rates.dart';
import '../../models/expense_model.dart';
import '../balance/exchange_rate_fetcher.dart';
import '../expenses/expenses_provider.dart';
import 'group_provider.dart';

/// G73: route of a group's exchange-rates page.
String groupRatesLocation(String roomId) => '/groups/$roomId/rates';

/// G73: the group settings tile's subtitle — "Not set …", "2 rates in EUR"
/// or "2 rates in EUR · settle up in EUR".
String exchangeRatesSummary(AppLocalizations l, ExchangeRates? fx) {
  if (fx == null || fx.rates.isEmpty) return l.exchangeRatesTileNone;
  final rates = l.exchangeRatesTileRates(fx.rates.length, fx.base);
  return fx.settle ? l.exchangeRatesTileSettled(rates, fx.base) : rates;
}

/// G73 (U18): the group's fixed exchange rates (group settings → *Exchange
/// rates*, `/groups/:id/rates`): add / change / remove a rate ("1 CHF =
/// 1.0797 EUR", entered by hand or with *Fetch current rate*), and the
/// switch *Settle up in {base}*. They live in the signed group meta, so
/// every change is a new meta version relayed to the group
/// ([GroupEditor.setExchangeRates]). Any active member may edit (same rule
/// as the name); others see them read-only. The base is the group currency
/// when the first rate is added.
class GroupRatesPage extends ConsumerWidget {
  final String roomId;
  const GroupRatesPage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    // Keep the (auto-dispose) editor alive while a write is in flight.
    final editorState = ref.watch(groupEditorProvider);
    final group = (ref.watch(ledgerGroupsProvider).value ?? const [])
        .where((g) => g.roomId == roomId)
        .firstOrNull;
    final me = ref.watch(currentParticipantProvider(roomId)).value;
    final canEdit =
        group != null && (me?.isActive ?? false) && !editorState.isLoading;
    final fx = group?.exchangeRates;
    final base = fx?.base ?? group?.currency ?? 'EUR';
    final rates = fx?.rates ?? const <String, String>{};
    final used = _usedCurrencies(
      ref.watch(expensesForRoomProvider(roomId)).value ?? const [],
      ref.watch(settlementsForRoomProvider(roomId)).value ?? const [],
    );
    final missing = [
      for (final c in used)
        if (c != base && !rates.containsKey(c)) c,
    ];
    final full = rates.length >= kMaxExchangeRates;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l.exchangeRatesTitle)),
      floatingActionButton: canEdit && !full
          ? FloatingActionButton.extended(
              key: const Key('addRate'),
              onPressed: () => _add(context, ref, base, missing, used),
              icon: const Icon(Icons.add),
              label: Text(l.addRate),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.only(
            top: Insets.s,
            bottom: Insets.fabClearance(context),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.page,
                Insets.s,
                Insets.page,
                Insets.m,
              ),
              child: Text(l.exchangeRatesIntro(base), style: muted),
            ),
            SwitchListTile(
              key: const Key('settleInBaseSwitch'),
              title: Text(l.settleInBase(base)),
              subtitle: Text(l.settleInBaseBody),
              value: fx?.settle ?? false,
              onChanged: canEdit && fx != null
                  ? (on) => _save(context, ref, fx.copyWith(settle: on))
                  : null,
            ),
            const Divider(),
            if (rates.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Insets.page),
                child: Text(
                  l.noRatesYet,
                  key: const Key('noRatesYet'),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            for (final MapEntry(key: code, value: rate) in rates.entries)
              ListTile(
                key: Key('rate-$code'),
                leading: const Icon(Icons.currency_exchange),
                title: Text(
                  l.rateRow(code, displayRate(rate, l.localeName), base),
                  style: const TextStyle(fontFeatures: kTabularFigures),
                ),
                onTap: canEdit
                    ? () => _edit(context, ref, base, code, rate)
                    : null,
                trailing: IconButton(
                  key: Key('removeRate-$code'),
                  tooltip: l.removeRate,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: canEdit
                      ? () => _save(
                          context,
                          ref,
                          fx!.copyWith(rates: {...rates}..remove(code)),
                        )
                      : null,
                ),
              ),
            if (missing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.m,
                  Insets.page,
                  0,
                ),
                child: Text(
                  l.ratesMissingFor(missing.join(', ')),
                  key: const Key('ratesMissing'),
                  style: muted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The currencies of the live records, most frequent first.
  static List<String> _usedCurrencies(
    List<ExpenseModel> expenses,
    List<SettlementModel> settlements,
  ) {
    final counts = <String, int>{};
    for (final c in [
      for (final e in expenses) e.currency,
      for (final s in settlements) s.currency,
    ]) {
      counts[c] = (counts[c] ?? 0) + 1;
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    String base,
    List<String> missing,
    List<String> used,
  ) async {
    final code = await showCurrencyPicker(
      context,
      selected: missing.firstOrNull ?? base,
      suggested: [...missing, ...used],
    );
    if (code == null || code == base || !context.mounted) return;
    final current = _current(ref);
    await _edit(context, ref, base, code, current?.rates[code]);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    String base,
    String code,
    String? rate,
  ) async {
    final picked = await showRateDialog(
      context,
      from: code,
      base: base,
      initial: rate,
    );
    if (picked == null || !context.mounted) return;
    final current = _current(ref);
    final next = current == null
        ? ExchangeRates(base: base, rates: {code: picked})
        : current.copyWith(rates: {...current.rates, code: picked});
    await _save(context, ref, next);
  }

  ExchangeRates? _current(WidgetRef ref) =>
      (ref.read(ledgerGroupsProvider).value ?? const [])
          .where((g) => g.roomId == roomId)
          .firstOrNull
          ?.exchangeRates;

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    ExchangeRates? next,
  ) async {
    final errors = ActionErrors.of(context);
    await ref.read(groupEditorProvider.notifier).setExchangeRates(roomId, next);
    final error = ref.read(groupEditorProvider).error;
    if (error != null) errors.show(error);
  }
}

/// [rate] (canonical, `.` as the point) with [locale]'s decimal separator —
/// no grouping (a German `31.315` would read as a decimal here).
String displayRate(String rate, String locale) {
  String sep;
  try {
    sep = NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;
  } catch (_) {
    sep = '.';
  }
  return rate.replaceFirst('.', sep);
}

/// G73: asks for the rate `1 [from] = ? [base]` — typed (`,` or `.`) or
/// filled in by *Fetch current rate* (only on tap; the source is named
/// under the button). Returns the canonical rate, or null when cancelled.
Future<String?> showRateDialog(
  BuildContext context, {
  required String from,
  required String base,
  String? initial,
}) => showDialog<String>(
  context: context,
  builder: (_) => RateDialog(from: from, base: base, initial: initial),
);

class RateDialog extends ConsumerStatefulWidget {
  final String from;
  final String base;
  final String? initial;

  const RateDialog({
    super.key,
    required this.from,
    required this.base,
    this.initial,
  });

  @override
  ConsumerState<RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends ConsumerState<RateDialog> {
  late final TextEditingController _controller;
  bool _fetching = false;
  bool _showInvalid = false;
  String? _fetchedDate;
  bool _unavailable = false;
  Object? _fetchError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final initial = widget.initial;
    if (initial != null && _controller.text.isEmpty) {
      _controller.text = displayRate(initial, context.l10n.localeName);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final l = context.l10n;
    setState(() {
      _fetching = true;
      _fetchedDate = null;
      _unavailable = false;
      _fetchError = null;
    });
    try {
      final fetched = await ref.read(exchangeRateFetcherProvider)(
        widget.from,
        widget.base,
      );
      if (!mounted) return;
      setState(() {
        _controller.text = displayRate(fetched.rate, l.localeName);
        _fetchedDate = fetched.date;
        _showInvalid = false;
      });
    } on RateUnavailableException {
      if (mounted) setState(() => _unavailable = true);
    } catch (e) {
      if (mounted) setState(() => _fetchError = e);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  /// The service's ISO day in the UI's date format (verbatim if odd).
  static String _dayLabel(BuildContext context, String isoDay) {
    final d = DateTime.tryParse(isoDay);
    return d == null ? isoDay : context.date(d.millisecondsSinceEpoch);
  }

  void _submit() {
    final rate = normalizeRateInput(_controller.text);
    if (rate == null) {
      setState(() => _showInvalid = true);
      return;
    }
    Navigator.of(context).pop(rate);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AlertDialog(
      title: Text(l.rateDialogTitle(widget.from, widget.base)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('rateField'),
              controller: _controller,
              autofocus: widget.initial == null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_showInvalid) setState(() => _showInvalid = false);
              },
              decoration: InputDecoration(
                labelText: l.rateFieldLabel(widget.base),
                prefixText: '1 ${widget.from} = ',
                suffixText: widget.base,
                errorText: _showInvalid ? l.rateInvalid : null,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: Insets.m),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('fetchRateButton'),
                onPressed: _fetching ? null : _fetch,
                icon: _fetching
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(l.fetchRate),
              ),
            ),
            Text(
              l.fetchRateSource(kRateSourceHost),
              key: const Key('fetchRateSource'),
              style: small,
            ),
            if (_fetchedDate != null) ...[
              const SizedBox(height: Insets.s),
              Text(
                l.fetchedRateFrom(_dayLabel(context, _fetchedDate!)),
                key: const Key('fetchedRateInfo'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_unavailable) ...[
              const SizedBox(height: Insets.s),
              Text(
                l.fetchRateUnavailable,
                key: const Key('fetchRateUnavailable'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (_fetchError != null) ...[
              const SizedBox(height: Insets.s),
              ActionErrorView(
                error: _fetchError!,
                what: l.fetchRateFailedTitle,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('rateSave'),
          onPressed: _fetching ? null : _submit,
          child: Text(l.save),
        ),
      ],
    );
  }
}
