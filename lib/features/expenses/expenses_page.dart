import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/session/app_session.dart';
import '../../core/l10n/l10n.dart';
import '../../core/widgets/text_prompt_dialog.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_health.dart';
import '../../core/sync/sync_status_provider.dart';
import '../../models/expense_category.dart';
import '../../models/expense_date.dart';
import '../../models/expense_model.dart';
import '../../models/member_model.dart';
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
import '../groups/group_actions.dart';
import '../groups/group_settings_page.dart' show groupSettingsLocation;
import '../groups/group_archive_provider.dart';
import '../groups/group_provider.dart';
import 'expense_category_ui.dart';
import 'expense_filter.dart';
import 'expenses_provider.dart';
import 'ledger_search_provider.dart';
import 'ledger_syncer.dart';
import '../../models/record_signature.dart';
import 'record_attribution.dart';
import 'record_actions.dart';
import 'record_details_sheet.dart';
import '../../core/widgets/action_error.dart';

/// G65 (U22): the group ⋮ menu — the frequent actions only (G52 adds
/// *Invite* here); the rest is on the group settings page.
enum _GroupMenuAction { addMember, archive, settings }

/// G56: groups whose "just you so far" card was dismissed — for this app
/// session only (it comes back on the next start while still true).
final addPeopleHintDismissedProvider =
    NotifierProvider<AddPeopleHintDismissed, Set<String>>(
      AddPeopleHintDismissed.new,
    );

