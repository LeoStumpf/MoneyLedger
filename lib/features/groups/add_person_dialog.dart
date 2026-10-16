import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import 'group_provider.dart';

/// "Add person" (members page FAB and the group menu's *Add member*, G17):
/// a name and/or a Matrix ID.
///  * name only → a local participant (no account, never synced to);
///  * Matrix ID → a claimed participant, bootstrapped with the group; the
///    name is optional — left blank, the account's Matrix profile display
///    name is used (else its localpart).
Future<void> showAddPersonDialog(
  BuildContext context,
  WidgetRef ref,
  String roomId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final result = await showDialog<({String name, String matrixId})>(
    context: context,
    builder: (_) => const _AddPersonDialog(),
  );
  if (result == null) return;

  final notifier = ref.read(memberAdderProvider.notifier);
  final mxid = result.matrixId;
  if (mxid.isEmpty) {
    await notifier.addLocal(roomId, result.name);
  } else {
    await notifier.add(
      roomId,
      mxid,
      displayName: result.name.isEmpty ? null : result.name,
    );
  }
  final error = ref.read(memberAdderProvider).error;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        error != null
            ? l.failedWithError(error.toString())
            : l.addedMember(result.name.isNotEmpty ? result.name : mxid),
      ),
    ),
  );
}

bool _isMatrixId(String s) => s.startsWith('@') && s.contains(':');

class _AddPersonDialog extends StatefulWidget {
  const _AddPersonDialog();

  @override
  State<_AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<_AddPersonDialog> {
  final _name = TextEditingController();
  final _mxid = TextEditingController();
  String? _nameError;
  String? _mxidError;

  @override
  void dispose() {
    _name.dispose();
    _mxid.dispose();
    super.dispose();
  }

  void _submit() {
    final l = context.l10n;
    final name = _name.text.trim();
    final mxid = _mxid.text.trim();
    setState(() {
      _nameError = null;
      _mxidError = null;
      if (mxid.isNotEmpty && !_isMatrixId(mxid)) {
        _mxidError = l.invalidMatrixId;
      } else if (name.isEmpty && mxid.isEmpty) {
        _nameError = l.nameOrMatrixIdRequired;
      }
    });
    if (_nameError != null || _mxidError != null) return;
    Navigator.of(context).pop((name: name, matrixId: mxid));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.addPerson),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('addPersonName'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l.nameLabel,
                hintText: l.nameHint,
                helperText: l.nameOptionalHelper,
                helperMaxLines: 2,
                errorText: _nameError,
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.add)),
      ],
    );
  }
}
