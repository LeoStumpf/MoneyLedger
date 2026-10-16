import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/content_width.dart';
import 'onboarding_provider.dart';

/// One-time, first-run intro to MoneyLedger's decentralized model. Shown once
/// (gated by the `onboarding_seen` flag); "Get started" marks it seen and routes
/// to the groups list.
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  static List<(IconData, String, String)> _points(AppLocalizations l) => [
    (
      Icons.phone_android_outlined,
      l.onboardingLocalTitle,
      l.onboardingLocalBody,
    ),
    (Icons.lock_outline, l.onboardingSyncTitle, l.onboardingSyncBody),
    (Icons.group_add_outlined, l.onboardingAddTitle, l.onboardingAddBody),
  ];

  Future<void> _getStarted(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      await ref.read(onboardingControllerProvider.notifier).markSeen();
    } catch (e) {
      // The flag couldn't be stored (DB error): say so instead of a dead
      // button (G15). The user can retry.
      messenger.showSnackBar(
        SnackBar(content: Text(l.failedWithError(e.toString()))),
      );
      return;
    }
    if (context.mounted) context.go('/groups');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // G17: one designed page — logo hero, three feature cards, and the
    // button pinned below the scrollable content.
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Insets.xl,
                  Insets.xxl,
                  Insets.xl,
                  Insets.l,
                ),
                child: ContentWidth(
                  maxWidth: 520,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: BrandLogo(size: 96)),
                      const SizedBox(height: Insets.xl),
                      Text(
                        l.onboardingWelcome,
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Insets.s),
                      Text(
                        l.onboardingTagline,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Insets.xxl),
                      for (final (icon, title, body) in _points(l))
                        Padding(
                          padding: const EdgeInsets.only(bottom: Insets.m),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(Insets.l),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: scheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(
                                        Radii.m,
                                      ),
                                    ),
                                    child: Icon(
                                      icon,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(width: Insets.l),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: Insets.xs),
                                        Text(
                                          body,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.xl,
                Insets.s,
                Insets.xl,
                Insets.l,
              ),
              child: ContentWidth(
                maxWidth: 520,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('getStartedBtn'),
                    onPressed: () => _getStarted(context, ref),
                    child: Text(l.getStarted),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
