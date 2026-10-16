import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/matrix/crypto_status.dart';
import '../../core/l10n/l10n.dart';
import '../auth/auth_provider.dart';
import '../onboarding/onboarding_provider.dart';
import '../backup/backup_providers.dart';
import '../backup/backup_ui.dart';
import '../devices/device_provider.dart';
import '../expenses/ledger_syncer.dart';
import '../../core/background/background_sync_provider.dart';
import '../../core/sync/self_recovery.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
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
    final groupsAsync = ref.watch(ledgerGroupsProvider);
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(size: 30),
            const SizedBox(width: Insets.m),
            Flexible(
              child: Text(l.groupsTitle, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: l.importCsvTooltip,
            onPressed: () => _importCsv(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.devices),
            tooltip: l.devicesTooltip,
            onPressed: () => context.push('/devices'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l.settingsTooltip,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const SyncSettingsSheet(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmSignOut(context, ref),
            tooltip: l.signOut,
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
          if (!ref.watch(cryptoAvailableProvider))
            const _EncryptionUnavailableBanner(),
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

  /// Sign-out confirmation (G29). Signing out is non-destructive: this
  /// account's ledger DB stays on the device (per-account DB, G4) and is
  /// reopened on the next sign-in with the same account.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.signOutConfirmTitle),
        content: Text(l.signOutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.signOut),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authProvider.notifier).logout();
    if (!context.mounted) return;
    final error = ref.read(authProvider).error;
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.failedWithError(error.toString()))),
      );
    }
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
      error: (e, _) => Center(child: Text(l.errorWithDetail(e.toString()))),
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
        final active = [
          for (var i = 0; i < groups.length; i++)
            if (!archived[i]) (groups[i], overviews[i]),
        ];
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
            if (nudge > 0) ...[
              ContentWidth(child: BackupNudgeCard(count: nudge)),
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
        InkWell(
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
    const onBrand = Colors.white;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: onBrand.withValues(alpha: 0.8),
    );
    final amountStyle = theme.textTheme.titleLarge?.copyWith(
      color: onBrand,
      fontFeatures: kTabularFigures,
      height: 1.25,
    );

    Widget column(String label, Map<String, int> amounts, Key key) => Expanded(
      child: Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: Insets.xs),
          if (amounts.isEmpty)
            Text(
              l.totalNothing,
              style: amountStyle?.copyWith(
                color: onBrand.withValues(alpha: 0.7),
              ),
            )
          else
            for (final MapEntry(key: c, value: v) in amounts.entries)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(context.money(v, c), style: amountStyle),
              ),
        ],
      ),
    );

    return Container(
      key: const Key('groupsTotals'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.l),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrandColors.gradientStart, BrandColors.gradientEnd],
        ),
      ),
      padding: const EdgeInsets.all(Insets.l + Insets.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.overviewTitle,
            style: theme.textTheme.titleSmall?.copyWith(color: onBrand),
          ),
          const SizedBox(height: Insets.m),
          if (settled)
            Row(
              children: [
                const Icon(Icons.check_circle_outline, color: onBrand),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: Text(
                    l.overallSettledUp,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: onBrand,
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                column(l.totalOwedLabel, totals.owed, const Key('totalsOwed')),
                Container(
                  width: 1,
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: Insets.m),
                  color: onBrand.withValues(alpha: 0.25),
                ),
                column(
                  l.totalOwingLabel,
                  totals.owing,
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

/// A group's rounded-square icon: its initial on a colour from the group id.
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
    final colors = context.ledgerColors;
    final i = avatarIndexFor(id, colors.avatarBackgrounds.length);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.avatarBackgrounds[i],
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          color: colors.avatarForegrounds[i],
          fontWeight: FontWeight.w700,
          fontSize: size * 0.38,
          height: 1,
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
        maxLines: 1,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: base?.copyWith(
              color: v > 0 ? colors.positive : colors.negative,
            ),
          ),
      ],
    );
  }
}

/// G11: the opt-in "Only sync with verified devices" switch (per account,
/// device-local). Turning it on asks first and spells out the consequence.
class VerifiedOnlySyncTile extends ConsumerWidget {
  const VerifiedOnlySyncTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final on = ref.watch(verifiedOnlySyncProvider).value ?? false;
    return SwitchListTile(
      key: const Key('verifiedOnlySwitch'),
      secondary: const Icon(Icons.verified_user_outlined),
      title: Text(l.verifiedOnlyTitle),
      subtitle: Text(on ? l.verifiedOnlyOnBody : l.verifiedOnlyOffBody),
      value: on,
      onChanged: (v) async {
        final settings = ref.read(settingsDaoProvider);
        if (v) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l.verifiedOnlyConfirmTitle),
              content: Text(l.verifiedOnlyConfirmBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l.cancel),
                ),
                FilledButton(
                  key: const Key('verifiedOnlyConfirm'),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(l.verifiedOnlyTurnOn),
                ),
              ],
            ),
          );
          if (ok != true) return;
        }
        await settings.setVerifiedOnlySync(v);
      },
    );
  }
}

/// Settings sheet (G31 sync settings, G11 verified-only, G5 backup, G12 about): explains when
/// this device syncs and, on Android, toggles the periodic background sync for
/// the signed-in account; backs up / restores all groups; links to the About
/// page.
class SyncSettingsSheet extends ConsumerWidget {
  const SyncSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final supported = ref.watch(backgroundSyncSupportedProvider);
    final enabled = ref.watch(backgroundSyncEnabledProvider).value ?? true;
    final schedulingError = ref.watch(backgroundSyncSchedulingErrorProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(l.syncSettingsTitle),
              subtitle: Text(l.syncSettingsBody),
            ),
            if (supported)
              SwitchListTile(
                key: const Key('backgroundSyncSwitch'),
                secondary: const Icon(Icons.sync),
                title: Text(l.backgroundSyncTitle),
                subtitle: Text(l.backgroundSyncBody),
                value: enabled,
                onChanged: (v) =>
                    ref.read(settingsDaoProvider).setBackgroundSyncEnabled(v),
              ),
            // G33: the OS refused to (un)register the task — say so.
            if (supported && schedulingError != null)
              ListTile(
                key: const Key('backgroundSyncError'),
                leading: Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  l.backgroundSyncScheduleFailed(schedulingError.toString()),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!supported)
              ListTile(
                leading: const Icon(Icons.sync_disabled),
                title: Text(l.noBackgroundSyncTitle),
                subtitle: Text(l.noBackgroundSyncBody),
              ),
            const VerifiedOnlySyncTile(),
            const Divider(),
            const BackupSettingsSection(),
            const Divider(),
            ListTile(
              key: const Key('aboutTile'),
              leading: const Icon(Icons.info_outline),
              title: Text(l.aboutTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/about');
              },
            ),
          ],
        ),
      ),
    );
  }
}
