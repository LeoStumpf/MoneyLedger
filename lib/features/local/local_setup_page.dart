import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/action_error.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/session/device_prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/large_text.dart';

/// G40: "Use without an account" — explains local mode and asks for the
/// user's name (how they appear in their local groups). Starting it opens the
/// device-local ledger; no Matrix client is ever built.
class LocalSetupPage extends ConsumerStatefulWidget {
  const LocalSetupPage({super.key});

  @override
  ConsumerState<LocalSetupPage> createState() => _LocalSetupPageState();
}

class _LocalSetupPageState extends ConsumerState<LocalSetupPage> {
  final _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final l = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l.localSetupNameRequired);
      return;
    }
    final errors = ActionErrors.of(context);
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await ref.read(devicePrefsProvider.notifier).startLocalProfile(name);
    } catch (e) {
      // Not stored: local mode works for this run, but would be gone after a
      // restart — say so (G15).
      errors.show(e);
    }
    if (mounted) setState(() => _busy = false);
    // The router moves on (onboarding / groups) once the profile is set.
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final adoptedInto = ref.watch(
      devicePrefsProvider.select((p) => p.value?.lastAdoptedInto),
    );
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: Insets.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: Insets.l),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(l.welcomeUseLocal),
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Insets.xl),
          child: ContentWidth(
            maxWidth: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                point(Icons.phone_android_outlined, l.localSetupStaysHere),
                point(Icons.person_outline, l.localSetupPeople),
                point(Icons.backup_outlined, l.localSetupBackup),
                point(Icons.link, l.localSetupConnectLater),
                if (adoptedInto != null)
                  Card(
                    key: const Key('localSetupAdoptedNotice'),
                    color: scheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(Insets.l),
                      child: Text(
                        l.localSetupAdoptedNotice(adoptedInto),
                        style: TextStyle(color: scheme.onSecondaryContainer),
                      ),
                    ),
                  ),
                const SizedBox(height: Insets.l),
                TextField(
                  key: const Key('localNameField'),
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _start(),
                  decoration: InputDecoration(
                    labelText: l.localSetupNameLabel,
                    helperText: l.localSetupNameHelper,
                    errorText: _error,
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: Insets.xl),
                FilledButton(
                  key: const Key('localStartBtn'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _busy ? null : _start,
                  child: Text(l.localSetupStart),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