class AddPeopleHintDismissed extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void dismiss(String groupId) => state = {...state, groupId};
}

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
    // Same for the leave/delete (G9, removed banner) and archive notifiers.
    ref.watch(groupExiterProvider);
    ref.watch(groupArchiverProvider);
    // G16: search / filter (null = search bar closed) and the device-local
    // archive.
    final search = ref.watch(ledgerSearchProvider(roomId));
    final archived = ref.watch(groupArchivedProvider(roomId));
    final l = context.l10n;
    final theme = Theme.of(context);
    final activeCount = members.where((m) => m.isActive).length;

    return Scaffold(
      appBar: AppBar(
        // G17: the group's name (not just "Expenses"), members as subtitle;
        // G16: the search field while searching.
        title: search != null
            ? _SearchField(roomId: roomId)
            // G65: tapping the title opens the group settings (as in
            // messengers); the ⋮ menu has the same entry.
            : Semantics(
                button: true,
                hint: l.groupSettingsTitle,
                child: InkWell(
                  key: const Key('groupTitleButton'),
                  borderRadius: BorderRadius.circular(Radii.s),
                  onTap: () => context.push(groupSettingsLocation(roomId)),
                  child: Column(
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
                ),
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
                // G65 (U22): only the frequent group actions stay in the
                // overflow menu; everything else lives on the group settings
                // page (also reached by tapping the title).
                PopupMenuButton<_GroupMenuAction>(
                  key: const Key('groupMenu'),
                  tooltip: l.moreTooltip,
                  onSelected: (action) => switch (action) {
                    _GroupMenuAction.addMember => showAddPersonDialog(
                      context,
                      ref,
                      roomId,
                    ),
                    _GroupMenuAction.archive => toggleGroupArchive(
                      context,
                      ref,
                      roomId,
                      archived: archived,
                      unsettled: overview.myBalance.isNotEmpty,
                    ),
                    _GroupMenuAction.settings => context.push(
                      groupSettingsLocation(roomId),
                    ),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _GroupMenuAction.addMember,
                      enabled: !adderState.isLoading && !removed,
                      child: ListTile(
                        key: const Key('addPersonMenuItem'),
                        leading: const Icon(Icons.person_add_outlined),
                        title: Text(l.addMember),
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
                      value: _GroupMenuAction.settings,
                      child: ListTile(
                        key: const Key('groupSettingsMenuItem'),
                        leading: const Icon(Icons.tune),
                        title: Text(l.groupSettingsTitle),
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
              key: const Key('removedBanner'),
              // G67: at 360 dp an inline action squeezed the text into a
              // sliver (overflow) — the action goes below.
              forceActionsBelow: true,
              content: Text(l.removedFromGroupBanner),
              leading: const Icon(Icons.person_off_outlined),
              actions: [
                TextButton(
                  onPressed: () =>
                      exitGroupFlow(context, ref, roomId, GroupExitKind.delete),
                  child: Text(l.deleteFromThisDevice),
                ),
              ],
            ),
          if (archived && search == null)
            MaterialBanner(
              key: const Key('archivedBanner'),
              forceActionsBelow: true,
              content: Text(l.archivedBanner),
              leading: const Icon(Icons.archive_outlined),
              actions: [
                TextButton(
                  onPressed: () => toggleGroupArchive(
                    context,
                    ref,
                    roomId,
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
                  group?.categories ?? const [],
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
                  // G46: I'm the group's only active participant.
                  onlyMe: canEdit && activeCount <= 1,
                  filter: search,
                  customCategories: group?.categories ?? const [],
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
    bool onlyMe = false,
    LedgerFilter? filter,
    List<CustomCategory> customCategories = const [],
  }) {
    final l = context.l10n;
    final loadError = expensesAsync.error ?? settlementsAsync.error;
    if (loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.page),
          child: ActionErrorView(error: loadError, what: l.loadFailedTitle),
        ),
      );
    }
    if (!expensesAsync.hasValue || !settlementsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    // G16: the search bar's filter (names as shown: "you" for me).
    String searchName(String id) =>
        id == myId ? l.you : (names[id] ?? localpartOf(id));
    final f = filter ?? LedgerFilter.none;
    // G49: an expense sits under its display day (`date ?? created_at`), so
    // a back-dated one lands on the day it happened (G60: payments too);
    // newest day first, and within a day newest-created first.
    final entries =
        <({int day, int createdAt, Object record})>[
          for (final e in expensesAsync.value!)
            if (!f.isActive ||
                expenseMatches(
                  e,
                  f,
                  nameOf: searchName,
                  myId: myId,
                  customCategories: customCategories,
                ))
              (
                day: e.displayDay.millisecondsSinceEpoch,
                createdAt: e.createdAt,
                record: e,
              ),
          for (final s in settlementsAsync.value!)
            if (!f.isActive ||
                settlementMatches(
                  s,
                  f,
                  nameOf: searchName,
                  myId: myId,
                  paymentLabel: l.paymentLabel,
                ))
              (
                day: s.displayDay.millisecondsSinceEpoch,
                createdAt: s.createdAt,
                record: s,
              ),
        ]..sort((a, b) {
          final byDay = b.day.compareTo(a.day);
          return byDay != 0 ? byDay : b.createdAt.compareTo(a.createdAt);
        });
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
      // G46: a fresh group with only me in it — adding people comes first.
      final invitePeople = !readOnly && onlyMe;
      return EmptyState(
        key: const Key('expensesEmpty'),
        icon: invitePeople
            ? Icons.group_add_outlined
            : Icons.receipt_long_outlined,
        title: l.expensesEmptyTitle,
        body: readOnly
            ? null
            : invitePeople
            ? l.expensesEmptyAloneBody
            : l.expensesEmptyBody,
        actions: [
          if (invitePeople)
            FilledButton.icon(
              key: const Key('emptyAddPeople'),
              onPressed: () => showAddPersonDialog(context, ref, roomId),
              icon: const Icon(Icons.person_add_outlined),
              label: Text(l.addPeople),
            ),
        ],
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
          // G60: tap (or ⋮ → Edit) edits the payment; read-only: neither.
          // G67 (U15): read-only → a details sheet to look at it.
          onTap: readOnly
              ? () => showSettlementDetails(context, record, from: from, to: to)
              : () => editPaymentFlow(context, ref, roomId, record),
          onEdit: readOnly
              ? null
              : () => editPaymentFlow(context, ref, roomId, record),
          onDelete: readOnly
              ? null
              : () => deleteSettlementFlow(
                  context,
                  ref,
                  record,
                  fromName: from,
                  toName: to,
                ),
        );
      }
      final expense = record as ExpenseModel;
      return _ExpenseTile(
        expense: expense,
        category: resolveCategory(expense.category, customCategories),
        payerLine: expense.paidBy == myId
            ? l.youPaid
            : l.paidByName(nameOf(expense.paidBy)),
        effect: myId == null ? null : expenseEffectFor(expense, myId),
        pending: syncStatus.isRecordPending(expense.updatedAt),
        attention: attention(expense.origin, expense.sig),
        // G67 (U15): read-only → a details sheet to look at it.
        onTap: readOnly
            ? () => showExpenseDetails(
                context,
                expense,
                names: names,
                category: resolveCategory(expense.category, customCategories),
              )
            : () =>
                  context.push('/groups/$roomId/expenses/edit', extra: expense),
        onDelete: readOnly
            ? null
            : () => deleteExpenseFlow(context, ref, expense),
      );
    }

    // Day sections, newest first.
    final sections = <({int day, List<Object> records})>[];
    for (final e in entries) {
      final day = e.day;
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
        // G56: only me, but there are already expenses — the empty state's
        // "Add people" no longer shows, so offer it above the ledger.
        if (filter == null &&
            !readOnly &&
            onlyMe &&
            !ref.watch(addPeopleHintDismissedProvider).contains(roomId))
          ContentWidth(child: _AddPeopleCard(roomId: roomId)),
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
    final errors = ActionErrors.of(context);
    final l = context.l10n;
    // G46: `null` = dismissed (barrier tap / back) → nothing happens;
    // `(member: null)` = "I'm someone new".
    final choice = await showDialog<({MemberModel? member})>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.whichParticipantAreYou),
        children: [
          for (final m in unclaimed)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop((member: m)),
              child: Text(m.displayName.isNotEmpty ? m.displayName : m.userId),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop((member: null)),
            child: Text(l.imSomeoneNew),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final picked = choice.member;
    if (picked != null) {
      await ref
          .read(memberAdderProvider.notifier)
          .selfClaim(roomId, picked.userId);
    } else {
      // "Someone new" — ask for a name, then join as a fresh participant.
      if (!context.mounted) return;
      final name = await _promptName(context);
      if (name == null || name.isEmpty) return;
      await ref.read(memberAdderProvider.notifier).joinAsNew(roomId, name);
    }
    final error = ref.read(memberAdderProvider).error;
    if (error != null) errors.show(error);
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
  final List<ResolvedCategory> categories;
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
                key: Key('filterCategory-${c.key}'),
                avatar: Icon(c.icon, size: 18),
                label: Text(c.label(l)),
                selected: filter.categories.contains(c.key),
                showCheckmark: false,
                onSelected: (_) => search.toggleCategory(c.key),
              ),
            ),
        ],
      ),
    );
  }
}

