import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../backup/backup_ui.dart' show BackupRestorer, backupErrorMessage;
import '../backup/ledger_backup.dart' show BackupFormatException;
import 'restore_points.dart';

/// Route of [RestorePointsPage].
const kRestorePointsLocation = '/restore-points';

/// G48: Settings → *Restore points* — the rotating on-device snapshots of
/// this ledger (native only), each restorable through the normal backup
/// restore (preview → confirm → LWW merge), plus where to find the per-group
/// reset.
class RestorePointsPage extends ConsumerWidget {
  const RestorePointsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final supported = ref.watch(snapshotsSupportedProvider);
    final points = ref.watch(restorePointsProvider);

    Widget para(String text, {Key? key, TextStyle? style}) => Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.page,
        Insets.s,
        Insets.page,
        Insets.s,
      ),
      child: Text(text, key: key, style: style ?? muted),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.restorePointsTitle)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.only(top: Insets.s, bottom: Insets.xxl),
          children: [
            if (!supported)
              para(l.restorePointsWebUnsupported, key: const Key('noSnapshots'))
            else ...[
              para(l.restorePointsIntro),
              para(l.restorePointsHowItWorks),
              const SizedBox(height: Insets.s),
              ...points.when(
                loading: () => const [
                  Padding(
                    padding: EdgeInsets.all(Insets.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (e, _) => [
                  para(l.restorePointsLoadFailed(e.toString())),
                ],
                data: (list) => list.isEmpty
                    ? [
                        para(
                          l.restorePointsEmpty,
                          key: const Key('restorePointsEmpty'),
                          style: theme.textTheme.bodyLarge,
                        ),
                      ]
                    : [
                        for (final p in list)
                          ListTile(
                            key: Key('restorePoint-${p.name}'),
                            leading: const Icon(Icons.history),
                            title: Text(
                              p.exportedAt == null || p.exportedAt == 0
                                  ? context.date(p.day.millisecondsSinceEpoch)
                                  : context.dateTime(p.exportedAt!),
                            ),
                            subtitle: Text(
                              '${l.restorePointGroups(p.groups)} · '
                              '${l.restorePointEntries(p.records)}',
                            ),
                            trailing: TextButton(
                              key: Key('restorePointRestore-${p.name}'),
                              onPressed: () => _restore(context, ref, p),
                              child: Text(l.restorePointRestore),
                            ),
                          ),
                      ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    RestorePoint point,
  ) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    // Captured before the first await (G19).
    final service = ref.read(restorePointsServiceProvider);
    final restorer = BackupRestorer.of(ref, exactState: true);
    try {
      final backup = await service.read(point.name);
      if (!context.mounted) return;
      await restorer.previewAndRestore(context, backup);
    } on BackupFormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(backupErrorMessage(e, l))));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.restoreFailed(e.toString()))),
      );
    }
  }
}
