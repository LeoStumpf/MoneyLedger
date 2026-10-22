import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/session/app_session.dart';
import '../../core/session/device_prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/action_error.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/large_text.dart';
import '../local/local_mode_ui.dart' show startConnectAccount;
import 'welcome_page.dart' show WelcomeDots, WelcomeHero;

/// G54: the "Why Matrix?" page — a public route (welcome, How it works, a
/// link group's ⋮, the groups-page hint).
const kWhyMatrixLocation = '/why-matrix';

/// What the last page of [WhyMatrixPage] offers — derived from the session.
enum WhyMatrixOffer {
  /// No account (local mode): *Connect a Matrix account* / *Not now*.
  connect,

  /// Signed out (welcome): *Sign in with Matrix* / *Create a Matrix
  /// account* / *Not now*.
  signIn,

  /// Already on Matrix: what to do in a link group; *Done*.
  signedIn,

  /// Read only (opened from a flow that must not be left, e.g. the link
  /// disclosure before a join): "later in the settings"; *Done*.
  later,
}

/// Pure: which offer the last page makes.
WhyMatrixOffer whyMatrixOffer(AppSessionKind session, {bool infoOnly = false}) {
  if (session == AppSessionKind.matrix) return WhyMatrixOffer.signedIn;
  if (infoOnly) return WhyMatrixOffer.later;
  return switch (session) {
    AppSessionKind.local => WhyMatrixOffer.connect,
    AppSessionKind.signedOut => WhyMatrixOffer.signIn,
    _ => WhyMatrixOffer.later,
  };
}

/// G54 (design doc §10.2 / §10.3): a calm explanation of the secure mode in
/// the welcome's style — "there's another mode, also free, and it works even
/// better: you just sign in". Three swipe pages: links are easy · what
/// Matrix does better (plain sentences, link vs. Matrix) · ready when you
/// are (the action fits the session, [whyMatrixOffer]). Never a nag: it is
/// only opened by the user (or once from the dismissible groups-page hint).
///
/// [infoOnly]: opened on top of a flow (the link disclosure) — no action
/// that leaves it; the last page only closes.
class WhyMatrixPage extends ConsumerStatefulWidget {
  const WhyMatrixPage({super.key, this.infoOnly = false});

  final bool infoOnly;

  @override
  ConsumerState<WhyMatrixPage> createState() => _WhyMatrixPageState();
}

