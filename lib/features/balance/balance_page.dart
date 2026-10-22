import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/large_text.dart';
import '../../core/l10n/l10n.dart';
import '../../core/matrix/transport_provider.dart';
import '../../core/platform/text_sharer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/names_line.dart';
import '../../core/widgets/person_avatar.dart';
import '../../models/expense_category.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../expenses/expense_category_ui.dart';
import '../expenses/expenses_provider.dart';
import '../groups/group_provider.dart';
import '../groups/group_rates_page.dart';
import 'balance_calculator.dart';
import 'balance_provider.dart';
import 'balance_share.dart';
import 'group_stats.dart';
import 'settle_currency.dart';
import 'settle_up.dart';

/// Per-participant net balance per currency, derived from the simplified
/// [debts] (the greedy simplification preserves everyone's net): `currency →
/// participant → cents`, > 0 gets money back, < 0 owes. Sorted by currency;
/// within one, creditors first (largest first), then debtors.
Map<String, List<MapEntry<String, int>>> netsFromDebts(List<DebtEntry> debts) {
  final byCurrency = <String, Map<String, int>>{};
  for (final d in debts) {
    final m = byCurrency.putIfAbsent(d.currency, () => {});
    m[d.to] = (m[d.to] ?? 0) + d.cents;
    m[d.from] = (m[d.from] ?? 0) - d.cents;
  }
  return {
    for (final c in byCurrency.keys.toList()..sort())
      c: byCurrency[c]!.entries.where((e) => e.value != 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value)),
  };
}

class BalancePage extends ConsumerStatefulWidget {
  final String roomId;
  const BalancePage({super.key, required this.roomId});

  @override
  ConsumerState<BalancePage> createState() => _BalancePageState();
}