/// G56: a subtle card above a ledger where I'm the only active member —
/// same action as the empty state's CTA, dismissible for the session.
class _AddPeopleCard extends ConsumerWidget {
  final String roomId;
  const _AddPeopleCard({required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Insets.m),
      child: Card(
        key: const Key('addPeopleCard'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.l,
            Insets.xs,
            Insets.xs,
            Insets.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: Insets.m),
                child: Icon(
                  Icons.group_add_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Insets.m),
              // Text above the action, so a long (German) label never
              // squeezes the row at phone width.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: Insets.m),
                      child: Text(
                        l.addPeopleHint,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('cardAddPeople'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Insets.s,
                        ),
                      ),
                      onPressed: () =>
                          showAddPersonDialog(context, ref, roomId),
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: Text(l.addPeople),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('dismissAddPeople'),
                tooltip: l.dismiss,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => ref
                    .read(addPeopleHintDismissedProvider.notifier)
                    .dismiss(roomId),
              ),
            ],
          ),
        ),
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
    // "Paper & ink" (G42): no card — a ledger rule above, a hairline below.
    return Container(
      key: const Key('groupSummaryCard'),
      decoration: BoxDecoration(
        border: Border(
          top: AppTheme.ledgerRule(scheme),
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.yourBalance.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: Insets.xs),
            BalanceSummaryText(
              overview: overview,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: Insets.l),
            Row(
              children: [
                if (!readOnly) ...[
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('settleUpButton'),
                      // The one accent: rust.
                      style: compact.merge(
                        FilledButton.styleFrom(
                          backgroundColor: scheme.secondary,
                          foregroundColor: scheme.onSecondary,
                        ),
                      ),
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

  /// G60: an *Edit* entry in the options menu (payments).
  final VoidCallback? onEdit;

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
    this.onEdit,
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
                  if (action == 'edit') onEdit?.call();
                  if (action == 'delete') onDelete!();
                },
                itemBuilder: (_) => [
                  if (onEdit != null)
                    PopupMenuItem(value: 'edit', child: Text(l.edit)),
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

  /// The expense's category as shown (G47: custom ones resolved).
  final ResolvedCategory? category;
  final String payerLine;

  /// What this expense means for me — null when I'm not a participant.
  final ({int net, bool involved})? effect;
  final bool pending;
  final bool attention;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  const _ExpenseTile({
    required this.expense,
    required this.category,
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
        category: category,
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
/// distinct (handshake on green). G60: tapping it (or ⋮ → *Edit*) edits
/// the payment; ⋮ → *Delete* tombstones it.
class _SettlementTile extends StatelessWidget {
  final SettlementModel settlement;
  final Widget title;
  final bool pending;
  final bool attention;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _SettlementTile({
    required this.settlement,
    required this.title,
    required this.pending,
    this.attention = false,
    this.onTap,
    this.onEdit,
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
      onTap: onTap,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }
}
