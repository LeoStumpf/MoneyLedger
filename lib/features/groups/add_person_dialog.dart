import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/action_error.dart';

import '../../core/l10n/l10n.dart';
import '../../core/session/app_session.dart';
import '../../core/theme/app_theme.dart';
import '../../models/member_model.dart' show MemberModel, duplicateNameOf;
import 'group_provider.dart';

/// "Add person" (members page FAB and the group menu's *Add person*, G17):
/// a name and/or a Matrix ID.
///  * name only → a local participant (no account, never synced to);
///  * Matrix ID → a claimed participant, bootstrapped with the group; the
///    name is optional — left blank, the account's Matrix profile display
///    name is used (else its localpart).
///
/// G64 (U9): *Add & next* adds the person and keeps the dialog open with an
/// empty field for the next one ("Added X" inside the dialog); a name that
/// already exists in the group (trimmed, case-insensitive — incl. people no
/// longer in it and the ones just added) shows a hint but can still be
/// added. *Add* adds and closes, as before.
Future<void> showAddPersonDialog(
  BuildContext context,
  WidgetRef ref,
  String roomId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final errors = ActionErrors.of(context);
  final l = context.l10n;
  // G40: local mode has no Matrix accounts — a name only.
  final local = ref.read(localModeActiveProvider);
  final existing = <String>[
    for (final m
        in ref.read(groupMembersProvider(roomId)).value ??
            const <MemberModel>[])
      m.label,
  ];

  /// Runs the write; returns the error (null = added).
  Future<Object?> addOne(String name, String mxid) async {
    final notifier = ref.read(memberAdderProvider.notifier);
    if (mxid.isEmpty) {
      await notifier.addLocal(roomId, name);
    } else {
      await notifier.add(roomId, mxid, displayName: name.isEmpty ? null : name);
    }
    if (!context.mounted) return null;
    return ref.read(memberAdderProvider).error;
  }

  final result = await showDialog<({String name, String matrixId})>(
    context: context,
    builder: (_) => AddPersonDialog(
      nameOnly: local,
      existingNames: existing,
      onAddAndNext: addOne,
    ),
  );
  if (result == null) return;

  final error = await addOne(result.name, result.matrixId);
  if (error != null) {
    errors.show(error);
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        l.addedMember(result.name.isNotEmpty ? result.name : result.matrixId),
      ),
    ),
  );
}

bool _isMatrixId(String s) => s.startsWith('@') && s.contains(':');

/// The dialog behind [showAddPersonDialog] (public for tests). *Add* pops
/// `(name, matrixId)`; *Add & next* calls [onAddAndNext] itself (it returns
/// the write's error, null = added) and stays open.
class AddPersonDialog extends StatefulWidget {
  const AddPersonDialog({
    super.key,
    this.nameOnly = false,
    this.existingNames = const [],
    required this.onAddAndNext,
  });

  /// G40 local mode: no Matrix ID field; the name is required.
  final bool nameOnly;

  /// Names already in the group (active and former) — for the duplicate
  /// hint (U9).
  final List<String> existingNames;

  final Future<Object?> Function(String name, String matrixId) onAddAndNext;

  @override
  State<AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<AddPersonDialog> {
  final _name = TextEditingController();
  final _mxid = TextEditingController();
  final _nameFocus = FocusNode();
  String? _nameError;
  String? _mxidError;

  /// Names added with *Add & next* in this dialog (duplicate hint + the
  /// "Added …" line).
  final _added = <String>[];
  Object? _addError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _mxid.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// The validated input, or null (errors shown).
  ({String name, String matrixId})? _validated() {
    final l = context.l10n;
    final name = _name.text.trim();
    final mxid = _mxid.text.trim();
    setState(() {
      _nameError = null;
      _mxidError = null;
      if (mxid.isNotEmpty && !_isMatrixId(mxid)) {
        _mxidError = l.invalidMatrixId;
      } else if (name.isEmpty && mxid.isEmpty) {
        _nameError = widget.nameOnly
            ? l.localSetupNameRequired
            : l.nameOrMatrixIdRequired;
      }
    });
    if (_nameError != null || _mxidError != null) return null;
    return (name: name, matrixId: mxid);
  }

  void _submit() {
    if (_busy) return;
    final input = _validated();
    if (input == null) return;
    Navigator.of(context).pop(input);
  }

  Future<void> _addAndNext() async {
    if (_busy) return;
    final input = _validated();
    if (input == null) return;
    setState(() {
      _busy = true;
      _addError = null;
    });
    final error = await widget.onAddAndNext(input.name, input.matrixId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _addError = error;
      if (error == null) {
        _added.add(input.name.isNotEmpty ? input.name : input.matrixId);
        _name.clear();
        _mxid.clear();
      }
    });
    _nameFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final duplicate = duplicateNameOf(_name.text, [
      ...widget.existingNames,
      ..._added,
    ]);
    return AlertDialog(
      title: Text(l.addPerson),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('addPersonName'),
              controller: _name,
              focusNode: _nameFocus,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onSubmitted: widget.nameOnly ? (_) => _submit() : null,
              decoration: InputDecoration(
                labelText: l.nameLabel,
                hintText: l.nameHint,
                helperText: duplicate != null
                    ? l.duplicatePersonHint(duplicate)
                    : widget.nameOnly
                    ? null
                    : l.nameOptionalHelper,
                helperMaxLines: 3,
                helperStyle: duplicate != null
                    ? theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.secondary,
                      )
                    : null,
                errorText: _nameError,
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            if (!widget.nameOnly) ...[
              const SizedBox(height: Insets.m),
              TextField(
                key: const Key('addPersonMatrixId'),
                controller: _mxid,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l.matrixIdOptionalLabel,
                  hintText: l.matrixIdOptionalHint,
                  hintMaxLines: 2,
                  errorText: _mxidError,
                  prefixIcon: const Icon(Icons.alternate_email),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_addError case final error?) ...[
              const SizedBox(height: Insets.m),
              ActionErrorView(key: const Key('addPersonError'), error: error),
            ] else if (_added.isNotEmpty) ...[
              const SizedBox(height: Insets.m),
              Text(
                l.addedMember(_added.join(', ')),
                key: const Key('addPersonStatus'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          // Once someone was added here, closing is "done", not "cancel".
          child: Text(_added.isEmpty ? l.cancel : l.done),
        ),
        TextButton(
          key: const Key('addPersonNext'),
          onPressed: _busy ? null : _addAndNext,
          child: Text(l.addAndNext),
        ),
        FilledButton(
          key: const Key('addPersonSubmit'),
          onPressed: _busy ? null : _submit,
          child: Text(l.add),
        ),
      ],
    );
  }
}
