import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'onboarding_provider.dart';

/// One-time, first-run intro to MoneyLedger's decentralized model. Shown once
/// (gated by the `onboarding_seen` flag); "Get started" marks it seen and routes
/// to the groups list.
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  static const _points = [
    (
      Icons.devices,
      'Your data lives on your device',
      'Groups, expenses and balances are stored locally — there is no central '
          'MoneyLedger server holding your finances.'
    ),
    (
      Icons.sync,
      'Members sync peer-to-peer',
      'Changes are shared directly between members over end-to-end-encrypted '
          'Matrix messages. The homeserver only relays ciphertext. Devices '
          'sync while the app runs and, on Android, periodically in the '
          'background.'
    ),
    (
      Icons.group_add,
      'Add anyone — Matrix or not',
      'Invite people by their Matrix ID, or add local participants by name and '
          'link an account later.'
    ),
  ];

  Future<void> _getStarted(BuildContext context, WidgetRef ref) async {
    await ref.read(onboardingControllerProvider.notifier).markSeen();
    if (context.mounted) context.go('/groups');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  const Icon(Icons.account_balance_wallet,
                      size: 56, color: Colors.teal),
                  const SizedBox(height: 16),
                  Text('Welcome to MoneyLedger',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text('Split expenses without a middleman.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  for (final (icon, title, body) in _points)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: Colors.teal),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 4),
                                Text(body,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('getStartedBtn'),
                    onPressed: () => _getStarted(context, ref),
                    child: const Text('Get started'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
