/// G68 (U24) + G52 step 9: the group page's sync icon and the sync sheet it
/// opens — **one sheet for Matrix and link groups**: a summary line, one row
/// per person, *Sync now*.
///
/// * **Matrix group** — the cloud follows `groupSyncStatusProvider` /
///   `SyncHealth` as before (synced / pending / failing); the rows come from
///   the anti-entropy proofs ([matrixPeerRows]: has everything / waiting /
///   no device / no verified device, plus our other devices). *Sync now*
///   sends the group's digest right away (`SyncEngine.syncGroupNow`).
/// * **Link group** (a channel on this device) — the cloud follows
///   `linkGroupSyncStatusProvider` (§5.3); the rows are the publishers seen
///   on the relays ([linkPeerRows]: "has everything" when their snapshot
///   equals ours, else "last update …"), plus a *Relays* entry. *Sync now* =
///   one full fetch + an immediate publish check (`LinkSyncEngine.syncNow`).
/// * Local mode without a link channel: no icon (nothing syncs).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/link/link_sync_engine.dart';
import '../../core/session/app_session.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_health.dart';
import '../../core/sync/sync_status_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/person_avatar.dart';
import '../../models/link_model.dart';
import '../../models/member_model.dart';
import '../expenses/expenses_provider.dart' show linkDaoProvider;
import '../groups/group_provider.dart';
import '../link/link_invite.dart';
import '../link/relay_settings_page.dart' show kRelaySettingsLocation;
import 'peer_sync_rows.dart';

/// What *Sync now* did.
enum GroupSyncNowResult {
  /// Matrix: the digest went out (answers come while the others' apps run).
  sent,

  /// Link: at least one relay answered the fetch.
  checked,

  /// Link: no relay answered.
  unreachable,
}

typedef GroupSyncNow =
    Future<GroupSyncNowResult> Function(String groupId, {required bool link});

/// The sheet's *Sync now* seam (widget tests replace it).
final groupSyncNowProvider = Provider<GroupSyncNow>(
  (ref) => (groupId, {required link}) async {
    if (link) {
      final r = await ref
          .read(linkSyncEngineProvider)
          .syncNow(groupId, timeout: const Duration(seconds: 10));
      return r.anyComplete
          ? GroupSyncNowResult.checked
          : GroupSyncNowResult.unreachable;
    }
    await ref.read(syncEngineProvider).syncGroupNow(groupId);
    return GroupSyncNowResult.sent;
  },
);

/// The link peers of a group (`link_peers`) — the sheet's rows.
final groupLinkPeersProvider = StreamProvider.autoDispose
    .family<List<LinkPeerModel>, String>(
      (ref, groupId) => ref.watch(linkDaoProvider).watchPeers(groupId),
    );

/// This device's link channel of a group (null: none).
final groupLinkChannelProvider = StreamProvider.autoDispose
    .family<LinkChannelModel?, String>(
      (ref, groupId) => ref.watch(linkDaoProvider).watchChannel(groupId),
    );

/// Whether [groupId] syncs by link here (a channel exists): derived from
/// the invite state the group page already watches. Null while loading.
final groupSyncsByLinkProvider = Provider.autoDispose.family<bool?, String>((
  ref,
  groupId,
) {
  final s = ref.watch(linkInviteStateProvider(groupId));
  if (!s.hasValue) return s.hasError ? false : null;
  return s.requireValue == LinkInviteState.open;
});

