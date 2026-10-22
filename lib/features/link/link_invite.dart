/// G52 step 6: *Invite with a link* — the invite sheet (QR code, share,
/// copy, "anyone with this link …"), the first-use disclosure and the flow
/// that opens a group's link channel on its first invite
/// (`docs/design/no-login-sharing.md` §2, §8.4, §9.2, §14 Q9).
///
/// **Which groups get the entry** ([linkInviteStateOf]):
/// * a group that already has a link channel on this device → the sheet
///   (also on a Matrix account: a group created with *Share with an invite
///   link*, or adopted from local mode);
/// * in **local mode** a group [openLinkChannel] accepts (unsigned meta, no
///   other Matrix account claims a participant) → disclosure (first use) →
///   `LinkSyncEngine.openChannel` → the sheet;
/// * G53: a **Matrix group** this account is an active participant of →
///   a confirmation (it becomes a mixed group: shared by link too, the
///   Matrix members' devices bridge, link changes aren't verified) →
///   `mixedLinkOpenerProvider` (a signed meta with `link`) → the sheet;
/// * anything else (a Matrix group we aren't an active participant of) →
///   nothing. On a Matrix account a link-only group is still created as one
///   (*Create group → Share with an invite link*).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../welcome/why_matrix_page.dart' show WhyMatrixPage;
import '../../core/l10n/l10n.dart';
import '../../core/link/link_channel.dart';
import '../../core/link/link_sync_engine.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/link/link_relay_policy.dart' show parseLinkRelays;
import '../../core/link/link_uri.dart';
import '../../core/link/nostr/nostr_relay_pool.dart' show kDefaultLinkRelays;
import '../../core/platform/text_sharer.dart';
import '../../core/session/app_session.dart';
import '../../core/session/device_prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/action_error.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/large_text.dart';
import '../../core/widgets/qr_code_view.dart';
import '../../models/group_model.dart';
import '../../models/link_model.dart';
import '../../models/member_model.dart';
import '../backup/backup_ui.dart' show runWithProgress;
import '../expenses/expenses_provider.dart';
import '../groups/group_provider.dart';
import 'relay_settings.dart';

/// What *Invite with a link* can do for a group on this device.
enum LinkInviteState {
  /// The group has a link channel here: show its link.
  open,

  /// No channel yet, but one can be opened (local mode, first invite).
  canOpen,

  /// G53: a Matrix group this account is an active participant of —
  /// *Invite by link* makes it a mixed group (signed meta with `link`).
  canOpenMixed,

  /// Not stored, or a Matrix group this account isn't an active participant
  /// of: no link.
  unavailable,
}

/// Pure: see the library doc. [localMode] = the ledger identity is local
/// mode's `local:self` (not a Matrix account); [identity] = this device's
/// MXID (G53: an active participant of a signed Matrix group may open a
/// link).
LinkInviteState linkInviteStateOf({
  required LinkChannelModel? channel,
  required GroupModel? group,
  required List<MemberModel> members,
  required bool localMode,
  String? identity,
}) {
  if (channel != null) return LinkInviteState.open;
  if (!localMode) {
    if (group != null && group.sig != null && identity != null) {
      final mine = claimedBy(members, identity);
      if (mine != null && mine.isActive) return LinkInviteState.canOpenMixed;
    }
    return LinkInviteState.unavailable;
  }
  return linkChannelBlocker(group, members, identity: kLocalAccountId) == null
      ? LinkInviteState.canOpen
      : LinkInviteState.unavailable;
}

/// [LinkInviteState] of a group — re-read when its members or the group
/// list change; the channel is read once (it only changes through this
/// device's own invite / join, which invalidate this provider). An error
/// (DB closed mid-switch) reads as [LinkInviteState.unavailable].
final linkInviteStateProvider = FutureProvider.autoDispose
    .family<LinkInviteState, String>((ref, groupId) async {
      final localMode = ref.watch(localModeActiveProvider);
      // The transport's MXID ('' until ready / signed out).
      final mxid = ref.watch(currentUserIdProvider);
      final identity = mxid.isEmpty ? null : mxid;
      final membersF = ref.watch(groupMembersProvider(groupId).future);
      final groupsF = ref.watch(ledgerGroupsProvider.future);
      final link = ref.watch(linkDaoProvider);
      try {
        final channel = await link.getChannel(groupId);
        final members = await membersF;
        final group = (await groupsF)
            .where((g) => g.roomId == groupId)
            .firstOrNull;
        return linkInviteStateOf(
          channel: channel,
          group: group,
          members: members,
          localMode: localMode,
          identity: identity,
        );
      } catch (_) {
        return LinkInviteState.unavailable;
      }
    });

