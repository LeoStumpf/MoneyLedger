import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../welcome/why_matrix_hint.dart';
import '../../core/widgets/action_error.dart';
import 'package:go_router/go_router.dart';
import '../../core/demo/demo_mode.dart' show kOfflineDemo;
import '../../core/matrix/crypto_status.dart';
import '../../core/session/app_session.dart';
import '../../core/session/local_adoption.dart';
import '../local/local_mode_ui.dart';
import '../notifications/notifications_provider.dart';
import '../../core/l10n/l10n.dart';
import '../auth/auth_provider.dart';
import '../backup/backup_providers.dart';
import '../backup/backup_ui.dart';
import '../expenses/ledger_syncer.dart';
import '../../core/sync/self_recovery.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_health.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
import '../settings/settings_page.dart' show kSettingsLocation;
import '../web/web_limits.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/person_avatar.dart';
import '../../models/group_model.dart';
import 'group_archive_provider.dart';
import 'group_overview_provider.dart';
import 'group_provider.dart';

class GroupsPage extends ConsumerWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerSyncerProvider); // keep syncer alive on the main screen
    ref.watch(syncEngineProvider); // run anti-entropy while signed in
    // G17: one-off upgrade of localpart names to Matrix profile names.
    ref.watch(profileNameRefreshProvider);
    // G72: ask for the notification permission once a group is shared.
    if (!kOfflineDemo) ref.watch(notificationPermissionPromptProvider);
    final groupsAsync = ref.watch(ledgerGroupsProvider);
    final l = context.l10n;
    // G40: no account — a "No account" indicator (G54: was "Local only") (G65: account, devices and
    // sign-out / delete local data live on the settings page).
    final local = ref.watch(localModeActiveProvider);

    return Scaffold(
      appBar: AppBar(
        // G54: the logo gives way when the title has little room (200 %
        // font next to the "No account" chip).
        title: LayoutBuilder(
          builder: (context, c) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (c.maxWidth >= 120) ...[
                const BrandLogo(size: 30),
                const SizedBox(width: Insets.m),
              ],
              Flexible(
                child: Text(l.groupsTitle, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        // G65 (U21): only the settings and, in local mode, the mode chip
        // stay up here — CSV import and sign-out moved to the settings page.
        actions: [
          if (local) const LocalModeChip(),
          IconButton(
            key: const Key('settingsButton'),
            icon: const Icon(Icons.settings),
            tooltip: l.settingsTooltip,
            onPressed: () => context.push(kSettingsLocation),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/groups/create'),
        icon: const Icon(Icons.add),
        label: Text(l.newGroup),
      ),
      body: Column(
        children: [
          // G33: E2EE failed to start (vodozemac init) — nothing can sync.
          if (!local && !ref.watch(cryptoAvailableProvider))
            const _EncryptionUnavailableBanner(),
          // G40: the local groups just moved into this account.
          const _LocalAdoptedBanner(),
          // G35: a peer relayed unsigned (pre-G6) records we had to refuse.
          const _LegacyRefusalBanner(),
          // G75 (U31): the web's limits, once (until *Got it*).
          const WebLimitsBanner(),
          Expanded(
            child: _GroupsBody(
              groupsAsync: groupsAsync,
              restoring: ref.watch(selfRecoveryProvider),
              onImport: () => _importCsv(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importCsv(BuildContext context, WidgetRef ref) =>
      importCsvWithPreview(context, ref);
}

/// Persistent notice that end-to-end encryption is off on this device, so
/// nothing syncs (G33).
class _EncryptionUnavailableBanner extends StatelessWidget {
  const _EncryptionUnavailableBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('encryptionUnavailableBanner'),
      color: scheme.errorContainer,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.page,
            vertical: Insets.m,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sync_disabled, color: scheme.onErrorContainer),
              const SizedBox(width: Insets.m),
              Expanded(
                child: Text(
                  context.l10n.encryptionUnavailableBanner,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// G35: unsigned records from before signed records (G6) can't be relayed —
/// a peer's old group arrives incomplete or not at all. Says so (with who
/// sent it and what to do) instead of leaving a silently half-empty group.
class _LegacyRefusalBanner extends ConsumerWidget {
  const _LegacyRefusalBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refusals = ref.watch(
      syncHealthProvider.select((s) => s.legacyRefusals),
    );
    if (refusals.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final localNames = {
      for (final g in ref.watch(ledgerGroupsProvider).value ?? const [])
        g.roomId: g.name,
    };
    return Material(
      key: const Key('legacyRefusalBanner'),
      color: scheme.tertiaryContainer,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.page,
            Insets.m,
            Insets.page,
            Insets.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.report_gmailerrorred_outlined,
                    color: scheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: Insets.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.legacyRefusedTitle,
                          style: TextStyle(
                            color: scheme.onTertiaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        for (final r in refusals.values)
                          Padding(
                            padding: const EdgeInsets.only(top: Insets.xs),
                            child: Text(
                              l.legacyRefusedBody(
                                r.count,
                                r.relayedBy,
                                r.groupName ??
                                    localNames[r.groupId] ??
                                    r.groupId,
                              ),
                              style: TextStyle(
                                color: scheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('legacyRefusalDismiss'),
                  onPressed: () => ref
                      .read(syncHealthProvider.notifier)
                      .dismissLegacyRefusals(),
                  child: Text(l.ok),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// G40: after "Connect a Matrix account" — says where the local groups went
/// (dismissible, this run only).
class _LocalAdoptedBanner extends ConsumerWidget {
  const _LocalAdoptedBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(localAdoptionResultProvider);
    final account = ref.watch(accountUserIdProvider);
    if (result == null || result.groupIds.isEmpty || account == null) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('localAdoptedBanner'),
      color: scheme.secondaryContainer,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.page,
            Insets.m,
            Insets.page,
            Insets.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.move_up, color: scheme.onSecondaryContainer),
                  const SizedBox(width: Insets.m),
                  Expanded(
                    child: Text(
                      l.localAdoptedBanner(result.groupIds.length, account),
                      style: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('localAdoptedDismiss'),
                  onPressed: () => ref
                      .read(localAdoptionResultProvider.notifier)
                      .report(null),
                  child: Text(l.ok),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupsBody extends ConsumerWidget {
  final AsyncValue<List<GroupModel>> groupsAsync;

  /// A fresh device's first recovery is outstanding (G30) — show "Restoring…"
  /// instead of the empty state.
  final bool restoring;
  final VoidCallback onImport;
  const _GroupsBody({
    required this.groupsAsync,
    required this.restoring,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return groupsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.page),
          child: ActionErrorView(error: e, what: l.loadFailedTitle),
        ),
      ),
      data: (groups) {
        if (groups.isEmpty && restoring) {
          return EmptyState(
            key: const Key('restoringGroups'),
            icon: Icons.cloud_sync_outlined,
            busy: true,
            title: l.restoringGroupsTitle,
            body: l.restoringGroupsBody,
          );
        }
        if (groups.isEmpty) {
          return EmptyState(
            key: const Key('groupsEmpty'),
            icon: Icons.groups_2_outlined,
            title: l.groupsEmptyTitle,
            body: l.groupsEmptyBody,
            actions: [
              FilledButton.icon(
                key: const Key('emptyCreateGroup'),
                onPressed: () => context.push('/groups/create'),
                icon: const Icon(Icons.add),
                label: Text(l.createGroup),
              ),
              OutlinedButton.icon(
                key: const Key('emptyImportCsv'),
                onPressed: onImport,
                icon: const Icon(Icons.upload_file),
                label: Text(l.importCsv),
              ),
              // G52 step 7: join a group someone shared by link.
              if (!kOfflineDemo)
                TextButton.icon(
                  key: const Key('emptyJoinLink'),
                  onPressed: () => context.push('/join'),
                  icon: const Icon(Icons.link),
                  label: Text(l.joinLinkEntry),
                ),
            ],
          );
        }
        final overviews = [
          for (final g in groups) ref.watch(groupOverviewProvider(g.roomId)),
        ];
        // G16: archived groups still count in the totals — an open balance
        // stays real (a settled one adds nothing anyway).
        final totals = balanceTotals(overviews.map((o) => o.myBalance));
        final archived = [
          for (final g in groups) ref.watch(groupArchivedProvider(g.roomId)),
        ];
        // G69 (U20): most recently active first (the current trip on top);
        // the archived section keeps its order.
        final active = sortGroupsByActivity([
          for (var i = 0; i < groups.length; i++)
            if (!archived[i]) (groups[i], overviews[i]),
        ]);
        final hidden = [
          for (var i = 0; i < groups.length; i++)
            if (archived[i]) (groups[i], overviews[i]),
        ];
        final nudge = ref.watch(backupNudgeProvider);
        return ListView(
          padding: EdgeInsets.fromLTRB(
            Insets.page,
            Insets.s,
            Insets.page,
            Insets.fabClearance(context),
          ),
          children: [
            ContentWidth(child: _TotalsCard(totals: totals)),
            const SizedBox(height: Insets.l),
            if (nudge.show) ...[
              ContentWidth(child: BackupNudgeCard(counts: nudge)),
              const SizedBox(height: Insets.m),
            ],
            // G54: once, after a link-only group is really in use.
            if (ref.watch(whyMatrixHintProvider)) ...[
              const ContentWidth(child: WhyMatrixHintCard()),
              const SizedBox(height: Insets.m),
            ],
            for (final (group, overview) in active)
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Insets.m),
                  child: GroupCard(group: group, overview: overview),
                ),
              ),
            if (hidden.isNotEmpty)
              ContentWidth(child: _ArchivedSection(groups: hidden)),
          ],
        );
      },
    );
  }
}

/// The collapsed "Archived (N)" section at the end of the groups list (G16).
/// Collapsed on every visit; expanding shows the archived groups' cards.
class _ArchivedSection extends StatefulWidget {
  final List<(GroupModel, GroupOverview)> groups;
  const _ArchivedSection({required this.groups});

  @override
  State<_ArchivedSection> createState() => _ArchivedSectionState();
}

class _ArchivedSectionState extends State<_ArchivedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // G71: a screen reader hears whether the section is open.
        Semantics(
          button: true,
          expanded: _expanded,
          child: InkWell(
            key: const Key('archivedSection'),
            borderRadius: BorderRadius.circular(Radii.s),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.xs,
                vertical: Insets.m,
              ),
              child: Row(
                children: [
                  Icon(Icons.archive_outlined, size: 20, color: muted),
                  const SizedBox(width: Insets.s),
                  Expanded(
                    child: Text(
                      l.archivedSection(widget.groups.length),
                      style: theme.textTheme.labelLarge?.copyWith(color: muted),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.xs,
              0,
              Insets.xs,
              Insets.m,
            ),
            child: Text(
              l.archivedSectionHint,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          for (final (group, overview) in widget.groups)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.m),
              child: GroupCard(group: group, overview: overview),
            ),
        ],
      ],
    );
  }
}

/// "Across all groups": what I am owed / what I owe, per currency (G17).
class _TotalsCard extends StatelessWidget {
  final ({Map<String, int> owed, Map<String, int> owing}) totals;
  const _TotalsCard({required this.totals});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final settled = totals.owed.isEmpty && totals.owing.isEmpty;
    final scheme = theme.colorScheme;
    final ledger = context.ledgerColors;
    final capsStyle = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    );
    TextStyle? amountStyle(Color color) =>
        theme.textTheme.headlineSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          fontFeatures: kTabularFigures,
          height: 1.2,
        );

    Widget column(
      String label,
      Map<String, int> amounts,
      Color color,
      Key key,
    ) => Expanded(
      // G71: read as one phrase ("You are owed, €21.00").
      child: MergeSemantics(
        child: Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), semanticsLabel: label, style: capsStyle),
            const SizedBox(height: Insets.xs),
            if (amounts.isEmpty)
              Text(l.totalNothing, style: amountStyle(scheme.onSurfaceVariant))
            else
              for (final MapEntry(key: c, value: v) in amounts.entries)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(context.money(v, c), style: amountStyle(color)),
                ),
          ],
        ),
      ),
    );

    // "Paper & ink" (G42): no card — a ledger rule above, a hairline below.
    return Container(
      key: const Key('groupsTotals'),
      decoration: BoxDecoration(
        border: Border(
          top: AppTheme.ledgerRule(scheme),
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: Insets.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l.overviewTitle, style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: Insets.m),
          if (settled)
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: ledger.positive),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: Text(
                    l.overallSettledUp,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                column(
                  l.totalOwedLabel,
                  totals.owed,
                  ledger.positive,
                  const Key('totalsOwed'),
                ),
                const SizedBox(width: Insets.l),
                column(
                  l.totalOwingLabel,
                  totals.owing,
                  ledger.negative,
                  const Key('totalsOwing'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One group in the list (G17): name, members, last activity and my balance.
class GroupCard extends StatelessWidget {
  final GroupModel group;
  final GroupOverview overview;
  const GroupCard({super.key, required this.group, required this.overview});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final last = overview.lastActivityAt;
    final subtitle = [
      l.membersCount(overview.members.length),
      if (last != null) context.relativeDate(last),
    ].join(' · ');
    return Card(
      key: Key('groupCard-${group.roomId}'),
      child: InkWell(
        onTap: () => context.push('/groups/${group.roomId}/expenses'),
        child: Padding(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GroupBadge(id: group.roomId, name: group.name),
                  const SizedBox(width: Insets.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: Insets.m),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AvatarStack(
                    people: [
                      for (final m in overview.members)
                        (id: m.userId, name: m.label),
                    ],
                  ),
                  const SizedBox(width: Insets.m),
                  Expanded(
                    child: BalanceSummaryText(
                      overview: overview,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group's monogram: its initials in an ink ring ([id] kept for callers).
class GroupBadge extends StatelessWidget {
  final String id;
  final String name;
  final double size;
  const GroupBadge({
    super.key,
    required this.id,
    required this.name,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      // "Paper & ink" (G42): an ink-ringed monogram, like a stamp.
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ink, width: 1.5),
      ),
      // DEV-I: scaled down instead of wrapping ("S" / "W" on two lines) at a
      // large system font size — the ring has a fixed size.
      child: Padding(
        padding: EdgeInsets.all(size * 0.12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            initialsOf(name),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: ink,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.38,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// "You are owed €12.50" (green) / "You owe €3.00" (red) / "Settled up" —
/// one line per currency (G17). Shared by the group cards and the group's
/// summary card.
class BalanceSummaryText extends StatelessWidget {
  final GroupOverview overview;
  final TextAlign textAlign;
  final TextStyle? style;
  const BalanceSummaryText({
    super.key,
    required this.overview,
    this.textAlign = TextAlign.start,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final colors = context.ledgerColors;
    final base = (style ?? theme.textTheme.bodyMedium)?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: kTabularFigures,
    );
    final neutral = base?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final crossAlign = textAlign == TextAlign.end
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    String? neutralText;
    if (overview.me == null) {
      neutralText = l.notParticipating;
    } else if (overview.myBalance.isEmpty) {
      neutralText = overview.recordCount == 0
          ? l.expensesEmptyTitle
          : l.settledUp;
    }
    if (neutralText != null) {
      return Text(
        neutralText,
        key: const Key('balanceSummary'),
        textAlign: textAlign,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: neutral,
      );
    }
    return Column(
      key: const Key('balanceSummary'),
      crossAxisAlignment: crossAlign,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final MapEntry(key: c, value: v) in overview.myBalance.entries)
          Text(
            v > 0
                ? l.youAreOwedAmount(context.money(v, c))
                : l.youOweAmount(context.money(-v, c)),
            textAlign: textAlign,
            // DEV-I: wraps instead of cutting the amount ("Du schuldest
            // 3,0…") at a large font size on a phone.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: base?.copyWith(
              color: v > 0 ? colors.positive : colors.negative,
            ),
          ),
      ],
    );
  }
}
