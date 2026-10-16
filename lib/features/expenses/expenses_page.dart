import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/session/app_session.dart';
import '../../core/l10n/l10n.dart';
import '../../core/widgets/text_prompt_dialog.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_health.dart';
import '../../core/sync/sync_status_provider.dart';
import '../../models/expense_category.dart';
import '../../models/expense_model.dart';
import '../../models/member_model.dart';
import '../backup/csv_export.dart';
import '../backup/ledger_backup.dart' show savedFileDisplayName;
import '../backup/backup_files.dart';
import '../backup/backup_ui.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/names_line.dart';
import '../balance/balance_calculator.dart';
import '../balance/balance_provider.dart';
import '../balance/settle_up.dart';
import '../groups/add_person_dialog.dart';
import '../groups/group_overview_provider.dart';
import '../groups/groups_page.dart' show BalanceSummaryText;
import '../groups/group_edit_dialog.dart';
import '../groups/group_exit_dialog.dart';
import '../groups/group_archive_provider.dart';
import '../groups/group_provider.dart';
import '../onboarding/onboarding_provider.dart' show settingsDaoProvider;
import 'expense_category_ui.dart';
import 'expense_filter.dart';
import 'expenses_provider.dart';
import 'ledger_search_provider.dart';
import 'ledger_syncer.dart';
import '../../core/sync/record_signing.dart' show RecordKind;
import '../../models/record_signature.dart';
import 'record_attribution.dart';

enum _GroupMenuAction { addMember, edit, archive, export, backup, exit }