/// Opens [groupId]'s link channel (or returns the existing one).
typedef LinkChannelOpener = Future<LinkChannelModel> Function(String groupId);

/// The invite's seam to the link sync engine (`LinkSyncEngine.openChannel`,
/// kept alive by `LedgerSyncHost`); widget tests replace it.
final linkChannelOpenerProvider = Provider<LinkChannelOpener>(
  (ref) =>
      (groupId) => ref.read(linkSyncEngineProvider).openChannel(groupId),
);

/// The relays named in the disclosure (host names) — the configured list
/// (G52 step 9), the defaults when none is given.
List<String> linkDisclosureRelayHosts([
  List<String> relays = kDefaultLinkRelays,
]) => [for (final r in relays) relayLabel(r)];

/// G52 step 9: the relays the disclosure names — the open ledger's
/// configured list (Settings → Relays), else the defaults. Reads only a DB
/// that is already open (never opens one) and never contacts a relay.
final linkDisclosureRelaysProvider = Provider<Future<List<String>> Function()>(
  (ref) => () async {
    try {
      if (ref.read(ledgerIdentityProvider) == null) return kDefaultLinkRelays;
      if (!ref.exists(appDatabaseProvider)) return kDefaultLinkRelays;
      final db = ref.read(appDatabaseProvider);
      if (db.isSignedOutPlaceholder || db.isClosed) return kDefaultLinkRelays;
      return parseLinkRelays(
        await SettingsDao(
          db,
        ).linkRelaysRaw().timeout(const Duration(seconds: 2)),
        kDefaultLinkRelays,
      );
    } catch (_) {
      return kDefaultLinkRelays;
    }
  },
);

/// Shows the first-use disclosure (§9.2) unless it was accepted on this
/// device before; true = go on (accepted now or earlier).
Future<bool> ensureLinkDisclosure(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(devicePrefsProvider.notifier);
  final seen = (await ref.read(devicePrefsProvider.future)).linkDisclosureSeen;
  if (seen) return true;
  final relays = await ref.read(linkDisclosureRelaysProvider)();
  if (!context.mounted) return false;
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LinkDisclosurePage(relays: relays),
    ),
  );
  if (ok != true) return false;
  try {
    await prefs.markLinkDisclosureSeen();
  } catch (e) {
    // Not stored: it is simply shown again next time.
    debugPrint('[link] disclosure flag not saved: $e');
  }
  return true;
}

