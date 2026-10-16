import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/l10n.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_health.dart';
import '../../core/sync/sync_status_provider.dart';
import '../../models/expense_model.dart';
import '../../models/member_model.dart';
import '../backup/csv_export.dart';
import '../backup/csv_files.dart';
import '../balance/balance_provider.dart';
import '../groups/group_edit_dialog.dart';
import '../groups/group_exit_dialog.dart';
import '../groups/group_provider.dart';
import 'expenses_provider.dart';
import 'ledger_syncer.dart';

enum _GroupMenuAction { addMember, edit, export, exit }

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
    // Invited but not yet linked to anyone in this group → offer self-claim.
    final needsClaim = meAsync.hasValue &&
        meAsync.value == null &&
        members.any((m) => m.isActive);
    // G26: another member removed us — the group stays as read-only history
    // (peers would reject our writes anyway) until we delete it here.
    final removed = meAsync.value != null && !meAsync.value!.isActive;
    final canEdit = meAsync.value?.isActive ?? false;
    final adderState = ref.watch(memberAdderProvider);
    // Keep the (auto-dispose) expense notifier alive while this page can
    // trigger deletes — a bare `read` in the dialog callback would let it be
    // disposed mid-delete.
    ref.watch(expenseAdderProvider);
    // Same for the leave/delete (G9) and edit-group (G10) notifiers.
    ref.watch(groupExiterProvider);
    ref.watch(groupEditorProvider);
    final exitKind =
        groupExitKind(members, ref.watch(currentUserIdProvider));
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.expensesTitle),
        actions: [
          _SyncStatusIcon(status: syncStatus),
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: l.membersTitle,
            onPressed: () => context.push('/groups/$roomId/members'),
          ),
          IconButton(
            icon: const Icon(Icons.balance),
            tooltip: l.balanceTitle,
            onPressed: () => context.push('/groups/$roomId/balance'),
          ),
          // Less frequent group actions live in an overflow menu so the app
          // bar stays uncluttered on phones (and the title isn't truncated —
          // G12, "Ausgaben").
          PopupMenuButton<_GroupMenuAction>(
            tooltip: l.moreTooltip,
            onSelected: (action) => switch (action) {
              _GroupMenuAction.addMember => _showAddMemberDialog(context, ref),
              _GroupMenuAction.edit => _editGroup(context, ref),
              _GroupMenuAction.export => _exportCsv(context, ref),
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
                value: _GroupMenuAction.export,
                child: ListTile(
                  leading: const Icon(Icons.save_alt),
                  title: Text(l.exportCsv),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _GroupMenuAction.exit,
                child: ListTile(
                  leading: Icon(exitKind == GroupExitKind.leave
                      ? Icons.logout
                      : Icons.delete_outline),
                  title: Text(exitKind == GroupExitKind.leave
                      ? l.leaveGroup
                      : l.deleteGroup),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: removed
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
          _ledgerList(context, ref, expensesAsync, settlementsAsync, names,
              syncStatus, readOnly: removed),
          if (adderState.isLoading)
            const ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator()),
            ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Expenses and settlements merged into one newest-first list. Both DAO
  /// streams already drop tombstones, so deleted records never show.
  Widget _ledgerList(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<ExpenseModel>> expensesAsync,
    AsyncValue<List<SettlementModel>> settlementsAsync,
    Map<String, String> names,
    GroupSyncStatus syncStatus, {
    required bool readOnly,
  }) {
    final l = context.l10n;
    if (expensesAsync.hasError) {
      return Center(
          child: Text(l.errorWithDetail(expensesAsync.error.toString())));
    }
    if (settlementsAsync.hasError) {
      return Center(
          child: Text(l.errorWithDetail(settlementsAsync.error.toString())));
    }
    if (!expensesAsync.hasValue || !settlementsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final entries = <({int createdAt, Object record})>[
      for (final e in expensesAsync.value!) (createdAt: e.createdAt, record: e),
      for (final s in settlementsAsync.value!)
        (createdAt: s.createdAt, record: s),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (entries.isEmpty) {
      return Center(child: Text(l.noExpensesYet));
    }
    String nameOf(String id) => names[id] ?? id;
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final record = entries[i].record;
        if (record is SettlementModel) {
          final from = nameOf(record.fromUser);
          final to = nameOf(record.toUser);
          return _SettlementTile(
            settlement: record,
            fromName: from,
            toName: to,
            pending: syncStatus.isRecordPending(record.updatedAt),
            onDelete: readOnly
                ? null
                : () => _confirmDeleteSettlement(context, ref, record, from, to),
          );
        }
        final expense = record as ExpenseModel;
        return _ExpenseTile(
          expense: expense,
          paidByName: nameOf(expense.paidBy),
          pending: syncStatus.isRecordPending(expense.updatedAt),
          onTap: readOnly
              ? null
              : () => context.push('/groups/$roomId/expenses/edit',
                  extra: expense),
          onDelete: readOnly ? null : () => _confirmDelete(context, ref, expense),
        );
      },
    );
  }

  /// Leave / delete this group (G9) after a confirmation that warns about an
  /// unsettled balance; then back to the groups list.
  Future<void> _exitGroup(
      BuildContext context, WidgetRef ref, GroupExitKind kind) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final group = await ref.read(groupsDaoProvider).getGroup(roomId);
    if (!context.mounted) return;
    final me = ref.read(currentParticipantProvider(roomId)).value;
    final warning = unsettledWarning(
        ref.read(balanceForRoomProvider(roomId)), me?.userId, l);
    final confirmed = await confirmGroupExit(
      context,
      kind: kind,
      groupName: group?.name ?? l.thisGroup,
      warning: warning,
      onExport: () => _exportCsv(context, ref),
    );
    if (!confirmed) return;
    final exiter = ref.read(groupExiterProvider.notifier);
    await (kind == GroupExitKind.leave
        ? exiter.leave(roomId)
        : exiter.delete(roomId));
    final error = ref.read(groupExiterProvider).error;
    if (error != null) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.failedWithError(error.toString()))));
      return;
    }
    messenger.showSnackBar(SnackBar(
        content: Text(kind == GroupExitKind.leave
            ? l.youLeftGroup(group?.name ?? '')
            : l.deletedGroup(group?.name ?? ''))));
    if (context.mounted) context.go('/groups');
  }

  /// Rename the group / change its default currency (G10).
  Future<void> _editGroup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final group = await ref.read(groupsDaoProvider).getGroup(roomId);
    if (group == null || !context.mounted) return;
    final result = await showEditGroupDialog(context,
        name: group.name, currency: group.currency);
    if (result == null) return;
    await ref
        .read(groupEditorProvider.notifier)
        .edit(roomId, name: result.name, currency: result.currency);
    final error = ref.read(groupEditorProvider).error;
    if (error != null) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.failedWithError(error.toString()))));
    }
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final group = await ref.read(groupsDaoProvider).getGroup(roomId);
    if (group == null) return;
    final csv = await buildGroupCsvForExport(
      ref.read(groupsDaoProvider),
      ref.read(membersDaoProvider),
      ref.read(expensesDaoProvider),
      roomId,
    );
    await saveCsvFile(csvFileName(group.name), csv);
    messenger.showSnackBar(
        SnackBar(content: Text(l.exportedFile(csvFileName(group.name)))));
  }

  /// Lets a just-invited user say which participant they are: pick an existing
  /// (unclaimed) local person → self-claim them, or join as a new participant.
  Future<void> _showClaimPicker(
      BuildContext context, WidgetRef ref, List<MemberModel> members) async {
    final unclaimed =
        members.where((m) => m.isActive && m.matrixId == null).toList();
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
          SnackBar(content: Text(l.failedWithError(error.toString()))));
    }
  }

  Future<String?> _promptName(BuildContext context) {
    final ctrl = TextEditingController();
    final l = context.l10n;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.yourName),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: l.nameLabel),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: Text(l.join)),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ExpenseModel expense) async {
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
          SnackBar(content: Text(l.failedWithError(error.toString()))));
    }
  }

  Future<void> _confirmDeleteSettlement(BuildContext context, WidgetRef ref,
      SettlementModel settlement, String fromName, String toName) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final amount = context.money(settlement.amountCents, settlement.currency);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteSettlementTitle),
        content: Text(l.deleteSettlementBody(fromName, toName, amount)),
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
          SnackBar(content: Text(l.failedWithError(error.toString()))));
    }
  }

  Future<void> _showAddMemberDialog(
      BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;

    final userId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.addMember),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: l.matrixIdLabel,
            hintText: '@user:matrix.org',
          ),
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () {
              final id = ctrl.text.trim();
              if (id.startsWith('@') && id.contains(':')) {
                Navigator.of(ctx).pop(id);
              }
            },
            child: Text(l.add),
          ),
        ],
      ),
    );

    ctrl.dispose();
    if (userId == null) return;

    await ref.read(memberAdderProvider.notifier).add(roomId, userId);

    final error = ref.read(memberAdderProvider).error;
    messenger.showSnackBar(SnackBar(
        content: Text(error != null
            ? l.failedWithError(error.toString())
            : l.addedMember(userId))));
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
    // A pending peer with no logged-in device isn't a sync error — say so
    // instead of "waiting" forever (G24).
    final noDevice =
        status.pendingPeers.where(health.unreachablePeers.contains).firstOrNull;
    final waitingFor = noDevice ?? status.pendingPeers.first;
    return IconButton(
      icon: const Icon(Icons.cloud_queue),
      tooltip: noDevice != null
          ? l.peerHasNoDevice(noDevice)
          : l.waitingForPeer(waitingFor),
      onPressed: null,
    );
  }

  void _showHealthSheet(
      BuildContext context, WidgetRef ref, SyncHealthState health) {
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
              Text(l.syncProblemTitle,
                  style: Theme.of(sheetCtx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(l.syncProblemBody),
              const SizedBox(height: 12),
              if (health.lastSuccessAt != null)
                Text(l.lastSynced(_ago(l, health.lastSuccessAt!)),
                    style: Theme.of(sheetCtx).textTheme.bodySmall),
              if (health.lastError != null)
                Text(l.lastError(health.lastError.toString()),
                    style: Theme.of(sheetCtx).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  ref.read(syncEngineProvider).broadcastDigests();
                  Navigator.pop(sheetCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.retryingSync)));
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
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(msEpoch));
  if (d.inMinutes < 1) return l.agoJustNow;
  if (d.inHours < 1) return l.agoMinutes(d.inMinutes);
  if (d.inDays < 1) return l.agoHours(d.inHours);
  return l.agoDays(d.inDays);
}