/// The app-bar sync icon of the group page — tappable, opens the sheet.
class GroupSyncButton extends ConsumerWidget {
  final String groupId;
  const GroupSyncButton({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(groupSyncsByLinkProvider(groupId));
    if (link == null) return const SizedBox.shrink();
    if (link) return _LinkSyncButton(groupId: groupId);
    // G40: nothing syncs in local mode (without a link).
    if (ref.watch(localModeActiveProvider)) return const SizedBox.shrink();
    return _MatrixSyncButton(groupId: groupId);
  }
}

class _MatrixSyncButton extends ConsumerWidget {
  final String groupId;
  const _MatrixSyncButton({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(groupSyncStatusProvider(groupId));
    final health = ref.watch(syncHealthProvider);
    final l = context.l10n;
    final IconData icon;
    final String tooltip;
    Color? color;
    if (health.failing) {
      icon = Icons.cloud_off;
      color = Theme.of(context).colorScheme.error;
      tooltip = l.syncProblemTooltip;
    } else if (status.synced) {
      icon = Icons.cloud_done_outlined;
      tooltip = l.syncedWithAll;
    } else {
      icon = Icons.cloud_queue;
      // A pending peer with no logged-in device (G24) or no verified one
      // (G11) isn't a sync error — say so instead of "waiting" forever.
      final hint = pendingPeerHint(status.pendingPeers, health);
      tooltip = switch (hint.reason) {
        PendingReason.unverified => l.peerHasNoVerifiedDevice(hint.peer),
        PendingReason.noDevice => l.peerHasNoDevice(hint.peer),
        PendingReason.waiting => l.waitingForPeer(hint.peer),
      };
    }
    return IconButton(
      key: const Key('groupSyncButton'),
      icon: Icon(icon, color: color),
      tooltip: tooltip,
      onPressed: () => showGroupSyncSheet(context, groupId, link: false),
    );
  }
}

class _LinkSyncButton extends ConsumerWidget {
  final String groupId;
  const _LinkSyncButton({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(linkGroupSyncStatusProvider(groupId)).value;
    final l = context.l10n;
    final phase = status?.phase ?? LinkSyncPhase.pending;
    final (icon, tooltip, error) = switch (phase) {
      LinkSyncPhase.failing => (Icons.cloud_off, l.syncProblemTooltip, true),
      LinkSyncPhase.synced => (
        Icons.cloud_done_outlined,
        l.linkCloudSynced,
        false,
      ),
      LinkSyncPhase.pending => (Icons.cloud_queue, l.linkSyncPending, false),
    };
    return IconButton(
      key: const Key('groupSyncButton'),
      icon: Icon(
        icon,
        color: error ? Theme.of(context).colorScheme.error : null,
      ),
      tooltip: tooltip,
      onPressed: () => showGroupSyncSheet(context, groupId, link: true),
    );
  }
}

/// Opens the sync sheet of [groupId].
Future<void> showGroupSyncSheet(
  BuildContext context,
  String groupId, {
  required bool link,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => GroupSyncSheet(groupId: groupId, link: link),
);

/// The sheet (see the library doc).
class GroupSyncSheet extends ConsumerStatefulWidget {
  final String groupId;
  final bool link;
  const GroupSyncSheet({super.key, required this.groupId, required this.link});

  @override
  ConsumerState<GroupSyncSheet> createState() => _GroupSyncSheetState();
}

class _GroupSyncSheetState extends ConsumerState<GroupSyncSheet> {
  bool _running = false;
  String? _result;

  Future<void> _syncNow() async {
    final l = context.l10n;
    final run = ref.read(groupSyncNowProvider);
    setState(() {
      _running = true;
      _result = null;
    });
    String text;
    try {
      final r = await run(widget.groupId, link: widget.link);
      text = switch (r) {
        GroupSyncNowResult.sent => l.syncNowSent,
        GroupSyncNowResult.checked => l.syncNowChecked,
        GroupSyncNowResult.unreachable => l.syncNowUnreachable,
      };
    } catch (_) {
      text = widget.link ? l.syncNowUnreachable : l.syncProblemBody;
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final members =
        ref.watch(groupMembersProvider(widget.groupId)).value ??
        const <MemberModel>[];
    final content = widget.link
        ? _linkContent(context, members)
        : _matrixContent(context, members);
    return ListView(
      key: const Key('groupSyncSheet'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(0, Insets.l, 0, Insets.l),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.page),
          child: Semantics(
            header: true,
            child: Text(l.syncSheetTitle, style: theme.textTheme.titleLarge),
          ),
        ),
        const SizedBox(height: Insets.s),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.page),
          child: Text(
            content.summary,
            key: const Key('groupSyncSummary'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: content.problem ? theme.colorScheme.error : null,
            ),
          ),
        ),
        for (final extra in content.details)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.page,
              Insets.xs,
              Insets.page,
              0,
            ),
            child: Text(extra, style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: Insets.s),
        if (content.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.page,
              vertical: Insets.s,
            ),
            child: Text(
              content.empty,
              key: const Key('groupSyncEmpty'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final row in content.rows) _PeerTile(row: row, link: widget.link),
        if (content.footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.page,
              Insets.s,
              Insets.page,
              0,
            ),
            child: Text(
              content.footer!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (widget.link)
          ListTile(
            key: const Key('groupSyncRelays'),
            leading: const Icon(Icons.hub_outlined),
            title: Text(l.relaysTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.push(kRelaySettingsLocation);
            },
          ),
        const SizedBox(height: Insets.m),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.page),
          child: FilledButton.icon(
            key: const Key('groupSyncNow'),
            onPressed: _running ? null : _syncNow,
            icon: _running
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(l.syncNow),
          ),
        ),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.page,
              Insets.s,
              Insets.page,
              0,
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _result!,
                key: const Key('groupSyncResult'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }

  _SheetContent _matrixContent(
    BuildContext context,
    List<MemberModel> members,
  ) {
    final l = context.l10n;
    final status = ref.watch(groupSyncStatusProvider(widget.groupId));
    final health = ref.watch(syncHealthProvider);
    final self = ref.watch(currentUserIdProvider);
    final rows = matrixPeerRows(
      selfMxid: self,
      members: members,
      peerInSyncAt: status.peerInSyncAt,
      maxRecordUpdatedAt: status.maxRecordUpdatedAt,
      health: health,
    );
    final details = <String>[
      if (health.failing && health.lastSuccessAt != null)
        l.lastSynced(agoText(l, health.lastSuccessAt!)),
      if (health.failing && health.lastError != null)
        l.lastError(health.lastError.toString()),
    ];
    return _SheetContent(
      summary: health.failing
          ? l.syncProblemBody
          : status.synced
          ? l.syncSheetAllSynced
          : l.syncSheetPending,
      problem: health.failing,
      details: details,
      rows: rows,
      empty: l.syncSheetNoPeers,
      footer: localOnlyPeople(members) > 0 ? l.syncSheetLocalPeople : null,
    );
  }

  _SheetContent _linkContent(BuildContext context, List<MemberModel> members) {
    final l = context.l10n;
    final status = ref.watch(linkGroupSyncStatusProvider(widget.groupId)).value;
    final peers =
        ref.watch(groupLinkPeersProvider(widget.groupId)).value ??
        const <LinkPeerModel>[];
    final channel = ref.watch(groupLinkChannelProvider(widget.groupId)).value;
    final synced = status?.phase == LinkSyncPhase.synced;
    final rows = linkPeerRows(
      peers: peers,
      members: members,
      myParticipantId: channel?.myParticipantId,
      ourDigest: synced ? channel?.lastPublishedHash : null,
      ourParts: channel?.parts ?? 1,
    );
    final published = status?.lastPublishedAt;
    final summary = switch (status?.problem) {
      LinkSyncProblem.notDelivered => l.linkSyncNotDelivered,
      LinkSyncProblem.relaysReject => l.linkSyncRelaysReject,
      LinkSyncProblem.tooLarge => l.linkSyncTooLarge,
      LinkSyncProblem.noParticipant => l.linkSyncNoParticipant,
      LinkSyncProblem.mergeFailed => l.linkSyncMergeFailed,
      null =>
        synced
            ? (published != null
                  ? l.linkSyncSynced(agoText(l, published))
                  : l.linkSyncSyncedNoTime)
            : l.linkSyncPending,
    };
    return _SheetContent(
      summary: summary,
      problem: status?.phase == LinkSyncPhase.failing,
      details: const [],
      rows: rows,
      empty: l.syncSheetLinkNoPeers,
      footer: l.syncSheetLinkHint,
    );
  }
}

class _SheetContent {
  final String summary;
  final bool problem;
  final List<String> details;
  final List<PeerSyncRow> rows;
  final String empty;
  final String? footer;
  const _SheetContent({
    required this.summary,
    required this.problem,
    required this.details,
    required this.rows,
    required this.empty,
    required this.footer,
  });
}

/// One person's row.
class _PeerTile extends StatelessWidget {
  final PeerSyncRow row;
  final bool link;
  const _PeerTile({required this.row, required this.link});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final name = row.isSelf ? l.peerYourDevices : (row.name ?? l.peerUnknown);
    final at = row.at;
    final status = switch (row.kind) {
      PeerSyncKind.upToDate =>
        at != null && !link ? l.peerUpToDateAt(agoText(l, at)) : l.peerUpToDate,
      PeerSyncKind.waiting =>
        at != null ? l.peerWaitingSince(agoText(l, at)) : l.peerWaitingNever,
      PeerSyncKind.noDevice => l.peerNoDevice,
      PeerSyncKind.unverified => l.peerUnverified,
      PeerSyncKind.published => l.peerPublishedAt(
        at != null ? agoText(l, at) : '—',
      ),
    };
    final (icon, color) = switch (row.kind) {
      PeerSyncKind.upToDate => (
        Icons.check_circle_outline,
        context.ledgerColors.positive,
      ),
      PeerSyncKind.noDevice ||
      PeerSyncKind.unverified => (Icons.error_outline, theme.colorScheme.error),
      PeerSyncKind.waiting || PeerSyncKind.published => (
        Icons.schedule,
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    final devices = row.devices > 1 ? ' · ${l.peerDevices(row.devices)}' : '';
    return ListTile(
      key: Key('peerSync-${row.isSelf ? 'self' : row.participantId ?? '?'}'),
      leading: row.isSelf || row.participantId == null
          ? CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                row.isSelf ? Icons.devices_other : Icons.person_outline,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : PersonAvatar(id: row.participantId!, name: name),
      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('$status$devices'),
      trailing: Icon(icon, color: color),
    );
  }
}
