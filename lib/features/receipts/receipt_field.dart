import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/action_error.dart';
import 'receipt_picker.dart';

/// G78: the expense form's *Receipt photo* section (Android only — the
/// parent shows it only while `receiptsSupportedProvider` is true).
/// Controlled: [photo] is what the form will store on save, [onChanged]
/// reports a new photo (or null = removed). Nothing is written here.
class ReceiptField extends ConsumerWidget {
  const ReceiptField({super.key, required this.photo, required this.onChanged});

  final Uint8List? photo;
  final ValueChanged<Uint8List?> onChanged;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final errors = ActionErrors.maybeOf(context);
    final picker = ref.read(receiptPickerProvider);
    final source = await showModalBottomSheet<ReceiptSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('receiptCamera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l.receiptTakePhoto),
              onTap: () => Navigator.of(ctx).pop(ReceiptSource.camera),
            ),
            ListTile(
              key: const Key('receiptGallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l.receiptChooseFromGallery),
              onTap: () => Navigator.of(ctx).pop(ReceiptSource.gallery),
            ),
            const SizedBox(height: Insets.s),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final bytes = await picker(source);
      if (bytes != null && bytes.isNotEmpty) onChanged(bytes);
    } catch (e) {
      errors?.show(e, what: l.receiptPickFailed);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final photo = this.photo;
    return Column(
      key: const Key('receiptSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.receiptPhotoLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: Insets.s),
        if (photo == null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const Key('receiptAdd'),
              onPressed: () => _pick(context, ref),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(l.receiptAdd),
            ),
          )
        else
          Row(
            children: [
              Tooltip(
                message: l.receiptView,
                child: Material(
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(Radii.s),
                  color: scheme.surfaceContainerHighest,
                  child: Semantics(
                    button: true,
                    child: InkWell(
                      key: const Key('receiptThumbnail'),
                      onTap: () => showReceiptViewer(context, photo),
                      child: Image.memory(
                        photo,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        cacheWidth: 216,
                        gaplessPlayback: true,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => SizedBox(
                          width: 72,
                          height: 72,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Insets.m),
              Expanded(
                child: Wrap(
                  spacing: Insets.xs,
                  children: [
                    TextButton.icon(
                      key: const Key('receiptReplace'),
                      onPressed: () => _pick(context, ref),
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(l.receiptReplace),
                    ),
                    TextButton.icon(
                      key: const Key('receiptRemove'),
                      onPressed: () => onChanged(null),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l.receiptRemove),
                    ),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: Insets.s),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.phone_android_outlined,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: Insets.xs),
            Expanded(
              child: Text(
                l.receiptLocalOnlyHint,
                key: const Key('receiptLocalOnlyHint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// G78: the receipt photo full screen — pinch / double-tap-free zoom via
/// [InteractiveViewer].
Future<void> showReceiptViewer(BuildContext context, Uint8List photo) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => ReceiptViewerPage(photo: photo),
      ),
    );

class ReceiptViewerPage extends StatelessWidget {
  const ReceiptViewerPage({super.key, required this.photo});

  final Uint8List photo;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.receiptPhotoLabel)),
      body: InteractiveViewer(
        key: const Key('receiptViewer'),
        minScale: 1,
        maxScale: 6,
        child: Center(
          child: Image.memory(
            photo,
            fit: BoxFit.contain,
            semanticLabel: l.receiptPhotoLabel,
            errorBuilder: (_, _, _) => Padding(
              padding: const EdgeInsets.all(Insets.xl),
              child: Text(
                l.receiptUnreadable,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
