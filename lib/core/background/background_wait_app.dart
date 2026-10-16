import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Shown at app start while a background sync round (G31) in this process
/// finishes and closes its stores (G18 review): the app must not open the
/// same Matrix store / ledger DB in parallel, so it waits — visibly — instead
/// of showing a blank screen. Replaced by the real app via `runApp`.
class BackgroundSyncWaitApp extends StatelessWidget {
  const BackgroundSyncWaitApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.system,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: Insets.l),
              Text(
                context.l10n.finishingBackgroundSync,
                key: const Key('finishingBackgroundSync'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
