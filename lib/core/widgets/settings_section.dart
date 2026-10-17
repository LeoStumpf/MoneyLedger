import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// G65: the small caps-style heading above a group of settings tiles (app
/// settings page, group settings page). [danger] colours it with the
/// scheme's error colour (leave / delete).
class SettingsSectionHeader extends StatelessWidget {
  final String text;
  final bool danger;
  const SettingsSectionHeader(this.text, {super.key, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.page,
        Insets.xl,
        Insets.page,
        Insets.xs,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: danger ? scheme.error : scheme.secondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}
