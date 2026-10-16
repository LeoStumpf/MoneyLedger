import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A friendly empty / status screen (G17): a tinted icon medallion, a title,
/// an explanation and optional action buttons, centred and scrollable.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actions = const [],
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String? body;
  final List<Widget> actions;

  /// Shows a progress ring around the medallion (e.g. "Restoring…").
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.primaryContainer,
                            scheme.secondaryContainer,
                          ],
                        ),
                      ),
                      child: Icon(icon,
                          size: 48, color: scheme.onPrimaryContainer),
                    ),
                    if (busy)
                      const SizedBox(
                        width: 112,
                        height: 112,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.xl),
              Text(title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge),
              if (body != null) ...[
                const SizedBox(height: Insets.s),
                Text(body!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: Insets.xl),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: Insets.m,
                  runSpacing: Insets.m,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