class ExpensesPage extends ConsumerWidget {
  final String roomId;
  const ExpensesPage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerSyncerProvider);
    ref.watch(syncEngineProvider); // run anti-entropy while this group is open
    final expensesAsync = ref.watch(expensesForRoomProvider(roomId));
    final settlementsAsync = ref.watch(settlementsForRoomProvider(roomId));
    final syncStatus = ref.watch(groupSyncStatusProvider(roomId));
    final names = ref.watch(participantNamesProvider(roomId));
    final meAsync = ref.watch(currentParticipantProvider(roomId));
    final members =
        ref.watch(groupMembersProvider(roomId)).value ?? const <MemberModel>[];
    final group = (ref.watch(ledgerGroupsProvider).value ?? const [])
        .where((g) => g.roomId == roomId)
        .firstOrNull;
    final overview = ref.watch(groupOverviewProvider(roomId));
    // Invited but not yet linked to anyone in this group → offer self-claim.
    final needsClaim =
        meAsync.hasValue &&
        meAsync.value == null &&
        members.any((m) => m.isActive);
    // G26: another member removed us — the group stays as read-only history
    // (peers would reject our writes anyway) until we delete it here.
    final removed = meAsync.value != null && !meAsync.value!.isActive;
    final canEdit = meAsync.value?.isActive ?? false;
    final adderState = ref.watch(memberAdderProvider);
    // Keep the (auto-dispose) expense notifier alive while this page can
    // trigger deletes / settle-ups — a bare `read` in the dialog callback
    // would let it be disposed mid-write.
    final expenseState = ref.watch(expenseAdderProvider);
    // Same for the leave/delete (G9) and edit-group (G10) notifiers.
    ref.watch(groupExiterProvider);
    ref.watch(groupEditorProvider);
    ref.watch(groupArchiverProvider);
    // G16: search / filter (null = search bar closed) and the device-local
    // archive.
    final search = ref.watch(ledgerSearchProvider(roomId));
    final archived = ref.watch(groupArchivedProvider(roomId));
    final exitKind = groupExitKind(members, ref.watch(currentUserIdProvider));
    final l = context.l10n;
    final theme = Theme.of(context);
    final activeCount = members.where((m) => m.isActive).length;

    return Scaffold(
      appBar: AppBar(
        // G17: the group's name (not just "Expenses"), members as subtitle;
        // G16: the search field while searching.
        title: search != null
            ? _SearchField(roomId: roomId)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    group?.name ?? l.expensesTitle,
                    key: const Key('groupTitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (members.isNotEmpty)
                    Text(
                      l.membersCount(activeCount),
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
        actions: search != null
            ? [
                IconButton(
                  key: const Key('closeSearch'),
                  icon: const Icon(Icons.close),
                  tooltip: l.closeSearch,
                  onPressed: () =>
                      ref.read(ledgerSearchProvider(roomId).notifier).close(),
                ),
              ]
            : [
                IconButton(
                  key: const Key('openSearch'),
                  icon: const Icon(Icons.search),
                  tooltip: l.searchTooltip,
                  onPressed: () =>
                      ref.read(ledgerSearchProvider(roomId).notifier).open(),
                ),
                // G40: nothing syncs in local mode.
                if (!ref.watch(localModeActiveProvider))
                  _SyncStatusIcon(status: syncStatus),
                IconButton(
                  icon: const Icon(Icons.group_outlined),
                  tooltip: l.membersTitle,
                  onPressed: () => context.push('/groups/$roomId/members'),
                ),
                // Less frequent group actions live in an overflow menu so the app
                // bar stays uncluttered on phones (and the title isn't truncated —
                // G12, "Ausgaben").
                PopupMenuButton<_GroupMenuAction>(
                  tooltip: l.moreTooltip,
                  onSelected: (action) => switch (action) {
                    _GroupMenuAction.addMember => showAddPersonDialog(
                      context,
                      ref,
                      roomId,
                    ),
                    _GroupMenuAction.edit => _editGroup(context, ref),
                    _GroupMenuAction.archive => _toggleArchive(
                      context,
                      ref,
                      archived: archived,
                      unsettled: overview.myBalance.isNotEmpty,
                    ),
                    _GroupMenuAction.export => _exportCsv(context, ref),
                    _GroupMenuAction.backup => _backupGroup(context, ref),
                    _GroupMenuAction.exit => _exitGroup(context, ref, exitKind),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _GroupMenuAction.addMember,
                      enabled: !adderState.isLoading && !removed,
                      child: ListTile(
                        leading: const Icon(Icons.person_add_outlined),
                        title: Text(l.addMember),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _GroupMenuAction.edit,
                      enabled: canEdit,
                      child: ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: Text(l.editGroup),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _GroupMenuAction.archive,
                      child: ListTile(
                        key: const Key('archiveMenuItem'),
                        leading: Icon(
                          archived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                        ),
                        title: Text(
                          archived ? l.unarchiveGroup : l.archiveGroup,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _GroupMenuAction.export,
                      child: ListTile(
                        leading: const Icon(Icons.save_alt),
                        title: Text(l.exportCsv),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _GroupMenuAction.backup,
                      child: ListTile(
                        key: const Key('backupGroupMenuItem'),
                        leading: const Icon(Icons.backup_outlined),
                        title: Text(l.backupThisGroup),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _GroupMenuAction.exit,
                      child: ListTile(
                        leading: Icon(
                          exitKind == GroupExitKind.leave
                              ? Icons.logout
                              : Icons.delete_outline,
                        ),
                        title: Text(
                          exitKind == GroupExitKind.leave
                              ? l.leaveGroup
                              : l.deleteGroup,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
      ),
      floatingActionButton: removed || search != null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/groups/$roomId/expenses/add'),
              icon: const Icon(Icons.add),
              label: Text(l.addExpense),
            ),
      body: Column(
        children: [
          if (removed)
            MaterialBanner(
              content: Text(l.removedFromGroupBanner),
              leading: const Icon(Icons.person_off_outlined),
              actions: [
                TextButton(
                  onPressed: () =>
                      _exitGroup(context, ref, GroupExitKind.delete),
                  child: Text(l.deleteFromThisDevice),
                ),
              ],
            ),
          if (archived && search == null)
            MaterialBanner(
              key: const Key('archivedBanner'),
              content: Text(l.archivedBanner),
              leading: const Icon(Icons.archive_outlined),
              actions: [
                TextButton(
                  onPressed: () => _toggleArchive(
                    context,
                    ref,
                    archived: true,
                    unsettled: false,
                  ),
                  child: Text(l.unarchiveGroup),
                ),
              ],
            ),
          if (search != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _FilterBar(
                roomId: roomId,
                filter: search,
                categories: usedCategories(
                  expensesAsync.value ?? const <ExpenseModel>[],
                ),
                canFilterMe: meAsync.value != null,
              ),
            ),
          if (needsClaim)
            MaterialBanner(
              content: Text(l.addedToGroupBanner),
              leading: const Icon(Icons.person_pin_circle_outlined),
              actions: [
                TextButton(
                  onPressed: () => _showClaimPicker(context, ref, members),
                  child: Text(l.choose),
                ),
              ],
            ),
          Expanded(
            child: Stack(
              children: [
                _ledgerList(
                  context,
                  ref,
                  expensesAsync,
                  settlementsAsync,
                  names,
                  syncStatus,
                  overview,
                  readOnly: removed,
                  busy: expenseState.isLoading,
                  myId: meAsync.value?.userId,
                  filter: search,
                ),
                if (adderState.isLoading)
                  ColoredBox(
                    color: theme.colorScheme.scrim.withValues(alpha: 0.2),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Expenses and settlements merged into one newest-first list, grouped
  /// under day headers (G17), below the group's balance summary. Both DAO
  /// streams already drop tombstones, so deleted records never show.
  Widget _ledgerList(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<ExpenseModel>> expensesAsync,
    AsyncValue<List<SettlementModel>> settlementsAsync,
    Map<String, String> names,
    GroupSyncStatus syncStatus,
    GroupOverview overview, {
    required bool readOnly,
    required bool busy,
    required String? myId,
    LedgerFilter? filter,
  }) {
    final l = context.l10n;
    if (expensesAsync.hasError) {
      return Center(
        child: Text(l.errorWithDetail(expensesAsync.error.toString())),
      );
    }
    if (settlementsAsync.hasError) {
      return Center(
        child: Text(l.errorWithDetail(settlementsAsync.error.toString())),
      );
    }
    if (!expensesAsync.hasValue || !settlementsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    // G16: the search bar's filter (names as shown: "you" for me).
    String searchName(String id) =>
        id == myId ? l.you : (names[id] ?? localpartOf(id));
    final f = filter ?? LedgerFilter.none;
    final entries = <({int createdAt, Object record})>[
      for (final e in expensesAsync.value!)
        if (!f.isActive || expenseMatches(e, f, nameOf: searchName, myId: myId))
          (createdAt: e.createdAt, record: e),
      for (final s in settlementsAsync.value!)
        if (!f.isActive ||
            settlementMatches(
              s,
              f,
              nameOf: searchName,
              myId: myId,
              paymentLabel: l.paymentLabel,
            ))
          (createdAt: s.createdAt, record: s),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (entries.isEmpty && f.isActive) {
      return EmptyState(
        key: const Key('noMatches'),
        icon: Icons.search_off,
        title: l.noMatchesTitle,
        body: l.noMatchesBody,
        actions: [
          OutlinedButton(
            onPressed: () =>
                ref.read(ledgerSearchProvider(roomId).notifier).clear(),
            child: Text(l.clearFilters),
          ),
        ],
      );
    }
    if (entries.isEmpty) {
      return EmptyState(
        key: const Key('expensesEmpty'),
        icon: Icons.receipt_long_outlined,
        title: l.expensesEmptyTitle,
        body: readOnly ? null : l.expensesEmptyBody,
      );
    }
    String nameOf(String id) =>
        id == myId ? l.you : (names[id] ?? localpartOf(id));
    // G6: flag signature problems (key conflicts, someone posing as us).
    final keys = ref.watch(knownDeviceKeysProvider).value ?? const [];
    final myMxid = ref.watch(currentUserIdProvider);
    bool attention(RecordSignature? origin, RecordSignature? sig) =>
        keys.isNotEmpty &&
        recordNeedsAttention(
          origin: origin,
          sig: sig,
          myMxid: myMxid,
          keys: keys,
          group: roomId,
        );

    Widget tileFor(Object record) {
      if (record is SettlementModel) {
        final from = names[record.fromUser] ?? localpartOf(record.fromUser);
        final to = names[record.toUser] ?? localpartOf(record.toUser);
        // G33: each name ellipsizes on its own, so both stay visible.
        final a = NamesLine.sentinel(0), b = NamesLine.sentinel(1);
        return _SettlementTile(
          settlement: record,
          title: NamesLine(
            key: const Key('settlementTitle'),
            template: record.fromUser == myId
                ? l.settlementYouPaid(b)
                : record.toUser == myId
                ? l.settlementPaidYou(a)
                : l.settlementTitle(a, b),
            names: {a: from, b: to},
          ),
          pending: syncStatus.isRecordPending(record.updatedAt),
          attention: attention(record.origin, record.sig),
          onDelete: readOnly
              ? null
              : () => _confirmDeleteSettlement(context, ref, record, from, to),
        );
      }
      final expense = record as ExpenseModel;
      return _ExpenseTile(
        expense: expense,
        payerLine: expense.paidBy == myId
            ? l.youPaid
            : l.paidByName(nameOf(expense.paidBy)),
        effect: myId == null ? null : expenseEffectFor(expense, myId),
        pending: syncStatus.isRecordPending(expense.updatedAt),
        attention: attention(expense.origin, expense.sig),
        onTap: readOnly
            ? null
            : () =>
                  context.push('/groups/$roomId/expenses/edit', extra: expense),
        onDelete: readOnly ? null : () => _confirmDelete(context, ref, expense),
      );
    }

    // Day sections, newest first.
    final sections = <({int day, List<Object> records})>[];
    for (final e in entries) {
      final d = DateTime.fromMillisecondsSinceEpoch(e.createdAt);
      final day = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
      if (sections.isEmpty || sections.last.day != day) {
        sections.add((day: day, records: [e.record]));
      } else {
        sections.last.records.add(e.record);
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Insets.page,
        Insets.s,
        Insets.page,
        Insets.fabClearance(context),
      ),
      children: [
        if (filter != null)
          ContentWidth(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                Insets.xs,
                Insets.s,
                Insets.xs,
                0,
              ),
              child: Text(
                l.filterResultCount(entries.length),
                textAlign: TextAlign.start,
                key: const Key('filterResultCount'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ContentWidth(
            child: _GroupSummaryCard(
              overview: overview,
              readOnly: readOnly,
              busy: busy,
              onSettleUp: () {
                final String my = myId ?? ref.read(currentUserIdProvider);
                recordPaymentFlow(
                  context,
                  ref,
                  roomId,
                  myId: my,
                  debt: settleUpSuggestion(
                    ref.read(balanceForRoomProvider(roomId)),
                    my,
                  ),
                );
              },
              onBalances: () => context.push('/groups/$roomId/balance'),
            ),
          ),
        for (final section in sections)
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DayHeader(text: context.dayHeader(section.day)),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < section.records.length; i++) ...[
                        if (i > 0) const Divider(indent: 72),
                        tileFor(section.records[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Leave / delete this group (G9) after a confirmation that warns about an
  /// unsettled balance; then back to the groups list.
  Future<void> _exitGroup(
    BuildContext context,
    WidgetRef ref,
    GroupExitKind kind,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final group = await ref.read(groupsDaoProvider).getGroup(roomId);
    if (!context.mounted) return;
    final me = ref.read(currentParticipantProvider(roomId)).value;
    final warning = unsettledWarning(
      ref.read(balanceForRoomProvider(roomId)),
      me?.userId,
      l,
    );
    final confirmed = await confirmGroupExit(
      context,
      kind: kind,
      groupName: group?.name ?? l.thisGroup,
      warning: warning,
      onBackup: () async => (await runBackupExport(context, ref)).message,
    );
    if (!confirmed) return;
    final exiter = ref.read(groupExiterProvider.notifier);
    await (kind == GroupExitKind.leave
        ? exiter.leave(roomId)
        : exiter.delete(roomId));
    final error = ref.read(groupExiterProvider).error;
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.failedWithError(error.toString()))),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          kind == GroupExitKind.leave
              ? l.youLeftGroup(group?.name ?? '')
              : l.deletedGroup(group?.name ?? ''),
        ),
      ),
    );
    if (context.mounted) context.go('/groups');
  }

  /// Archives this group on this device (G16) and goes back to the groups
  /// list, where it sits in the collapsed "Archived" section — or brings an
  /// archived one back. Archiving an unsettled group is allowed; the
  /// snackbar says that the open balance still counts in the totals.
  Future<void> _toggleArchive(
    BuildContext context,
    WidgetRef ref, {
    required bool archived,
    required bool unsettled,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    // Captured for the snackbar's undo, which may run after this page is gone.
    final settings = ref.read(settingsDaoProvider);
    final archiver = ref.read(groupArchiverProvider.notifier);
    final name = (await ref.read(groupsDaoProvider).getGroup(roomId))?.name;
    if (archived) {
      await archiver.unarchive(roomId);
    } else {
      await archiver.archive(roomId);
    }
    final error = ref.read(groupArchiverProvider).error;
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.failedWithError(error.toString()))),
      );
      return;
    }
    if (archived) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.groupUnarchived(name ?? ''))),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          unsettled
              ? l.groupArchivedUnsettled(name ?? '')
              : l.groupArchived(name ?? ''),
        ),
        // An action makes snackbars persist by default — this one is a
        // short undo window, not something to dismiss by hand.
        persist: false,
        action: SnackBarAction(
          label: l.undo,
          onPressed: () => settings.unarchiveGroup(roomId),
        ),
      ),
    );
    if (context.mounted) context.go('/groups');
  }

  /// Rename the group / change its default currency (G10).
  Future<void> _editGroup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final group = await ref.read(groupsDaoProvider).getGroup(roomId);
    if (group == null || !context.mounted) return;
    final result = await showEditGroupDialog(
      context,
      name: group.name,
      currency: group.currency,
    );
    if (result == null) return;
    await ref
        .read(groupEditorProvider.notifier)
        .edit(roomId, name: result.name, currency: result.currency);
    final error = ref.read(groupEditorProvider).error;
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.failedWithError(error.toString()))),
      );
    }
  }

  /// G34: a JSON backup of just this group (same format as the full one).
  Future<void> _backupGroup(BuildContext context, WidgetRef ref) async {
    final group = await ref.read(groupsDaoProvider).getGroup(roomId);
    if (group == null || !context.mounted) return;
    await exportGroupBackup(
      context,
      ref,
      groupId: roomId,
      groupName: group.name,
    );
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final groups = ref.read(groupsDaoProvider);
    final members = ref.read(membersDaoProvider);
    final expenses = ref.read(expensesDaoProvider);
    try {
      final group = await groups.getGroup(roomId);
      if (group == null) return;
      final csv = await buildGroupCsvForExport(
        groups,
        members,
        expenses,
        roomId,
      );
      final saved = await saveTextFile(
        csvFileName(group.name),
        csv,
        LedgerFileKind.csv,
      );
      if (saved == null) return; // dialog cancelled
      // G34: the name Android actually used, if the platform tells us.
      final name = kIsWeb
          ? csvFileName(group.name)
          : savedFileDisplayName(saved.path, LedgerFileKind.csv.extension);
      messenger.showSnackBar(
        SnackBar(
          content: Text(name == null ? l.exportedNoName : l.exportedFile(name)),
        ),
      );
    } catch (e) {
      // e.g. the file couldn't be written — tell the user (G15).
      messenger.showSnackBar(
        SnackBar(content: Text(l.exportFailed(e.toString()))),
      );
    }
  }

  /// Lets a just-invited user say which participant they are: pick an existing
  /// (unclaimed) local person → self-claim them, or join as a new participant.
  Future<void> _showClaimPicker(
    BuildContext context,
    WidgetRef ref,
    List<MemberModel> members,
  ) async {
    final unclaimed = members
        .where((m) => m.isActive && m.matrixId == null)
        .toList();
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final choice = await showDialog<MemberModel?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.whichParticipantAreYou),
        children: [
          for (final m in unclaimed)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(m),
              child: Text(m.displayName.isNotEmpty ? m.displayName : m.userId),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(l.imSomeoneNew),
          ),
        ],
      ),
    );
    if (choice != null) {
      await ref
          .read(memberAdderProvider.notifier)
          .selfClaim(roomId, choice.userId);
    } else {
      // "Someone new" — ask for a name, then join as a fresh participant.
      if (!context.mounted) return;
      final name = await _promptName(context);
      if (name == null || name.isEmpty) return;
      await ref.read(memberAdderProvider.notifier).joinAsNew(roomId, name);
    }
    final error = ref.read(memberAdderProvider).error;
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.failedWithError(error.toString()))),
      );
    }
  }

  Future<String?> _promptName(BuildContext context) {
    final l = context.l10n;
    return showTextPrompt(
      context,
      title: l.yourName,
      label: l.nameLabel,
      cancelLabel: l.cancel,
      confirmLabel: l.join,
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ExpenseModel expense,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteExpenseTitle),
        content: Text(l.deleteExpenseBody(expense.description)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(expenseAdderProvider.notifier)
        .deleteExpense(expense.id, roomId);
    final error = ref.read(expenseAdderProvider).error;
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.failedWithError(error.toString()))),
      );
    }
  }

  Future<void> _confirmDeleteSettlement(
    BuildContext context,
    WidgetRef ref,
    SettlementModel settlement,
    String fromName,
    String toName,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final amount = context.money(settlement.amountCents, settlement.currency);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteSettlementTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.deleteSettlementBody(fromName, toName, amount)),
            // G6: who recorded (and last changed) this payment.
            const SizedBox(height: Insets.m),
            RecordAttribution(
              groupId: roomId,
              kind: RecordKind.settlement,
              recordId: settlement.id,
              origin: settlement.origin,
              sig: settlement.sig,
              createdAt: settlement.createdAt,
              updatedAt: settlement.updatedAt,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(expenseAdderProvider.notifier)
        .deleteSettlement(settlement.id, roomId);
    final error = ref.read(expenseAdderProvider).error;
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.failedWithError(error.toString()))),
      );
    }
  }
}

