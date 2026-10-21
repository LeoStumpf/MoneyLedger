import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/settings_section.dart';
import '../../models/member_model.dart';
import 'group_actions.dart';
import 'group_archive_provider.dart';
import 'group_overview_provider.dart';
import 'group_provider.dart';
import '../link/link_invite.dart';
import '../../core/widgets/large_text.dart';

/// G65: route of a group's settings page.
String groupSettingsLocation(String roomId) => '/groups/$roomId/settings';

/// G65 (U22): the group settings page (group ⋮ → *Group settings*, or a tap
/// on the group page's title) — replaces the long ⋮ menu. Sections:
///
/// * **Group** — name & currency (G10), categories (G47);
/// * **People** — the people page; G52 step 6: *Invite with a link* (link
///   groups, local mode) — G53 adds *Secure the group*;
/// * **Data** — back up this group (G34), export CSV (G13), reset to an
///   earlier state (G48);
/// * **On this device** — archive / unarchive (G16, device-local);
/// * **Leave or delete** (G9) — last, in the error colour (G52 step 12 adds
///   *Reset invite link* near it).
///
/// A read-only group (we were removed, G26) keeps its restrictions: no
/// edit, no reset; the exit is *Delete* ([groupExitKind]).
class GroupSettingsPage extends ConsumerWidget {
  final String roomId;
  const GroupSettingsPage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    // Keep the (auto-dispose) notifiers alive while their flows run.
    ref.watch(groupExiterProvider);
    final editorState = ref.watch(groupEditorProvider);
    ref.watch(groupArchiverProvider);
    final group = (ref.watch(ledgerGroupsProvider).value ?? const [])
        .where((g) => g.roomId == roomId)
        .firstOrNull;
    final members =
        ref.watch(groupMembersProvider(roomId)).value ?? const <MemberModel>[];
    final me = ref.watch(currentParticipantProvider(roomId)).value;
    final canEdit = me?.isActive ?? false;
    final archived = ref.watch(groupArchivedProvider(roomId));
    final overview = ref.watch(groupOverviewProvider(roomId));
    final exitKind = groupExitKind(members, ref.watch(currentUserIdProvider));
    final activeCount = members.where((m) => m.isActive).length;
    final leave = exitKind == GroupExitKind.leave;
    // G52 step 6: link groups / local-mode groups only.
    final linkState =
        ref.watch(linkInviteStateProvider(roomId)).value ??
        LinkInviteState.unavailable;

    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l.groupSettingsTitle)),
      body: ContentWidth(
        child: ListView(
          key: const Key('groupSettingsList'),
          padding: EdgeInsets.only(
            bottom: Insets.xl + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            SettingsSectionHeader(l.groupSectionGroup),
            ListTile(
              key: const Key('editGroupTile'),
              leading: const Icon(Icons.edit_outlined),
              title: Text(l.groupNameAndCurrency),
              subtitle: group == null
                  ? null
                  : Text(
                      l.groupNameCurrencyValue(group.name, group.currency),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              enabled: canEdit && !editorState.isLoading,
              onTap: () => editGroupFlow(context, ref, roomId),
            ),
            ListTile(
              key: const Key('categoriesTile'),
              leading: const Icon(Icons.label_outline),
              title: Text(l.manageCategories),
              subtitle: Text(l.categoriesTileBody),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/groups/$roomId/categories'),
            ),
            SettingsSectionHeader(l.membersTitle),
            ListTile(
              key: const Key('peopleTile'),
              leading: const Icon(Icons.group_outlined),
              title: Text(l.membersTitle),
              subtitle: Text(l.membersCount(activeCount)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/groups/$roomId/members'),
            ),
            if (linkState != LinkInviteState.unavailable)
              ListTile(
                key: const Key('inviteLinkTile'),
                leading: const Icon(Icons.link),
                title: Text(l.inviteByLink),
                subtitle: Text(
                  linkState == LinkInviteState.open
                      ? l.inviteByLinkTileBodyOpen
                      : l.inviteByLinkTileBody,
                ),
                enabled: canEdit,
                onTap: () => inviteByLinkFlow(context, ref, roomId),
              ),
            SettingsSectionHeader(l.settingsSectionData),
            ListTile(
              key: const Key('backupGroupTile'),
              leading: const Icon(Icons.backup_outlined),
              title: Text(l.backupThisGroup),
              subtitle: Text(l.backupGroupTileBody),
              onTap: () => backupGroupFlow(context, ref, roomId),
            ),
            ListTile(
              key: const Key('exportCsvTile'),
              leading: const Icon(Icons.table_chart_outlined),
              title: Text(l.exportCsv),
              subtitle: Text(l.exportCsvTileBody),
              onTap: () => exportGroupCsvFlow(context, ref, roomId),
            ),
            // G48: not for a read-only group — peers would refuse our
            // versions.
            ListTile(
              key: const Key('resetGroupTile'),
              leading: const Icon(Icons.history),
              title: Text(l.groupResetMenu),
              subtitle: Text(l.groupResetTileBody),
              trailing: const Icon(Icons.chevron_right),
              enabled: canEdit,
              onTap: () => context.push('/groups/$roomId/reset'),
            ),
            SettingsSectionHeader(l.groupSectionDevice),
            ListTile(
              key: const Key('archiveTile'),
              leading: Icon(
                archived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              title: Text(archived ? l.unarchiveGroup : l.archiveGroup),
              subtitle: Text(
                archived ? l.unarchiveTileBody : l.archiveTileBody,
              ),
              onTap: () => toggleGroupArchive(
                context,
                ref,
                roomId,
                archived: archived,
                unsettled: overview.myBalance.isNotEmpty,
              ),
            ),
            SettingsSectionHeader(l.groupSectionExit, danger: true),
            ListTile(
              key: const Key('exitGroupTile'),
              leading: Icon(
                leave ? Icons.logout : Icons.delete_outline,
                color: scheme.error,
              ),
              title: Text(
                leave ? l.leaveGroup : l.deleteGroup,
                style: TextStyle(color: scheme.error),
              ),
              subtitle: Text(
                leave ? l.leaveGroupTileBody : l.deleteGroupTileBody,
              ),
              onTap: () => exitGroupFlow(context, ref, roomId, exitKind),
            ),
          ],
        ),
      ),
    );
  }
}
