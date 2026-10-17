import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../errors/action_errors.dart';
import '../l10n/l10n.dart';

/// Shows failed user actions the G67 way (U25): a friendly snackbar from
/// [describeActionError] — optionally headed by *what* failed ("Export
/// failed") — with the raw error text only behind a *Details* action.
///
/// Capture it **before the first await** ([ActionErrors.of]): the page may
/// be gone by the time the action fails, the messenger and navigator stay.
class ActionErrors {
  ActionErrors.of(BuildContext context)
    : _messenger = ScaffoldMessenger.of(context),
      _navigator = Navigator.maybeOf(context, rootNavigator: true),
      _l = context.l10n;

  /// Null when [context] has no messenger (then [show] does nothing).
  static ActionErrors? maybeOf(BuildContext context) =>
      ScaffoldMessenger.maybeOf(context) == null
      ? null
      : ActionErrors.of(context);

  final ScaffoldMessengerState _messenger;
  final NavigatorState? _navigator;
  final AppLocalizations _l;

  /// Shows [error]; [what] (e.g. `l.exportFailedTitle`) becomes the first
  /// line. A no-op when the messenger is gone.
  ///
  /// G75 (G67 leftover): [retry] adds *Try again* (the snackbar's action;
  /// *Details* then moves into the content) — only for actions that can
  /// simply run again (export, picking a file). The callback must check
  /// that its page is still mounted itself.
  void show(Object error, {String? what, VoidCallback? retry}) {
    if (!_messenger.mounted) return;
    final m = describeActionError(error, _l);
    final detail = m.detail;
    final lines = ActionErrorLines(message: m, what: what);
    _messenger.showSnackBar(
      SnackBar(
        key: const Key('actionErrorSnack'),
        duration: const Duration(seconds: 8),
        content: retry == null || detail == null
            ? lines
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  lines,
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Builder(
                      builder: (context) => TextButton(
                        key: const Key('actionErrorDetails'),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.inversePrimary,
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () => _showDetails(detail),
                        child: Text(_l.errorDetails),
                      ),
                    ),
                  ),
                ],
              ),
        action: retry != null
            ? SnackBarAction(
                key: const Key('actionErrorRetry'),
                label: _l.errorTryAgain,
                onPressed: retry,
              )
            : detail == null
            ? null
            : SnackBarAction(
                key: const Key('actionErrorDetails'),
                label: _l.errorDetails,
                onPressed: () => _showDetails(detail),
              ),
      ),
    );
  }

  void _showDetails(String detail) {
    final nav = _navigator;
    if (nav != null && nav.mounted) {
      showDialog<void>(
        context: nav.context,
        builder: (ctx) => ActionErrorDetailsDialog(detail: detail, l: _l),
      );
      return;
    }
    // No navigator (shouldn't happen in the app): the text as a snackbar.
    if (_messenger.mounted) {
      _messenger.showSnackBar(
        SnackBar(content: SelectableText(detail), showCloseIcon: true),
      );
    }
  }
}

/// Shortcut for a still-mounted [context]: `ActionErrors.of(context).show`.
void showActionError(
  BuildContext context,
  Object error, {
  String? what,
  VoidCallback? retry,
}) => ActionErrors.of(context).show(error, what: what, retry: retry);

/// The text of an action error: [what] (bold, optional), the title, the hint.
class ActionErrorLines extends StatelessWidget {
  const ActionErrorLines({super.key, required this.message, this.what});

  final ActionErrorMessage message;
  final String? what;

  @override
  Widget build(BuildContext context) {
    final hint = message.hint;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (what != null)
          Text(
            what!,
            key: const Key('actionErrorWhat'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        Text(
          message.title,
          key: const Key('actionErrorTitle'),
          style: what == null
              ? const TextStyle(fontWeight: FontWeight.w600)
              : null,
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(hint, key: const Key('actionErrorHint')),
          ),
      ],
    );
  }
}

/// The raw error text, selectable, with *Copy* (for a bug report).
class ActionErrorDetailsDialog extends StatelessWidget {
  const ActionErrorDetailsDialog({
    super.key,
    required this.detail,
    required this.l,
  });

  final String detail;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('actionErrorDetailsDialog'),
    title: Text(l.errorDetailsTitle),
    content: SingleChildScrollView(
      child: SelectableText(
        detail,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Clipboard.setData(ClipboardData(text: detail)),
        child: Text(l.copy),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l.ok),
      ),
    ],
  );
}

/// An action / load error shown **inline** (a failed list, an error inside
/// a dialog): icon, [what], title, hint and a collapsed *Details* with the
/// raw text.
class ActionErrorView extends StatelessWidget {
  const ActionErrorView({super.key, required this.error, this.what});

  final Object error;
  final String? what;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = describeActionError(error, l);
    final theme = Theme.of(context);
    final detail = m.detail;
    return Column(
      key: const Key('actionErrorView'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium,
                child: ActionErrorLines(message: m, what: what),
              ),
            ),
          ],
        ),
        if (detail != null)
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('actionErrorViewDetails'),
              tilePadding: const EdgeInsets.only(left: 36),
              childrenPadding: const EdgeInsets.only(left: 36, bottom: 8),
              dense: true,
              expandedAlignment: Alignment.centerLeft,
              title: Text(l.errorDetails, style: theme.textTheme.labelLarge),
              children: [
                SelectableText(detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}