/// App-bar indicator. **Error** (tappable) when background sync has failed
/// repeatedly (`SyncHealth.failing`) — opens a sheet with the last error / last
/// sync and a manual retry. Otherwise a filled cloud once every active peer has
/// acknowledged the group's latest record, or an outlined cloud (with the first
/// waiting peer in the tooltip) while replication is still pending.
class _SyncStatusIcon extends ConsumerWidget {
  final GroupSyncStatus status;
  const _SyncStatusIcon({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(syncHealthProvider);
    final l = context.l10n;
    if (health.failing) {
      return IconButton(
        icon: Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.error),
        tooltip: l.syncProblemTooltip,
        onPressed: () => _showHealthSheet(context, ref, health),
      );
    }
    if (status.synced) {
      return IconButton(
        icon: const Icon(Icons.cloud_done_outlined),
        tooltip: l.syncedWithAll,
        onPressed: null,
      );
    }
    // A pending peer with no logged-in device (G24) or no verified one
    // (G11, verified-only sync) isn't a sync error — say so instead of
    // "waiting" forever.
    final hint = pendingPeerHint(status.pendingPeers, health);
    return IconButton(
      icon: const Icon(Icons.cloud_queue),
      tooltip: switch (hint.reason) {
        PendingReason.unverified => l.peerHasNoVerifiedDevice(hint.peer),
        PendingReason.noDevice => l.peerHasNoDevice(hint.peer),
        PendingReason.waiting => l.waitingForPeer(hint.peer),
      },
      onPressed: null,
    );
  }

