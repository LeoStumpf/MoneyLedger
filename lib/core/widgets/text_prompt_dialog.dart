import 'package:flutter/material.dart';

/// A one-field text prompt (title, field, Cancel + confirm). It owns its
/// [TextEditingController] and disposes it with the dialog's state — i.e.
/// only after the close animation. (Disposing a caller-owned controller as
/// soon as `showDialog` returns crashes the still-animating TextField, G15.)
///
/// Pops with the trimmed text, or `null` on cancel. [accept] may veto the
/// confirm (e.g. an invalid Matrix ID keeps the dialog open). [helperFor]
/// (G75) gives a live, non-blocking hint for the typed value (null = none),
/// e.g. "There is already a Ben in this group".
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String label,
  required String cancelLabel,
  required String confirmLabel,
  String? hint,
  String initial = '',
  TextInputType? keyboardType,
  bool Function(String value)? accept,
  String? Function(String value)? helperFor,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPromptDialog(
    title: title,
    label: label,
    hint: hint,
    initial: initial,
    cancelLabel: cancelLabel,
    confirmLabel: confirmLabel,
    keyboardType: keyboardType,
    accept: accept,
    helperFor: helperFor,
  ),
);

class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String label;
  final String? hint;
  final String initial;
  final String cancelLabel;
  final String confirmLabel;
  final TextInputType? keyboardType;
  final bool Function(String value)? accept;
  final String? Function(String value)? helperFor;

  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.initial,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.keyboardType,
    required this.accept,
    this.helperFor,
  });

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final value = _ctrl.text.trim();
    if (widget.accept != null && !widget.accept!(value)) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final helper = widget.helperFor?.call(_ctrl.text);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('textPromptField'),
        controller: _ctrl,
        autofocus: true,
        keyboardType: widget.keyboardType,
        onChanged: widget.helperFor == null ? null : (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          helperText: helper,
          helperMaxLines: 3,
          helperStyle: helper == null
              ? null
              : theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
