import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import 'group_provider.dart';

/// Currencies offered for a group's default currency (create + edit).
const kGroupCurrencies = ['EUR', 'USD', 'GBP', 'CHF', 'JPY', 'CAD', 'AUD'];

class CreateGroupPage extends ConsumerStatefulWidget {
  const CreateGroupPage({super.key});

  @override
  ConsumerState<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends ConsumerState<CreateGroupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  String _currency = 'EUR';

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final groupId = await ref
        .read(groupCreatorProvider.notifier)
        .create(_nameCtrl.text.trim(), _currency);
    if (!mounted) return;
    final error = ref.read(groupCreatorProvider).error;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.failedWithError(error.toString()))),
      );
    } else if (groupId != null) {
      // G46: open the new group right away. Replacing this page keeps the
      // groups list underneath, so Back from the group lands there.
      context.pushReplacement('/groups/$groupId/expenses');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupCreatorProvider);
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.newGroup)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.page),
        child: ContentWidth(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l.groupNameLabel,
                    prefixIcon: const Icon(Icons.groups_2_outlined),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? l.required : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: InputDecoration(
                    labelText: l.currencyLabel,
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                  items: kGroupCurrencies
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _currency = v ?? 'EUR'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: state.isLoading ? null : _submit,
                  child: state.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l.create),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