/// *Invite with a link* for [groupId]: opens the channel on the first
/// invite (after the disclosure), then shows the invite sheet.
Future<void> inviteByLinkFlow(
  BuildContext context,
  WidgetRef ref,
  String groupId,
) async {
  final errors = ActionErrors.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final opener = ref.read(linkChannelOpenerProvider);
  final mixedOpener = ref.read(mixedLinkOpenerProvider);
  final link = ref.read(linkDaoProvider);
  final localMode = ref.read(localModeActiveProvider);
  final LinkInviteState state;
  // Keep the auto-dispose state alive while it is read.
  final sub = ref.listenManual(linkInviteStateProvider(groupId), (_, _) {});
  try {
    state = await ref.read(linkInviteStateProvider(groupId).future);
  } catch (e) {
    errors.show(e);
    return;
  } finally {
    sub.close();
  }
  if (!context.mounted) return;
  LinkChannelModel? channel;
  switch (state) {
    case LinkInviteState.unavailable:
      messenger.showSnackBar(SnackBar(content: Text(l.linkInviteMatrixGroup)));
      return;
    case LinkInviteState.canOpen:
      if (!await ensureLinkDisclosure(context, ref)) return;
      try {
        channel = await opener(groupId);
      } on LinkChannelException {
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(l.linkInviteMatrixGroup)),
          );
        }
        return;
      } catch (e) {
        errors.show(e);
        return;
      }
      if (context.mounted) {
        ref.invalidate(linkInviteStateProvider(groupId));
        // "Me" now comes from the channel (our claim was dropped).
        ref.invalidate(currentParticipantProvider(groupId));
      }
    case LinkInviteState.canOpenMixed:
      if (!await ensureLinkDisclosure(context, ref)) return;
      if (!context.mounted || !await confirmMixedLink(context)) return;
      if (!context.mounted) return;
      try {
        channel = await runWithProgress(
          context,
          l.linkMixedOpening,
          () => mixedOpener(groupId),
        );
      } catch (e) {
        errors.show(e);
        return;
      }
      if (context.mounted) ref.invalidate(linkInviteStateProvider(groupId));
    case LinkInviteState.open:
      try {
        channel = await link.getChannel(groupId);
      } catch (e) {
        errors.show(e);
        return;
      }
  }
  if (channel == null || !context.mounted) return;
  // G53: in a mixed group only a Matrix device can reset the link (it signs
  // the meta that carries it).
  var canReset = true;
  if (localMode) {
    try {
      canReset = !(await link.policyOf(groupId)).isMixed;
    } catch (_) {}
    if (!context.mounted) return;
  }
  final group = (ref.read(ledgerGroupsProvider).value ?? const [])
      .where((g) => g.roomId == groupId)
      .firstOrNull;
  final reset = await showLinkInviteSheet(
    context,
    channel: channel,
    groupName: group?.name,
    canReset: canReset,
  );
  if (reset && context.mounted) {
    await resetInviteLinkFlow(context, ref, groupId);
  }
}

/// Replaces [groupId]'s invite link (G52 step 12); returns the new channel.
typedef LinkResetter = Future<LinkChannelModel> Function(String groupId);

/// The reset's seam to the link sync engine (`LinkSyncEngine.resetLink`,
/// kept alive by `LedgerSyncHost`); widget tests replace it.
///
/// G53: in a **mixed** group the new link is a new signed meta
/// (`mixedLinkResetterProvider`) — every Matrix member's device follows it.
final linkResetterProvider = Provider<LinkResetter>(
  (ref) => (groupId) async {
    final engine = ref.read(linkSyncEngineProvider);
    final mixedReset = ref.read(mixedLinkResetterProvider);
    final policy = await ref.read(linkDaoProvider).policyOf(groupId);
    if (policy.isMixed) return mixedReset(groupId);
    return engine.resetLink(groupId);
  },
);

/// G53 (§10.1): asks before a **Matrix group** gets an invite link — what
/// changes (anyone with the link can see and change it, those changes
/// aren't verified, the Matrix members' devices share it through the relays
/// too, it can be made secure-only again). True = go on.
Future<bool> confirmMixedLink(BuildContext context) async {
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('linkMixedDialog'),
      // 360 dp at 200 %: title, body and buttons scroll together.
      scrollable: true,
      title: Text(l.linkMixedTitle),
      content: Text(l.linkMixedBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('linkMixedConfirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.linkMixedConfirm),
        ),
      ],
    ),
  );
  return ok == true;
}