  void _showHealthSheet(
    BuildContext context,
    WidgetRef ref,
    SyncHealthState health,
  ) {
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.syncProblemTitle,
                style: Theme.of(sheetCtx).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(l.syncProblemBody),
              const SizedBox(height: 12),
              if (health.lastSuccessAt != null)
                Text(
                  l.lastSynced(_ago(l, health.lastSuccessAt!)),
                  style: Theme.of(sheetCtx).textTheme.bodySmall,
                ),
              if (health.lastError != null)
                Text(
                  l.lastError(health.lastError.toString()),
                  style: Theme.of(sheetCtx).textTheme.bodySmall,
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  ref.read(syncEngineProvider).broadcastDigests();
                  Navigator.pop(sheetCtx);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l.retryingSync)));
                },
                icon: const Icon(Icons.refresh),
                label: Text(l.retryNow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A coarse "x ago" for the last-synced line (minutes / hours / days).
String _ago(AppLocalizations l, int msEpoch) {
  final d = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(msEpoch),
  );
  if (d.inMinutes < 1) return l.agoJustNow;
  if (d.inHours < 1) return l.agoMinutes(d.inMinutes);
  if (d.inDays < 1) return l.agoHours(d.inHours);
  return l.agoDays(d.inDays);
}

/// The app-bar search field (G16) — owns its controller; follows the
/// provider when the filter is cleared from elsewhere.
class _SearchField extends ConsumerStatefulWidget {
  final String roomId;
  const _SearchField({required this.roomId});

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: ref.read(ledgerSearchProvider(widget.roomId))?.query ?? '',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ledgerSearchProvider(widget.roomId), (_, next) {
      final q = next?.query ?? '';
      if (q != _ctrl.text) _ctrl.text = q;
    });
    return TextField(
      key: const Key('searchField'),
      controller: _ctrl,
      autofocus: true,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: context.l10n.searchHint,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
      ),
      onChanged: (q) =>
          ref.read(ledgerSearchProvider(widget.roomId).notifier).setQuery(q),
    );
  }
}