class _BalancePageState extends ConsumerState<BalancePage> {
  Future<void> _share(
    GroupModel? group,
    List<DebtEntry> debts,
    String Function(String) nameOf,
  ) async {
    final l = context.l10n;
    final title = l.shareBalanceTitle(group?.name ?? '');
    final text = buildBalanceShareText(
      l: l,
      groupName: group?.name ?? '',
      debts: debts,
      nameOf: nameOf,
    );
    final outcome = await shareOrCopy(
      ref.read(textSharerProvider),
      text,
      subject: title,
    );
    if (!mounted || outcome == ShareOutcome.shared) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.shareCopiedFallback)));
  }

  @override
  Widget build(BuildContext context) {
    final debts = ref.watch(balanceForRoomProvider(widget.roomId));
    final names = ref.watch(participantNamesProvider(widget.roomId));
    final transport = ref.watch(ledgerTransportProvider).value;
    // "Me" is this device's participant in the group (id may differ from the
    // MXID once a local slot has been claimed); fall back to the raw MXID.
    final me = ref.watch(currentParticipantProvider(widget.roomId)).value;
    final myId = me?.userId ?? transport?.userId ?? '';
    // G28: any active member may record a payment between any two
    // participants. G26: removed from the group → read-only, nothing to record.
    final canRecord = me?.isActive ?? true;
    final adderState = ref.watch(expenseAdderProvider);
    final busy = adderState.isLoading;
    // Kept alive for the dialog: members (choices) + group (default currency).
    ref.watch(groupMembersProvider(widget.roomId));
    final group = ref
        .watch(ledgerGroupsProvider)
        .value
        ?.where((g) => g.roomId == widget.roomId)
        .firstOrNull;
    // G69 (U19): the overview is computed from the live expenses.
    final expenses =
        ref.watch(expensesForRoomProvider(widget.roomId)).value ??
        const <ExpenseModel>[];
    final stats = groupStats(
      expenses,
      customCategories: group?.categories ?? const <CustomCategory>[],
    );
    String nameOf(String id) => names[id] ?? localpartOf(id);
    final l = context.l10n;
    final theme = Theme.of(context);
    final nets = netsFromDebts(debts);
    final multiCurrency = nets.length > 1;
    // G73: "settle up in {base}" converted something → say so.
    final fx = ref.watch(groupExchangeRatesProvider(widget.roomId));
    // (Expenses only: a payment alone in a rated currency is rare, and the
    // page doesn't watch the payments stream itself.)
    final converted = settlesConverted(fx, [
      for (final e in expenses) e.currency,
    ]);
    void openRates() => context.push(groupRatesLocation(widget.roomId));
    final nothingYet = debts.isEmpty && stats.isEmpty;

    void record({DebtEntry? debt}) =>
        recordPaymentFlow(context, ref, widget.roomId, myId: myId, debt: debt);

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(l.balanceTitle),
        actions: [
          // G69 (U17): "who pays whom" as text for the group's chat.
          if (!nothingYet)
            IconButton(
              key: const Key('shareBalances'),
              icon: const Icon(Icons.share_outlined),
              tooltip: l.shareBalances,
              onPressed: () => _share(group, debts, nameOf),
            ),
          if (canRecord)
            IconButton(
              key: const Key('recordPayment'),
              icon: const Icon(Icons.payments_outlined),
              tooltip: l.recordPayment,
              onPressed: busy ? null : () => record(),
            ),
        ],
      ),
      body: Stack(
        children: [
          nothingYet
              ? EmptyState(
                  key: const Key('allSettledUp'),
                  icon: Icons.celebration_outlined,
                  title: l.allSettledUp,
                  body: l.allSettledUpBody,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.page,
                    Insets.s,
                    Insets.page,
                    Insets.xxl,
                  ),
                  children: [
                    // Expenses, but nobody owes anything: say so above the
                    // overview.
                    if (debts.isEmpty)
                      const ContentWidth(child: _SettledCard()),
                    if (converted)
                      ContentWidth(
                        child: _CurrencyNote(
                          key: const Key('settledInBaseNote'),
                          text: l.settledInBaseNote(fx!.base),
                          action: TextButton(
                            key: const Key('openRatesFromBalance'),
                            onPressed: openRates,
                            child: Text(l.exchangeRatesTitle),
                          ),
                        ),
                      ),
                    // G16: several currencies are never netted against
                    // each other — say so once at the top.
                    if (multiCurrency)
                      ContentWidth(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Insets.xs,
                            Insets.m,
                            Insets.xs,
                            0,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.currency_exchange,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: Insets.s),
                              Expanded(
                                child: Text(
                                  l.simplifyDebtsPerCurrency,
                                  key: const Key('perCurrencyNote'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // G73: one currency instead — fixed rates.
                    if (multiCurrency && canRecord && !converted)
                      ContentWidth(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            key: const Key('setExchangeRates'),
                            onPressed: openRates,
                            icon: const Icon(Icons.currency_exchange),
                            label: Text(l.setExchangeRates),
                          ),
                        ),
                      ),
                    for (final MapEntry(key: currency, value: people)
                        in nets.entries)
                      ContentWidth(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SectionHeader(
                              multiCurrency
                                  ? '${l.balancesSection} · $currency'
                                  : l.balancesSection,
                            ),
                            Card(
                              child: Column(
                                children: [
                                  for (var i = 0; i < people.length; i++) ...[
                                    if (i > 0) const Divider(indent: 68),
                                    _PersonBalanceRow(
                                      id: people[i].key,
                                      name: people[i].key == myId
                                          ? l.you
                                          : nameOf(people[i].key),
                                      avatarName: nameOf(people[i].key),
                                      isMe: people[i].key == myId,
                                      cents: people[i].value,
                                      currency: currency,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            _SectionHeader(
                              multiCurrency
                                  ? '${l.suggestedPayments} · $currency'
                                  : l.suggestedPayments,
                              // G16: what "simplified debts" means.
                              trailing: IconButton(
                                key: Key('simplifyInfo-$currency'),
                                icon: const Icon(Icons.info_outline, size: 20),
                                tooltip: l.simplifyDebtsInfoTooltip,
                                onPressed: () => showSimplifyDebtsInfo(context),
                              ),
                            ),
                            Card(
                              child: Column(
                                children: [
                                  for (final (i, d)
                                      in debts
                                          .where((d) => d.currency == currency)
                                          .indexed) ...[
                                    if (i > 0) const Divider(indent: 16),
                                    _DebtRow(
                                      debt: d,
                                      // G33: each name ellipsizes on its own.
                                      titleTemplate: d.from == myId
                                          ? l.debtYouPay(NamesLine.sentinel(1))
                                          : d.to == myId
                                          ? l.debtPaysYou(NamesLine.sentinel(0))
                                          : l.debtPays(
                                              NamesLine.sentinel(0),
                                              NamesLine.sentinel(1),
                                            ),
                                      fromAvatar: nameOf(d.from),
                                      toAvatar: nameOf(d.to),
                                      isMine: d.from == myId || d.to == myId,
                                      // Any debt — ours, a local person's, or
                                      // one owed to us — can be settled by
                                      // recording the payment.
                                      onTap: canRecord && !busy
                                          ? () => record(debt: d)
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (canRecord)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  Insets.xs,
                                  Insets.s,
                                  Insets.xs,
                                  0,
                                ),
                                child: Text(
                                  l.suggestedPaymentsHint,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    // G69 (U19): total, paid vs. share, categories.
                    for (final st in stats)
                      ContentWidth(
                        child: _StatsSection(
                          stats: st,
                          title: stats.length > 1
                              ? '${l.statsSection} · ${st.currency}'
                              : l.statsSection,
                          nameOf: (id) => id == myId ? l.you : nameOf(id),
                          avatarNameOf: nameOf,
                          myId: myId,
                        ),
                      ),
                  ],
                ),
          // Overlay spinner while the settlement event is being sent.
          if (busy)
            ColoredBox(
              color: theme.colorScheme.scrim.withValues(alpha: 0.2),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// G16: explains the suggested payments — debts are simplified (fewest
/// payments, everyone's net unchanged), separately per currency.
Future<void> showSimplifyDebtsInfo(BuildContext context) {
  final l = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.alt_route),
      title: Text(l.simplifyDebtsInfoTitle),
      content: Text(
        l.simplifyDebtsInfoBody,
        key: const Key('simplifyInfoBody'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l.ok)),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _SectionHeader(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // G71: screen readers can jump between the sections.
    final label = Semantics(
      header: true,
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Insets.xs,
        trailing == null ? Insets.xl : Insets.l,
        0,
        trailing == null ? Insets.s : 0,
      ),
      child: trailing == null
          ? label
          : Row(
              children: [
                Expanded(child: label),
                trailing!,
              ],
            ),
    );
  }
}

/// "Bea · gets back €12.50" (G17). Not tappable — payments are recorded from
/// the suggested-payment rows below.
class _PersonBalanceRow extends StatelessWidget {
  final String id;
  final String name;
  final String avatarName;
  final bool isMe;
  final int cents;
  final String currency;
  const _PersonBalanceRow({
    required this.id,
    required this.name,
    required this.avatarName,
    required this.isMe,
    required this.cents,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final colors = context.ledgerColors;
    final color = colors.forSign(cents, theme.colorScheme.onSurfaceVariant);
    final label = cents > 0
        ? (isMe ? l.balanceYouGetBack : l.balanceGetsBack)
        : cents < 0
        ? (isMe ? l.balanceYouOwe : l.balanceOwes)
        : l.balanceSettled;
    return Padding(
      key: Key('personBalance-$id'),
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.l,
        vertical: Insets.m,
      ),
      child: Row(
        children: [
          PersonAvatar(id: id, name: avatarName),
          const SizedBox(width: Insets.m),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: Insets.s),
          // Flexible + scaleDown: at a large font size (G71, 200 %) the
          // label / amount shrink instead of overflowing the row.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    context.money(cents.abs(), currency),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One suggested payment "Carl pays Bea · €3.00" — tap to record it (G28).
class _DebtRow extends StatelessWidget {
  final DebtEntry debt;

  /// The localized sentence with [NamesLine.sentinel] 0 (payer) / 1 (payee).
  final String titleTemplate;
  final String fromAvatar;
  final String toAvatar;
  final bool isMine;
  final VoidCallback? onTap;
  const _DebtRow({
    required this.debt,
    required this.titleTemplate,
    required this.fromAvatar,
    required this.toAvatar,
    required this.isMine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final large = isLargeText(context);
    final amount = Text(
      context.money(debt.cents, debt.currency),
      key: Key('debtAmount-${debt.from}-${debt.to}-${debt.currency}'),
      style: theme.textTheme.bodyLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
        fontFeatures: kTabularFigures,
      ),
    );
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(
        Insets.l,
        Insets.xs,
        Insets.s,
        Insets.xs,
      ),
      leading: SizedBox(
        width: 76,
        child: Row(
          children: [
            PersonAvatar(id: debt.from, name: fromAvatar, size: 30),
            Expanded(
              child: Icon(
                Icons.arrow_forward,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
            PersonAvatar(id: debt.to, name: toAvatar, size: 30),
          ],
        ),
      ),
      title: NamesLine(
        key: Key('debtTitle-${debt.from}-${debt.to}-${debt.currency}'),
        template: titleTemplate,
        names: {
          NamesLine.sentinel(0): fromAvatar,
          NamesLine.sentinel(1): toAvatar,
        },
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isMine ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      // DEV-I: at a large font size the amount moves under the names —
      // side by side, both names were cut to one letter at 360 dp.
      subtitle: large ? amount : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!large) amount,
          if (onTap != null)
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Expenses exist but nobody owes anything (G69: the page then still shows
/// the overview below this card).
class _SettledCard extends StatelessWidget {
  const _SettledCard();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: const Key('allSettledUpCard'),
      margin: const EdgeInsets.only(top: Insets.m),
      child: Padding(
        padding: const EdgeInsets.all(Insets.l),
        child: Row(
          children: [
            Icon(Icons.celebration_outlined, color: scheme.primary),
            const SizedBox(width: Insets.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.allSettledUp, style: theme.textTheme.titleMedium),
                  Text(
                    l.allSettledUpBody,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How many categories the overview lists before summing up the rest.
const kStatsTopCategories = 5;

/// G69 (U19): the overview of one currency — total spent, what everyone
/// paid vs. their share, and the biggest categories as simple bars.
class _StatsSection extends StatelessWidget {
  final CurrencyStats stats;
  final String title;
  final String Function(String id) nameOf;
  final String Function(String id) avatarNameOf;
  final String myId;
  const _StatsSection({
    required this.stats,
    required this.title,
    required this.nameOf,
    required this.avatarNameOf,
    required this.myId,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final currency = stats.currency;
    final top = stats.categories.take(kStatsTopCategories).toList();
    final rest = stats.categories.skip(kStatsTopCategories).toList();
    final restCents = rest.fold<int>(0, (sum, c) => sum + c.cents);
    Widget subHeading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.l,
        Insets.m,
        Insets.l,
        Insets.xs,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(color: muted),
        ),
      ),
    );
    return Column(
      key: Key('stats-$currency'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title),
        Card(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Insets.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.l,
                      Insets.m,
                      Insets.l,
                      Insets.s,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // DEV-I: one long German word
                              // ("Gesamtausgaben") broke mid-word at a
                              // large font size — shrink it instead.
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  l.statsTotalSpent,
                                  key: const Key('statsTotalLabel'),
                                  maxLines: 1,
                                  softWrap: false,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                l.statsExpenseCount(stats.count),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Insets.s),
                        Text(
                          context.money(stats.total, currency),
                          key: Key('statsTotal-$currency'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFeatures: kTabularFigures,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                subHeading(l.statsPerPerson),
                for (final p in stats.people)
                  MergeSemantics(
                    key: Key('statsPerson-$currency-${p.id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Insets.l,
                        vertical: Insets.s,
                      ),
                      child: Row(
                        children: [
                          PersonAvatar(
                            id: p.id,
                            name: avatarNameOf(p.id),
                            size: 32,
                          ),
                          const SizedBox(width: Insets.m),
                          // Amounts under the name: fits 360 dp at
                          // 200 % font size too.
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nameOf(p.id),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: p.id == myId
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                                Wrap(
                                  spacing: Insets.m,
                                  children: [
                                    Text(
                                      l.statsPaid(
                                        context.money(p.paid, currency),
                                      ),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontFeatures: kTabularFigures,
                                          ),
                                    ),
                                    Text(
                                      l.statsShare(
                                        context.money(p.share, currency),
                                      ),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: muted,
                                            fontFeatures: kTabularFigures,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (top.isNotEmpty) ...[
                  const Divider(),
                  subHeading(l.statsByCategory),
                  for (final c in top)
                    _CategoryBar(
                      key: Key('statsCategory-$currency-${c.category?.key}'),
                      category: c.category,
                      label: c.category?.label(l) ?? l.categoryNone,
                      cents: c.cents,
                      total: stats.total,
                      currency: currency,
                    ),
                  if (rest.isNotEmpty)
                    _CategoryBar(
                      key: Key('statsCategoryRest-$currency'),
                      category: null,
                      label: l.statsMoreCategories(rest.length),
                      cents: restCents,
                      total: stats.total,
                      currency: currency,
                      showIcon: false,
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One category of the overview: icon, name, amount and a bar of its share
/// of the total (the bar is decorative — the amount is read out).
class _CategoryBar extends StatelessWidget {
  final ResolvedCategory? category;
  final String label;
  final int cents;
  final int total;
  final String currency;
  final bool showIcon;
  const _CategoryBar({
    super.key,
    required this.category,
    required this.label,
    required this.cents,
    required this.total,
    required this.currency,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = categoryColors(context, category);
    final fraction = total <= 0 ? 0.0 : (cents / total).clamp(0.0, 1.0);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.l,
          vertical: Insets.s,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: showIcon
                  ? CategoryIconTile(category: category, size: 32)
                  : null,
            ),
            const SizedBox(width: Insets.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: Insets.s),
                      Text(
                        context.money(cents, currency),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Insets.xs),
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.s),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 6,
                        color: colors.foreground,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// G73: a small note above the balances with an action under it.
class _CurrencyNote extends StatelessWidget {
  final String text;
  final Widget action;
  const _CurrencyNote({super.key, required this.text, required this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.xs, Insets.m, Insets.xs, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.currency_exchange,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Insets.s),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          action,
        ],
      ),
    );
  }
}