class _ExpenseTile extends StatelessWidget {
  final ExpenseModel expense;
  final String paidByName;
  final bool pending;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  const _ExpenseTile(
      {required this.expense,
      required this.paidByName,
      required this.pending,
      this.onTap,
      this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final amount = context.money(expense.amountCents, expense.currency);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.receipt)),
      title: Text(expense.description),
      subtitle: Text(l.paidByName(paidByName)),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.cloud_queue,
                size: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          Text(
            amount,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (onDelete != null)
          PopupMenuButton<String>(
            tooltip: l.expenseOptions,
            onSelected: (action) {
              if (action == 'delete') onDelete!();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'delete', child: Text(l.delete)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A recorded payment between two participants ("Alex paid Sam"). No edit —
/// a wrong settlement is deleted (tombstoned) and re-recorded from the balance
/// page.
class _SettlementTile extends StatelessWidget {
  final SettlementModel settlement;
  final String fromName;
  final String toName;
  final bool pending;
  final VoidCallback? onDelete;
  const _SettlementTile({
    required this.settlement,
    required this.fromName,
    required this.toName,
    required this.pending,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final amount = context.money(settlement.amountCents, settlement.currency);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.handshake_outlined)),
      title: Text(l.settlementTitle(fromName, toName)),
      subtitle: Text(l.settlementSubtitle(context.date(settlement.createdAt))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.cloud_queue,
                size: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          Text(
            amount,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (onDelete != null)
          PopupMenuButton<String>(
            tooltip: l.settlementOptions,
            onSelected: (action) {
              if (action == 'delete') onDelete!();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'delete', child: Text(l.delete)),
            ],
          ),
        ],
      ),
    );
  }
}
