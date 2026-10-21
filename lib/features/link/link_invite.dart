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
/// * any other group — a **Matrix group** — gets nothing: it stays a Matrix
///   group until G53's *Invite by link* (§14 Q13). On a Matrix account a
///   link group is created as one (*Create group → Share with an invite
///   link*), because a Matrix device signs the meta of every group it
///   writes and a signed meta can't get a channel.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/link/link_channel.dart';
import '../../core/link/link_sync_engine.dart';
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
import '../expenses/expenses_provider.dart';
import '../groups/group_provider.dart';

/// What *Invite with a link* can do for a group on this device.
enum LinkInviteState {
  /// The group has a link channel here: show its link.
  open,

  /// No channel yet, but one can be opened (local mode, first invite).
  canOpen,

  /// A Matrix group (or not stored): no link until G53.
  unavailable,
}

/// Pure: see the library doc. [localMode] = the ledger identity is local
/// mode's `local:self` (not a Matrix account).
LinkInviteState linkInviteStateOf({
  required LinkChannelModel? channel,
  required GroupModel? group,
  required List<MemberModel> members,
  required bool localMode,
}) {
  if (channel != null) return LinkInviteState.open;
  if (!localMode) return LinkInviteState.unavailable;
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

/// The relays named in the disclosure (host names). Step 9 makes the list
/// configurable; until then the defaults.
List<String> linkDisclosureRelayHosts([
  List<String> relays = kDefaultLinkRelays,
]) => [for (final r in relays) Uri.tryParse(r)?.host ?? r];

/// Shows the first-use disclosure (§9.2) unless it was accepted on this
/// device before; true = go on (accepted now or earlier).
Future<bool> ensureLinkDisclosure(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(devicePrefsProvider.notifier);
  final seen = (await ref.read(devicePrefsProvider.future)).linkDisclosureSeen;
  if (seen) return true;
  if (!context.mounted) return false;
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const LinkDisclosurePage(),
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
  final link = ref.read(linkDaoProvider);
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
    case LinkInviteState.open:
      try {
        channel = await link.getChannel(groupId);
      } catch (e) {
        errors.show(e);
        return;
      }
  }
  if (channel == null || !context.mounted) return;
  final group = (ref.read(ledgerGroupsProvider).value ?? const [])
      .where((g) => g.roomId == groupId)
      .firstOrNull;
  await showLinkInviteSheet(context, channel: channel, groupName: group?.name);
}

/// The invite link of [channel] (https form — what is shared and put into
/// the QR code), with the group-name hint `n`.
String linkInviteUri(LinkChannelModel channel, {String? groupName}) =>
    buildLinkUri(decodeLinkSecret(channel.secret), name: groupName);

/// The invite sheet (§8.4).
Future<void> showLinkInviteSheet(
  BuildContext context, {
  required LinkChannelModel channel,
  String? groupName,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => LinkInviteSheet(
    link: linkInviteUri(channel, groupName: groupName),
    groupName: groupName ?? '',
  ),
);

class LinkInviteSheet extends ConsumerWidget {
  const LinkInviteSheet({
    super.key,
    required this.link,
    required this.groupName,
  });

  final String link;
  final String groupName;

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

  /// Relay host names to name (default: [linkDisclosureRelayHosts]).
  final List<String>? relays;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final hosts = (relays ?? linkDisclosureRelayHosts()).join(', ');
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
                      point(Icons.hub_outlined, l.linkDisclosureRelays(hosts)),
                      point(Icons.lock_outline, l.linkDisclosureEncrypted),
                      point(
                        Icons.visibility_outlined,
                        l.linkDisclosureMetadata,
                      ),
                      point(Icons.link, l.linkDisclosureAnyone),
                      point(
                        Icons.verified_user_outlined,
                        l.linkDisclosureMatrix,
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