class _WhyMatrixPageState extends ConsumerState<WhyMatrixPage> {
  static const _count = 3;
  final PageController _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int page) => _pages.animateToPage(
    page,
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
  );

  void _close() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      context.go('/groups');
    }
  }

  Future<void> _connect() async {
    await startConnectAccount(context, ref);
    // This page is public, so the router keeps it while connecting — go to
    // the login page ourselves.
    if (mounted) context.go('/login');
  }

  Future<void> _signIn(String location) async {
    final errors = ActionErrors.of(context);
    try {
      await ref.read(devicePrefsProvider.notifier).markWelcomeSeen();
    } catch (e) {
      errors.show(e);
    }
    if (mounted) context.go(location);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final offer = whyMatrixOffer(
      ref.watch(appSessionProvider),
      infoOnly: widget.infoOnly,
    );
    final onLast = _page == _count - 1;
    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l.whyMatrixTitle)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: PageView(
                key: const Key('whyMatrixPages'),
                controller: _pages,
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  _InfoPage(
                    key: const Key('whyMatrixEasy'),
                    hero: const WelcomeHero(
                      center: Icon(Icons.link, size: 64),
                      satellites: [
                        Icons.chat_outlined,
                        Icons.qr_code_2,
                        Icons.groups_outlined,
                      ],
                    ),
                    title: l.whyMatrixEasyTitle,
                    body: l.whyMatrixEasyBody,
                  ),
                  _InfoPage(
                    key: const Key('whyMatrixCompare'),
                    hero: const WelcomeHero(
                      center: Icon(Icons.verified_user_outlined, size: 64),
                      satellites: [
                        Icons.lock_outline,
                        Icons.person_remove_outlined,
                        Icons.phone_android_outlined,
                      ],
                    ),
                    title: l.whyMatrixCompareTitle,
                    body: l.whyMatrixCompareBody,
                    rows: [
                      (
                        Icons.lock_outline,
                        l.whyMatrixWhoTitle,
                        l.whyMatrixWhoLink,
                        l.whyMatrixWhoMatrix,
                      ),
                      (
                        Icons.person_remove_outlined,
                        l.whyMatrixRemoveTitle,
                        l.whyMatrixRemoveLink,
                        l.whyMatrixRemoveMatrix,
                      ),
                      (
                        Icons.phone_android_outlined,
                        l.whyMatrixPhoneTitle,
                        l.whyMatrixPhoneLink,
                        l.whyMatrixPhoneMatrix,
                      ),
                      (
                        Icons.dns_outlined,
                        l.whyMatrixServersTitle,
                        l.whyMatrixServersLink,
                        l.whyMatrixServersMatrix,
                      ),
                    ],
                  ),
                  _ReadyPage(
                    offer: offer,
                    onConnect: _connect,
                    onSignIn: () => _signIn('/login'),
                    onCreateAccount: () => _signIn('/register'),
                    onClose: _close,
                  ),
                ],
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
                child: Row(
                  children: [
                    WelcomeDots(count: _count, current: _page, onTap: _goTo),
                    const SizedBox(width: Insets.s),
                    // At a large font size the buttons wrap instead of
                    // overflowing (360 dp, 200 %).
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: Insets.s,
                        runSpacing: Insets.xs,
                        children: [
                          if (_page > 0)
                            TextButton(
                              key: const Key('whyMatrixBack'),
                              onPressed: () => _goTo(_page - 1),
                              child: Text(l.welcomeBack),
                            ),
                          if (!onLast) ...[
                            FilledButton(
                              key: const Key('whyMatrixNext'),
                              onPressed: () => _goTo(_page + 1),
                              child: Text(l.welcomeNext),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One explanation page: illustration, title, body and optional
/// "link vs. Matrix" rows (icon, topic, with a link, with Matrix).
class _InfoPage extends StatelessWidget {
  const _InfoPage({
    super.key,
    required this.hero,
    required this.title,
    required this.body,
    this.rows = const [],
  });

  final Widget hero;
  final String title;
  final String body;
  final List<(IconData, String, String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Insets.xl,
        Insets.l,
        Insets.xl,
        Insets.l,
      ),
      child: ContentWidth(
        maxWidth: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: hero),
            const SizedBox(height: Insets.xxl),
            Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: Insets.m),
            Text(
              body,
              style: theme.textTheme.bodyLarge?.copyWith(color: muted),
              textAlign: TextAlign.center,
            ),
            if (rows.isNotEmpty) const SizedBox(height: Insets.xl),
            for (final (icon, topic, link, matrix) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.l),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: Insets.l),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topic,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: Insets.xs),
                          Text(
                            l.whyMatrixWithLink(link),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: muted,
                            ),
                          ),
                          const SizedBox(height: Insets.xs),
                          Text(
                            l.whyMatrixWithMatrix(matrix),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The last page: "Ready when you are" with the action that fits [offer].
class _ReadyPage extends StatelessWidget {
  const _ReadyPage({
    required this.offer,
    required this.onConnect,
    required this.onSignIn,
    required this.onCreateAccount,
    required this.onClose,
  });

  final WhyMatrixOffer offer;
  final VoidCallback onConnect;
  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    const big = Size.fromHeight(52);
    final body = switch (offer) {
      WhyMatrixOffer.connect => l.whyMatrixReadyConnectBody,
      WhyMatrixOffer.signIn => l.whyMatrixReadySignInBody,
      WhyMatrixOffer.signedIn => l.whyMatrixReadySignedInBody,
      WhyMatrixOffer.later => l.whyMatrixReadyLaterBody,
    };
    final notNow = TextButton(
      key: const Key('whyMatrixNotNow'),
      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: onClose,
      child: Text(l.whyMatrixNotNow),
    );
    return SingleChildScrollView(
      key: const Key('whyMatrixReady'),
      padding: const EdgeInsets.fromLTRB(
        Insets.xl,
        Insets.l,
        Insets.xl,
        Insets.l,
      ),
      child: ContentWidth(
        maxWidth: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: BrandLogo(size: 88)),
            const SizedBox(height: Insets.xl),
            Semantics(
              header: true,
              child: Text(
                l.whyMatrixReadyTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: Insets.m),
            Text(
              body,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.xxl),
            ...switch (offer) {
              WhyMatrixOffer.connect => [
                FilledButton.icon(
                  key: const Key('whyMatrixConnect'),
                  style: FilledButton.styleFrom(minimumSize: big),
                  icon: const Icon(Icons.login),
                  label: Text(l.connectMatrixAccount),
                  onPressed: onConnect,
                ),
                const SizedBox(height: Insets.s),
                notNow,
              ],
              WhyMatrixOffer.signIn => [
                FilledButton.icon(
                  key: const Key('whyMatrixSignIn'),
                  style: FilledButton.styleFrom(minimumSize: big),
                  icon: const Icon(Icons.login),
                  label: Text(l.welcomeSignIn),
                  onPressed: onSignIn,
                ),
                const SizedBox(height: Insets.m),
                OutlinedButton.icon(
                  key: const Key('whyMatrixCreateAccount'),
                  style: OutlinedButton.styleFrom(minimumSize: big),
                  icon: const Icon(Icons.person_add_alt_outlined),
                  label: Text(l.welcomeCreateAccount),
                  onPressed: onCreateAccount,
                ),
                const SizedBox(height: Insets.s),
                notNow,
              ],
              WhyMatrixOffer.signedIn || WhyMatrixOffer.later => [
                FilledButton(
                  key: const Key('whyMatrixDone'),
                  style: FilledButton.styleFrom(minimumSize: big),
                  onPressed: onClose,
                  child: Text(l.welcomeDone),
                ),
              ],
            },
          ],
        ),
      ),
    );
  }
}