/// Filter chips below the app bar while searching (G16): "Involving me" and
/// the categories this group uses.
class _FilterBar extends ConsumerWidget {
  final String roomId;
  final LedgerFilter filter;
  final List<ExpenseCategory> categories;
  final bool canFilterMe;
  const _FilterBar({
    required this.roomId,
    required this.filter,
    required this.categories,
    required this.canFilterMe,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final search = ref.read(ledgerSearchProvider(roomId).notifier);
    return SingleChildScrollView(
      key: const Key('filterBar'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        Insets.page,
        Insets.xs,
        Insets.page,
        Insets.xs,
      ),
      child: Row(
        children: [
          if (canFilterMe)
            Padding(
              padding: const EdgeInsets.only(right: Insets.s),
              child: FilterChip(
                key: const Key('filterInvolvingMe'),
                avatar: const Icon(Icons.person_outline, size: 18),
                label: Text(l.filterInvolvingMe),
                selected: filter.involvingMe,
                showCheckmark: false,
                onSelected: (_) => search.toggleInvolvingMe(),
              ),
            ),
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(right: Insets.s),
              child: FilterChip(
                key: Key('filterCategory-${c.wire}'),
                avatar: Icon(c.icon, size: 18),
                label: Text(c.label(l)),
                selected: filter.categories.contains(c),
                showCheckmark: false,
                onSelected: (_) => search.toggleCategory(c),
              ),
            ),
        ],
      ),
    );
  }
}

