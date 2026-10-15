import 'package:flutter/material.dart';

import 'auth_errors.dart';

/// Inline, friendly auth error (G20): a title + hint, with the raw technical
/// text only behind a collapsed "Details" expansion.
class AuthErrorCard extends StatelessWidget {
  final AuthErrorMessage message;
  const AuthErrorCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final detail = message.detail;
    return Card(
      key: const Key('authErrorCard'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message.title,
                          style: text.titleSmall
                              ?.copyWith(color: scheme.onErrorContainer)),
                      if (message.hint != null) ...[
                        const SizedBox(height: 4),
                        Text(message.hint!,
                            style: text.bodyMedium
                                ?.copyWith(color: scheme.onErrorContainer)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (detail != null && detail.isNotEmpty)
              Theme(
                // No divider lines around the expansion inside the card.
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: const Key('authErrorDetails'),
                  tilePadding: const EdgeInsets.only(left: 36, right: 8),
                  childrenPadding:
                      const EdgeInsets.only(left: 36, right: 8, bottom: 8),
                  dense: true,
                  expandedAlignment: Alignment.centerLeft,
                  title: Text(AuthErrorStrings.detailsLabel,
                      style: text.labelLarge
                          ?.copyWith(color: scheme.onErrorContainer)),
                  iconColor: scheme.onErrorContainer,
                  collapsedIconColor: scheme.onErrorContainer,
                  children: [
                    SelectableText(detail,
                        style: text.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: scheme.onErrorContainer)),
                  ],
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
