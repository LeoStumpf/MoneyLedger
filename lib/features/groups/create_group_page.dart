import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/currency_field.dart';
import '../../models/member_model.dart' show duplicateNameOf;
import 'group_provider.dart';

class CreateGroupPage extends ConsumerStatefulWidget {
  const CreateGroupPage({super.key});

  @override
  ConsumerState<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends ConsumerState<CreateGroupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();

  /// G66: the device region's currency (de_CH → CHF), else EUR.
  late String _currency = defaultCurrencyFor(ref.read(deviceRegionProvider));

  /// G64 (U4): the other people, added as chips ("Who's in?"). The creator
  /// is always in the group ("You" chip) and isn't part of this list.
  final _people = <String>[];
  final _personCtrl = TextEditingController();
  final _personFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Rebuild for the live duplicate hint under the field.
    _personCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _personCtrl.dispose();
    _personFocus.dispose();
    super.dispose();
  }

  /// Adds the typed name as a chip (trimmed; blank → nothing) and keeps the
  /// focus in the field for the next one.
  void _addPerson() {
    final name = _personCtrl.text.trim();
    if (name.isNotEmpty) {
      setState(() => _people.add(name));
    }
    _personCtrl.clear();
    _personFocus.requestFocus();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // A name still in the field (typed, not yet added) counts too.
    final pending = _personCtrl.text.trim();
    final people = [..._people, if (pending.isNotEmpty) pending];
    final groupId = await ref
        .read(groupCreatorProvider.notifier)
        .create(_nameCtrl.text.trim(), _currency, people: people);
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
                      (v == null || v.trim().isEmpty) ? l.required : null,
                ),
                const SizedBox(height: 16),
                CurrencyField(
                  key: const Key('createGroupCurrency'),
                  value: _currency,
                  showName: true,
                  prefixIcon: const Icon(Icons.payments_outlined),
                  suggested: suggestedCurrencies(
                    selected: _currency,
                    region: ref.read(deviceRegionProvider),
                  ),
                  onChanged: (c) => setState(() => _currency = c),
                ),
                const SizedBox(height: Insets.xl),
                _peopleSection(context),
                const SizedBox(height: Insets.xl),
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

  /// "Who's in?": a name field (*Add* / Enter adds a chip and keeps the
  /// keyboard up) and the chips — "You" first (not removable), then the
  /// people added here (✕ removes one). A name that is already a chip gets
  /// a hint, but can still be added (U9).
  Widget _peopleSection(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final duplicate = duplicateNameOf(_personCtrl.text, _people);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('createGroupPersonField'),
          controller: _personCtrl,
          focusNode: _personFocus,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          // Enter adds the chip; overriding onEditingComplete keeps the
          // focus (and the keyboard) for the next name.
          onEditingComplete: () {},
          onSubmitted: (_) => _addPerson(),
          decoration: InputDecoration(
            labelText: l.createGroupPeopleLabel,
            hintText: l.nameHint,
            prefixIcon: const Icon(Icons.person_add_alt_1_outlined),
            helperText: duplicate != null
                ? l.duplicatePersonHint(duplicate)
                : l.createGroupPeopleHelper,
            helperMaxLines: 3,
            helperStyle: duplicate != null
                ? theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  )
                : null,
            suffixIcon: IconButton(
              key: const Key('createGroupPersonAdd'),
              tooltip: l.add,
              icon: const Icon(Icons.add),
              onPressed: _addPerson,
            ),
          ),
        ),
        const SizedBox(height: Insets.m),
        Wrap(
          spacing: Insets.s,
          runSpacing: Insets.s,
          children: [
            Chip(
              key: const Key('createGroupYouChip'),
              avatar: const Icon(Icons.person, size: 18),
              label: Text(l.you),
            ),
            for (var i = 0; i < _people.length; i++)
              InputChip(
                key: Key('createGroupPersonChip-$i'),
                label: Text(_people[i], overflow: TextOverflow.ellipsis),
                deleteButtonTooltipMessage: l.removePersonTooltip(_people[i]),
                onDeleted: () => setState(() => _people.removeAt(i)),
              ),
          ],
        ),
      ],
    );
  }
}