/// A date section header in the ledger list (G17).
class _DayHeader extends StatelessWidget {
  final String text;
  const _DayHeader({required this.text});

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
        key: const Key('dayHeader'),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The group's header card (G17): my balance in this group and the two
/// money actions — *Settle up* (record a payment, prefilled with what I owe
/// or am owed) and *Balances* (everyone's balances + suggested payments).
class _GroupSummaryCard extends StatelessWidget {
  final GroupOverview overview;
  final bool readOnly;
  final bool busy;
  final VoidCallback onSettleUp;
  final VoidCallback onBalances;
  const _GroupSummaryCard({
    required this.overview,
    required this.readOnly,
    required this.busy,
    required this.onSettleUp,
    required this.onBalances,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Tighter than the default so "Begleichen" fits two-up on a phone.
    final compact = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: Insets.m),
    );
    return Card(
      key: const Key('groupSummaryCard'),
      color: scheme.primaryContainer.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.l),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Insets.l + Insets.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.yourBalance,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: Insets.xs),
            BalanceSummaryText(
              overview: overview,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: Insets.l),
            Row(
              children: [
                if (!readOnly) ...[
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('settleUpButton'),
                      style: compact,
                      onPressed: busy ? null : onSettleUp,
                      icon: const Icon(Icons.payments_outlined, size: 20),
                      label: Text(
                        l.settleUp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: Insets.m),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('balancesButton'),
                    onPressed: onBalances,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: Insets.m),
                      backgroundColor: AppTheme.cardColor(scheme),
                    ),
                    icon: const Icon(Icons.balance, size: 20),
                    label: Text(
                      l.balancesButton,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The square icon tile at the start of a ledger row.
class _LeadingTile extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;
  const _LeadingTile({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(Radii.m),
    ),
    child: Icon(icon, color: foreground, size: 22),
  );
}

/// Shared row layout for expenses and settlements (G33): icon tile, then two
/// independent lines — *title … amount* and *subtitle … note* (payer and
/// "you lent / you borrowed") — so a long localized note never squeezes the
/// title; everything ellipsizes to one line. Then an options menu.
class _LedgerRow extends StatelessWidget {
  final Widget leading;

  /// The title line's text widget (ellipsizing — a [Text] or a [NamesLine]).
  final Widget title;
  final String subtitle;
  final String amount;
  final Widget? amountNote;
  final bool pending;

  /// G6: a signature problem (key conflict / someone posing as us).
  final bool attention;
  final String menuTooltip;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  /// G16: the expense has a note — a small icon after the title.
  final bool hasNote;
  const _LedgerRow({
    this.hasNote = false,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.menuTooltip,
    this.amountNote,
    this.pending = false,
    this.attention = false,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Insets.l,
          Insets.m,
          onDelete == null ? Insets.l : 0,
          Insets.m,
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: Insets.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    // G18 review 2: a payment's title may wrap onto a second
                    // line — the amount stays on the first.
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: DefaultTextStyle.merge(
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                child: title,
                              ),
                            ),
                            if (hasNote)
                              Padding(
                                padding: const EdgeInsets.only(left: Insets.xs),
                                child: Tooltip(
                                  message: l.expenseHasNote,
                                  child: Icon(
                                    Icons.notes,
                                    key: const Key('expenseNoteIcon'),
                                    size: 16,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            if (attention)
                              Padding(
                                padding: const EdgeInsets.only(left: Insets.xs),
                                child: Tooltip(
                                  message: l.recordSignatureWarning,
                                  child: Icon(
                                    Icons.gpp_maybe_outlined,
                                    key: const Key('recordAttention'),
                                    size: 16,
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Insets.s),
                      if (pending)
                        Padding(
                          padding: const EdgeInsets.only(right: Insets.xs),
                          child: Icon(
                            Icons.cloud_queue,
                            size: 16,
                            color: scheme.outline,
                          ),
                        ),
                      Text(
                        amount,
                        key: const Key('ledgerRowAmount'),
                        maxLines: 1,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  LayoutBuilder(
                    builder: (context, c) => Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (amountNote != null) ...[
                          const SizedBox(width: Insets.s),
                          // The note keeps its natural width (it's what the
                          // row is about for me), capped so the payer always
                          // keeps some room.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: c.maxWidth * 0.7,
                            ),
                            child: DefaultTextStyle.merge(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              child: amountNote!,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              PopupMenuButton<String>(
                tooltip: menuTooltip,
                icon: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                padding: EdgeInsets.zero,
                onSelected: (action) {
                  if (action == 'delete') onDelete!();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'delete', child: Text(l.delete)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final ExpenseModel expense;
  final String payerLine;

  /// What this expense means for me — null when I'm not a participant.
  final ({int net, bool involved})? effect;
  final bool pending;
  final bool attention;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  const _ExpenseTile({
    required this.expense,
    required this.payerLine,
    required this.effect,
    required this.pending,
    this.attention = false,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.ledgerColors;
    final effect = this.effect;
    Widget? note;
    if (effect != null) {
      final small = theme.textTheme.labelMedium?.copyWith(
        fontFeatures: kTabularFigures,
      );
      final (text, color) = !effect.involved
          ? (l.notInvolved, scheme.onSurfaceVariant)
          : effect.net > 0
          ? (
              l.youLentAmount(context.money(effect.net, expense.currency)),
              colors.positive,
            )
          : effect.net < 0
          ? (
              l.youBorrowedAmount(context.money(-effect.net, expense.currency)),
              colors.negative,
            )
          : (l.settledUp, scheme.onSurfaceVariant);
      note = Text(
        text,
        key: const Key('expenseEffect'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: small?.copyWith(color: color),
      );
    }
    return _LedgerRow(
      // G16: the category's icon (generic receipt without one).
      leading: CategoryIconTile(
        key: Key('categoryTile-${expense.category ?? 'none'}'),
        category: ExpenseCategory.fromWire(expense.category),
      ),
      title: Text(expense.description, key: const Key('expenseTitle')),
      hasNote: expense.note != null,
      subtitle: payerLine,
      amount: context.money(expense.amountCents, expense.currency),
      amountNote: note,
      pending: pending,
      attention: attention,
      menuTooltip: l.expenseOptions,
      onTap: onTap,
      onDelete: onDelete,
    );
  }
}

/// A recorded payment between two participants ("Alex paid Sam") — visually
/// distinct (handshake on green). No edit — a wrong settlement is deleted
/// (tombstoned) and re-recorded from the balance page.
class _SettlementTile extends StatelessWidget {
  final SettlementModel settlement;
  final Widget title;
  final bool pending;
  final bool attention;
  final VoidCallback? onDelete;
  const _SettlementTile({
    required this.settlement,
    required this.title,
    required this.pending,
    this.attention = false,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = context.ledgerColors;
    return _LedgerRow(
      leading: _LeadingTile(
        icon: Icons.handshake_outlined,
        background: colors.positiveContainer,
        foreground: colors.onPositiveContainer,
      ),
      title: title,
      subtitle: l.paymentLabel,
      amount: context.money(settlement.amountCents, settlement.currency),
      pending: pending,
      attention: attention,
      menuTooltip: l.settlementOptions,
      onDelete: onDelete,
    );
  }
}
