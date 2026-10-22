/// G52 step 12 follow-up (design doc §7.3, Leo 2026-10-22): the group
/// page's hint for a member still on an **old** invite link — someone
/// reset (or switched) the link and posted the header-only "this link was
/// replaced" marker on the old topic. The new link itself only travels
/// directly (share sheet / QR), so the hint says to ask for it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/link/link_replaced.dart';
import '../expenses/expenses_provider.dart' show linkDaoProvider;
import '../onboarding/onboarding_provider.dart' show settingsDaoProvider;

/// The visible "link replaced" notice of a group (null: none) — only one
/// that arrived on this device's current channel and wasn't dismissed.
final linkReplacedNoticeProvider = StreamProvider.autoDispose
    .family<LinkReplacedNotice?, String>((ref, groupId) {
      final settings = ref.watch(settingsDaoProvider);
      final link = ref.watch(linkDaoProvider);
      return settings.watchLinkReplacedRaw(groupId).asyncMap((raw) async {
        final notice = LinkReplacedNotice.decode(raw);
        if (notice == null) return null;
        return visibleLinkReplacedNotice(
          notice,
          await link.getChannel(groupId),
        );
      });
    });

/// Closes the banner for this channel (a later marker on the same link
/// doesn't bring it back; a new channel starts fresh).
Future<void> dismissLinkReplacedNotice(WidgetRef ref, String groupId) async {
  final settings = ref.read(settingsDaoProvider);
  final notice = LinkReplacedNotice.decode(
    await settings.linkReplacedRaw(groupId),
  );
  if (notice == null) return;
  await settings.setLinkReplacedRaw(groupId, notice.asDismissed.encode());
}

/// The banner text: by this device's own person (another phone of the
/// user), by someone named, or by someone unknown.
String linkReplacedBannerText(
  AppLocalizations l, {
  required String? by,
  required String? me,
  required Map<String, String> names,
}) {
  if (by != null && by == me) return l.linkReplacedBannerMe;
  final name = by == null ? null : names[by];
  return name == null ? l.linkReplacedBannerNoName : l.linkReplacedBanner(name);
}

class LinkReplacedBanner extends ConsumerWidget {
  final String groupId;

  /// This device's participant in the group (null: none yet).
  final String? me;
  final Map<String, String> names;

  const LinkReplacedBanner({
    super.key,
    required this.groupId,
    required this.me,
    required this.names,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(linkReplacedNoticeProvider(groupId)).value;
    if (notice == null) return const SizedBox.shrink();
    final l = context.l10n;
    return MaterialBanner(
      key: const Key('linkReplacedBanner'),
      // As the other group-page banners (G67): the action goes below.
      forceActionsBelow: true,
      leading: const Icon(Icons.link_off),
      content: Text(
        linkReplacedBannerText(l, by: notice.by, me: me, names: names),
      ),
      actions: [
        TextButton(
          key: const Key('linkReplacedDismiss'),
          onPressed: () => dismissLinkReplacedNotice(ref, groupId),
          child: Text(l.dismiss),
        ),
      ],
    );
  }
}