/// G52 step 12 — *Reset invite link* (§7.3, §14 Q10): asks first (the old
/// link stops working, everyone still in the group needs the new one),
/// replaces the link behind a progress dialog (our copy leaves the old
/// topic first — bounded), then shows the invite sheet with the **new**
/// link and the "send it to everyone" hint — the new link is shared
/// directly, never posted where the old link could read it.
Future<void> resetInviteLinkFlow(
  BuildContext context,
  WidgetRef ref,
  String groupId,
) async {
  final errors = ActionErrors.of(context);
  final l = context.l10n;
  final resetter = ref.read(linkResetterProvider);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('linkResetDialog'),
      title: Text(l.linkResetTitle),
      content: SingleChildScrollView(child: Text(l.linkResetBody)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('linkResetConfirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.linkResetConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final LinkChannelModel channel;
  try {
    channel = await runWithProgress(
      context,
      l.linkResetting,
      () => resetter(groupId),
    );
  } catch (e) {
    errors.show(e, what: l.linkResetFailed);
    return;
  }
  if (!context.mounted) return;
  ref.invalidate(linkInviteStateProvider(groupId));
  final group = (ref.read(ledgerGroupsProvider).value ?? const [])
      .where((g) => g.roomId == groupId)
      .firstOrNull;
  await showLinkInviteSheet(
    context,
    channel: channel,
    groupName: group?.name,
    afterReset: true,
  );
}

/// The invite link of [channel] (https form — what is shared and put into
/// the QR code), with the group-name hint `n`.
String linkInviteUri(LinkChannelModel channel, {String? groupName}) =>
    buildLinkUri(decodeLinkSecret(channel.secret), name: groupName);

/// The invite sheet (§8.4). [canReset] shows *Reset invite link…* (G52
/// step 12) — the sheet then pops true and the caller runs the reset;
/// [afterReset] shows the "send the new link to everyone" hint. Returns
/// whether a reset was asked for.
Future<bool> showLinkInviteSheet(
  BuildContext context, {
  required LinkChannelModel channel,
  String? groupName,
  bool canReset = false,
  bool afterReset = false,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => LinkInviteSheet(
        link: linkInviteUri(channel, groupName: groupName),
        groupName: groupName ?? '',
        canReset: canReset,
        afterReset: afterReset,
      ),
    ) ==
    true;

class LinkInviteSheet extends ConsumerWidget {
  const LinkInviteSheet({
    super.key,
    required this.link,
    required this.groupName,
    this.canReset = false,
    this.afterReset = false,
  });

  final String link;
  final String groupName;

  /// G52 step 12: offer *Reset invite link…* (pops the sheet with true).
  final bool canReset;

  /// G52 step 12: the link was just reset — say who needs it now.
  final bool afterReset;

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await shareOrCopy(
      ref.read(textSharerProvider),
      l.linkInviteShareText(groupName, link),
      subject: groupName.isEmpty ? null : groupName,
    );
    if (outcome == ShareOutcome.copied) {
      messenger.showSnackBar(SnackBar(content: Text(l.shareCopiedFallback)));
    }
  }

  Future<void> _copy(BuildContext context) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: link));
    messenger.showSnackBar(SnackBar(content: Text(l.linkInviteCopied)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // The QR code never wider than the sheet (360 dp phones, 200 % font).
    final qrSize = (MediaQuery.sizeOf(context).width - 2 * Insets.page).clamp(
      120.0,
      240.0,
    );
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('linkInviteSheet'),
        padding: const EdgeInsets.fromLTRB(
          Insets.page,
          0,
          Insets.page,
          Insets.xl,
        ),
        child: ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(l.inviteByLink, style: theme.textTheme.titleLarge),
              ),
              const SizedBox(height: Insets.s),
              Text(l.linkInviteSheetBody, style: muted),
              if (afterReset) ...[
                const SizedBox(height: Insets.m),
                Card(
                  key: const Key('linkInviteAfterReset'),
                  child: Padding(
                    padding: const EdgeInsets.all(Insets.m),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.autorenew,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(width: Insets.m),
                        Expanded(
                          child: Text(
                            l.linkResetDoneHint,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Insets.l),
              Center(
                child: QrCodeView(
                  key: const Key('linkInviteQr'),
                  data: link,
                  size: qrSize,
                  semanticLabel: l.linkInviteQrLabel,
                ),
              ),
              const SizedBox(height: Insets.s),
              Text(
                l.linkInviteQrHint,
                style: muted,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Insets.l),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: Insets.s,
                runSpacing: Insets.s,
                children: [
                  FilledButton.icon(
                    key: const Key('linkInviteShare'),
                    onPressed: () => _share(context, ref),
                    icon: const Icon(Icons.share_outlined),
                    label: Text(l.linkInviteShare),
                  ),
                  OutlinedButton.icon(
                    key: const Key('linkInviteCopy'),
                    onPressed: () => _copy(context),
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(l.copy),
                  ),
                ],
              ),
              const SizedBox(height: Insets.l),
              Card(
                key: const Key('linkInviteWarning'),
                child: Padding(
                  padding: const EdgeInsets.all(Insets.m),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: Insets.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.linkInviteWarning,
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: Insets.xs),
                            Text(
                              l.linkInviteRecoveryHint,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (canReset) ...[
                const SizedBox(height: Insets.m),
                Center(
                  child: TextButton.icon(
                    key: const Key('linkInviteReset'),
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.autorenew),
                    label: Text(l.linkResetMenu),
                  ),
                ),
                Text(
                  l.linkResetSheetHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The first-use disclosure (§9.2): one screen, explicit *Continue*
/// (pops true); back / ✕ pops nothing (= cancel).
class LinkDisclosurePage extends StatelessWidget {
  const LinkDisclosurePage({super.key, this.relays});

  /// The relays (URLs) to name (default: the default relays).
  final List<String>? relays;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final list = relays ?? kDefaultLinkRelays;
    final hosts = linkDisclosureRelayHosts(list).join(', ');
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: Insets.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: Insets.m),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l.linkDisclosureTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const Key('linkDisclosure'),
                padding: const EdgeInsets.all(Insets.page),
                child: ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      point(
                        Icons.hub_outlined,
                        // §9.2: the defaults share one operator.
                        isDefaultRelayList(list)
                            ? l.linkDisclosureRelaysOneOperator(hosts)
                            : l.linkDisclosureRelays(hosts),
                      ),
                      point(Icons.lock_outline, l.linkDisclosureEncrypted),
                      point(
                        Icons.visibility_outlined,
                        l.linkDisclosureMetadata,
                      ),
                      point(Icons.link, l.linkDisclosureAnyone),
                      point(Icons.dns_outlined, l.linkDisclosureOwnRelay),
                      point(
                        Icons.verified_user_outlined,
                        l.linkDisclosureMatrix,
                      ),
                      // G54: the calm comparison — read only here (the
                      // disclosure sits in front of an invite / join).
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const Key('linkDisclosureWhyMatrix'),
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text(l.whyMatrixTitle),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const WhyMatrixPage(infoOnly: true),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Insets.page),
              child: ContentWidth(
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('linkDisclosureContinue'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(l.linkDisclosureContinue),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// G53 step 4 — whether this device may offer *Make group secure* for
/// [group]: a **mixed** group (signed meta with an open link) on a Matrix
/// account ([identity] an MXID) that claims an active participant. Pure.
bool canOfferLock({
  required GroupModel? group,
  required List<MemberModel> members,
  required String? identity,
}) {
  if (group == null || group.sig == null || group.link == null) return false;
  if (identity == null || !identity.startsWith('@')) return false;
  final mine = claimedBy(members, identity);
  return mine != null && mine.isActive;
}

/// G53 step 4 — *Make group secure* (§10.1 Lock): when someone active has
/// no Matrix account yet, a dialog names them (nothing is written);
/// otherwise a confirmation, then `groupLockerProvider` behind a progress
/// dialog and a snackbar.
Future<void> lockGroupFlow(
  BuildContext context,
  WidgetRef ref,
  String groupId,
) async {
  final errors = ActionErrors.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final locker = ref.read(groupLockerProvider);
  final members =
      ref.read(groupMembersProvider(groupId)).value ?? const <MemberModel>[];
  final blockers = lockBlockers(members);
  if (blockers.isNotEmpty) {
    await _showLockBlocked(context, blockers);
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('lockConfirmDialog'),
      scrollable: true,
      title: Text(l.lockConfirmTitle),
      content: Text(l.lockConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('lockConfirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.lockConfirm),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await runWithProgress(context, l.lockRunning, () => locker(groupId));
  } on LockNotEligibleException catch (e) {
    // Someone joined meanwhile.
    if (context.mounted) await _showLockBlocked(context, e.blockers);
    return;
  } catch (e) {
    errors.show(e, what: l.lockFailed);
    return;
  }
  if (context.mounted) ref.invalidate(linkInviteStateProvider(groupId));
  messenger.showSnackBar(SnackBar(content: Text(l.lockDone)));
}

Future<void> _showLockBlocked(
  BuildContext context,
  List<MemberModel> blockers,
) {
  final l = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('lockBlockedDialog'),
      scrollable: true,
      title: Text(l.lockBlockedTitle),
      content: Text(
        l.lockBlockedBody([for (final m in blockers) m.label].join(', ')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
        ),
      ],
    ),
  );
}
