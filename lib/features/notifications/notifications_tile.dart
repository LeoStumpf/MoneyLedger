import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/background/background_sync_provider.dart';
import '../../core/l10n/l10n.dart';
import 'notifications_provider.dart';

/// G72: settings → *Sync* → *Notifications* (Android only): on by default,
/// needs background sync (the round posts them); shows off while Android
/// doesn't allow them (turning it on asks), says so once Android blocks
/// them for good.
class NotificationsTile extends ConsumerWidget {
  const NotificationsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(notificationsSupportedProvider)) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    final theme = Theme.of(context);
    final enabled = ref.watch(notificationsEnabledProvider).value ?? true;
    final background = ref.watch(backgroundSyncEnabledProvider).value ?? true;
    final granted = ref.watch(notificationPermissionProvider).value;
    final denials = ref.watch(notificationPermissionDenialsProvider).value ?? 0;
    // Not allowed (yet): the switch shows off — turning it on asks again.
    // "Blocked" only once Android stopped asking (2nd denial, smoke 7.13).
    final blocked =
        background &&
        enabled &&
        notificationsBlockedFor(granted: granted, denials: denials);
    return SwitchListTile(
      key: const Key('notificationsSwitch'),
      secondary: const Icon(Icons.notifications_outlined),
      title: Text(l.notificationsTitle),
      subtitle: Text(
        !background
            ? l.notificationsNeedBackgroundSync
            : blocked
            ? l.notificationsBlocked
            : l.notificationsBody,
        key: const Key('notificationsSubtitle'),
        style: blocked ? TextStyle(color: theme.colorScheme.error) : null,
      ),
      value: background && enabled && granted != false,
      onChanged: background ? (v) => setNotificationsEnabled(ref, v) : null,
    );
  }
}
