import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/platform/is_web.dart';
import '../../core/session/app_session.dart';
import '../../core/session/device_prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/action_error.dart';
import '../backup/backup_restore_page.dart' show kBackupLocation;

/// G75 (U31): the web's limits in one place — no background sync (Matrix
/// mode: it syncs only while the tab is open), no restore points, the data
/// lives in this browser only.
String webLimitsText(AppLocalizations l, {required bool local}) =>
    local ? l.webLimitsBodyLocal : l.webLimitsBody;

/// G75 (U31): shown once on the groups page on the web, until *Got it*
/// (device-wide flag `DevicePrefs.webNoticeSeen`, stored in this browser).
/// Never on Android, never while the prefs are still loading.
class WebLimitsBanner extends ConsumerWidget {
  const WebLimitsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isWebProvider)) return const SizedBox.shrink();
    final prefs = ref.watch(devicePrefsProvider).value;
    if (prefs == null || prefs.webNoticeSeen) return const SizedBox.shrink();
    final l = context.l10n;
    final local = ref.watch(localModeActiveProvider);
    final scheme = Theme.of(context).colorScheme;
    final onColor = scheme.onSurface;
    final buttonStyle = TextButton.styleFrom(foregroundColor: onColor);
    return Material(
      key: const Key('webLimitsBanner'),
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.page,
            Insets.m,
            Insets.page,
            Insets.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.language, color: onColor),
                  const SizedBox(width: Insets.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l.webLimitsTitle,
                            style: TextStyle(
                              color: onColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: Insets.xs),
                        Text(
                          webLimitsText(l, local: local),
                          key: const Key('webLimitsBody'),
                          style: TextStyle(color: onColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: Insets.s,
                  children: [
                    TextButton(
                      key: const Key('webLimitsBackup'),
                      // G71: the accent on this grey fails AA — ink instead.
                      style: buttonStyle,
                      onPressed: () => context.push(kBackupLocation),
                      child: Text(l.webLimitsBackup),
                    ),
                    TextButton(
                      key: const Key('webLimitsDismiss'),
                      style: buttonStyle,
                      onPressed: () async {
                        final errors = ActionErrors.of(context);
                        try {
                          await ref
                              .read(devicePrefsProvider.notifier)
                              .markWebNoticeSeen();
                        } catch (e) {
                          // The banner is gone for this run anyway (state
                          // changed); say the choice wasn't stored.
                          errors.show(e);
                        }
                      },
                      child: Text(l.webLimitsDismiss),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// G75 (U31): the same text again from *About* (web only).
class WebLimitsAboutTile extends ConsumerWidget {
  const WebLimitsAboutTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isWebProvider)) return const SizedBox.shrink();
    final l = context.l10n;
    final local = ref.watch(localModeActiveProvider);
    return ListTile(
      key: const Key('webLimitsTile'),
      leading: const Icon(Icons.language),
      title: Text(l.webLimitsTitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.webLimitsTitle),
          content: Text(
            webLimitsText(l, local: local),
            key: const Key('webLimitsDialogBody'),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.ok),
            ),
          ],
        ),
      ),
    );
  }
}
