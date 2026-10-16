import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n.dart';

part 'about_page.g.dart';

/// Where the app's source code lives (AGPL-3.0 §13: offer the source).
const kSourceCodeUrl = 'https://github.com/LeoStumpf/MoneyLedger';

/// The app's license (G21).
const kAppLicense = 'AGPL-3.0';

/// The app version (`1.0.0+1` style) from the platform; tests override it.
@riverpod
Future<String> appVersion(Ref ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.buildNumber.isEmpty
      ? info.version
      : '${info.version}+${info.buildNumber}';
}

/// About MoneyLedger (G12): name, version, description, source code link,
/// license, the open-source licenses page and the privacy policy.
/// Reachable signed in (settings sheet) and signed out (login page).
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          const Icon(Icons.account_balance_wallet,
              size: 56, color: Colors.teal),
          const SizedBox(height: 12),
          Text(l.appTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall),
          if (version != null)
            Text(l.aboutVersion(version),
                key: const Key('aboutVersion'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Text(l.aboutDescription,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l.aboutSourceCode),
            subtitle: const Text(kSourceCodeUrl),
            trailing: const Icon(Icons.open_in_new),
            // External browser (a new tab on web — not the SSO same-tab redirect).
            onTap: () => launchUrl(Uri.parse(kSourceCodeUrl),
                mode: LaunchMode.externalApplication),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(l.aboutLicense),
            subtitle: Text(l.aboutLicenseValue(kAppLicense)),
          ),
          ListTile(
            key: const Key('openSourceLicensesTile'),
            leading: const Icon(Icons.description_outlined),
            title: Text(l.aboutOpenSourceLicenses),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l.appTitle,
              applicationVersion: version,
              applicationIcon: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.account_balance_wallet,
                    size: 48, color: Colors.teal),
              ),
              applicationLegalese: l.aboutLegalese(kAppLicense),
            ),
          ),
          ListTile(
            key: const Key('privacyPolicyTile'),
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l.privacyPolicyTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/about/privacy'),
          ),
        ],
      ),
    );
  }
}

/// The in-app privacy policy — the same content as `PRIVACY.md` (keep the
/// two in sync), localized via the ARB files.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  /// Date of the policy text (also in PRIVACY.md).
  static final lastUpdated = DateTime(2026, 10, 16);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final sections = [
      (l.privacyLedgerTitle, l.privacyLedgerBody),
      (l.privacyHomeserverTitle, l.privacyHomeserverBody),
      (l.privacyNoTrackingTitle, l.privacyNoTrackingBody),
      (l.privacyBackgroundTitle, l.privacyBackgroundBody),
      (l.privacyCsvTitle, l.privacyCsvBody),
      (l.privacyBackupTitle, l.privacyBackupBody),
      (l.privacyDeleteTitle, l.privacyDeleteBody),
      (l.privacyContactTitle, l.privacyContactBody),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l.privacyPolicyTitle)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(l.privacyLastUpdated(
                context.date(lastUpdated.millisecondsSinceEpoch)),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(l.privacyIntro, style: theme.textTheme.bodyMedium),
            for (final (title, body) in sections) ...[
              const SizedBox(height: 20),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(body, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
