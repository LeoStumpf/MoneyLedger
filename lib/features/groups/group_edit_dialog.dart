import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import 'create_group_page.dart' show kGroupCurrencies;

/// The "Edit group" dialog (G10): name + default currency. Returns the new
/// values, or null when cancelled. Changing the currency only affects **new**
/// expenses — existing ones keep their own currency (balances are per
/// currency), which the helper text says.
Future<({String name, String currency})?> showEditGroupDialog(
  BuildContext context, {
  required String name,
  required String currency,
}) =>
    showDialog<({String name, String currency})>(
      context: context,
      builder: (_) => _EditGroupDialog(name: name, currency: currency),
    );

class _EditGroupDialog extends StatefulWidget {
  final String name;
  final String currency;
  const _EditGroupDialog({required this.name, required this.currency});

  @override
  State<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends State<_EditGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.name);
  late String _currency = widget.currency;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((name: _nameCtrl.text.trim(), currency: _currency));
  }

  @override
  Widget build(BuildContext context) {
    // Keep a currency set elsewhere (CSV import, older app) selectable.
    final currencies = [
      ...kGroupCurrencies,
      if (!kGroupCurrencies.contains(widget.currency)) widget.currency,
    ];
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.editGroup),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(labelText: l.groupNameLabel),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l.required : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: InputDecoration(
                labelText: l.defaultCurrencyLabel,
                helperText: l.defaultCurrencyHelper,
                helperMaxLines: 3,
              ),
              items: currencies
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _currency = v ?? _currency),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l.save)),
      ],
    );
  }
}
