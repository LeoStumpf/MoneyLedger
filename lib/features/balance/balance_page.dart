import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n/l10n.dart';
import '../../core/matrix/transport_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/person_avatar.dart';
import '../../models/member_model.dart';
import '../expenses/expenses_provider.dart';
import '../groups/group_provider.dart';
import 'balance_calculator.dart';
import 'balance_provider.dart';
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
    ref.watch(ledgerGroupsProvider);
    String nameOf(String id) => names[id] ?? localpartOf(id);
    final l = context.l10n;
    final theme = Theme.of(context);
    final nets = netsFromDebts(debts);
    final multiCurrency = nets.length > 1;

    void record({DebtEntry? debt}) =>
        recordPaymentFlow(context, ref, widget.roomId, myId: myId, debt: debt);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.balanceTitle),
        actions: [
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
          debts.isEmpty
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
                                      title: d.from == myId
                                          ? l.debtYouPay(nameOf(d.to))
                                          : d.to == myId
                                          ? l.debtPaysYou(nameOf(d.from))
                                          : l.debtPays(
                                              nameOf(d.from),
                                              nameOf(d.to),
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

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.xs,
        Insets.xl,
        Insets.xs,
        Insets.s,
      ),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
              Text(
                context.money(cents.abs(), currency),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One suggested payment "Carl pays Bea · €3.00" — tap to record it (G28).
class _DebtRow extends StatelessWidget {
  final DebtEntry debt;
  final String title;
  final String fromAvatar;
  final String toAvatar;
  final bool isMine;
  final VoidCallback? onTap;
  const _DebtRow({
    required this.debt,
    required this.title,
    required this.fromAvatar,
    required this.toAvatar,
    required this.isMine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isMine ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.money(debt.cents, debt.currency),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: kTabularFigures,
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
    );
  }
}
