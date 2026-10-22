import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/action_error.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n.dart';
import '../../core/router.dart' show kLocalSetupLocation;
import '../../core/session/device_prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/content_width.dart';
import '../about/about_page.dart' show kSourceCodeUrl;
import 'why_matrix_page.dart' show kWhyMatrixLocation;
import '../../core/widgets/large_text.dart';

/// The explanation pages of the welcome, in order. G54 (design doc §10.3):
/// link groups are the default, Matrix the secure upgrade — the former
/// "What is Matrix?" and "Who sees what" pages are merged into [link] and
/// [matrix].
enum WelcomeTopic {
  /// What MoneyLedger does (Splitwise / Tricount-style).
  intro,

  /// Free, open source, no MoneyLedger server.
  openSource,

  /// Share a group with an invite link (relays, encrypted, anyone with the
  /// link).
  link,

  /// "Want more security? Matrix" — what Matrix is, who sees what; links
  /// the "Why Matrix?" page.
  matrix;

  static WelcomeTopic fromName(String? name) => values.firstWhere(
    (t) => t.name == name,
    orElse: () => WelcomeTopic.intro,
  );
}

/// G39: the first-open welcome — explains the app *before* any login, then
/// offers the ways in. G54 (design doc §10.3): *Start without an account*
/// (G40) first, then *Join with an invite link*, then sign in / create a
/// Matrix account under "Secure mode". Choosing any of them marks the
/// device-wide "welcome seen" flag.
///
/// With [revisit] the same explanation is shown again (About → "How
/// MoneyLedger works", login page → "What is Matrix?"): no choices, a back
/// button, and it can open at [initialTopic].
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({
    super.key,
    this.revisit = false,
    this.initialTopic = WelcomeTopic.intro,
    this.startAtChoices = false,
  });

  final bool revisit;
  final WelcomeTopic initialTopic;

  /// G46: open on the choices page (the explanation was read before — e.g.
  /// after *Delete local data*); the pages stay a swipe away. Ignored with
  /// [revisit].
  final bool startAtChoices;

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  late final int _initialPage = widget.startAtChoices && !widget.revisit
      ? WelcomeTopic.values.length
      : widget.initialTopic.index;
  late final PageController _pages = PageController(initialPage: _initialPage);
  late int _page = _initialPage;

  /// Explanation pages + (first open only) the choices page.
  int get _count => WelcomeTopic.values.length + (widget.revisit ? 0 : 1);
  bool get _onLast => _page == _count - 1;

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

  void _next() {
    if (_onLast) {
      _close();
    } else {
      _goTo(_page + 1);
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  /// One of the three choices: remember the welcome, then go on. *Start
  /// without an account* doesn't: the local setup page stores it together
  /// with the name (`startLocalProfile`) — a seen welcome without a local
  /// profile would build the Matrix client (and create its SDK store) while
  /// the name is still being typed (G79).
  Future<void> _choose(String location) async {
    if (location == kLocalSetupLocation) {
      context.go(location);
      return;
    }
    final errors = ActionErrors.of(context);
    try {
      await ref.read(devicePrefsProvider.notifier).markWelcomeSeen();
    } catch (e) {
      // Not stored (the welcome shows again next start) — go on anyway.
      errors.show(e);
    }
    if (mounted) context.go(location);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final topics = WelcomeTopic.values;
    return Scaffold(
      appBar: widget.revisit
          ? AppBar(title: AppBarTitle(l.howItWorksTitle))
          : AppBar(
              automaticallyImplyLeading: false,
              actions: [
                if (!_onLast)
                  TextButton(
                    key: const Key('welcomeSkip'),
                    onPressed: () => _goTo(_count - 1),
                    child: Text(l.welcomeSkip),
                  ),
              ],
            ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: PageView(
                key: const Key('welcomePages'),
                controller: _pages,
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  for (final t in topics) _TopicPage(topic: t),
                  if (!widget.revisit) _ChoicesPage(onChoose: _choose),
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
                              key: const Key('welcomeBack'),
                              onPressed: () => _goTo(_page - 1),
                              child: Text(l.welcomeBack),
                            ),
                          if (!_onLast || widget.revisit) ...[
                            FilledButton(
                              key: const Key('welcomeNext'),
                              onPressed: _next,
                              child: Text(
                                _onLast ? l.welcomeDone : l.welcomeNext,
                              ),
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

/// One explanation page: illustration, title, body (+ extras).
class _TopicPage extends StatelessWidget {
  const _TopicPage({required this.topic});

  final WelcomeTopic topic;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (hero, title, body) = switch (topic) {
      WelcomeTopic.intro => (
        const WelcomeHero(
          center: BrandLogo(size: 96),
          satellites: [
            Icons.restaurant_outlined,
            Icons.flight_takeoff_outlined,
            Icons.home_outlined,
          ],
        ),
        l.welcomeIntroTitle,
        l.welcomeIntroBody,
      ),
      WelcomeTopic.openSource => (
        const WelcomeHero(
          center: Icon(Icons.code, size: 64),
          satellites: [
            Icons.volunteer_activism_outlined,
            Icons.phone_android_outlined,
            Icons.cloud_off_outlined,
          ],
        ),
        l.welcomeOpenTitle,
        l.welcomeOpenBody,
      ),
      WelcomeTopic.link => (
        const WelcomeHero(
          center: Icon(Icons.link, size: 64),
          satellites: [
            Icons.chat_outlined,
            Icons.lock_outline,
            Icons.groups_outlined,
          ],
        ),
        l.welcomeLinkTitle,
        l.welcomeLinkBody,
      ),
      WelcomeTopic.matrix => (
        const WelcomeHero(
          center: Icon(Icons.verified_user_outlined, size: 64),
          satellites: [
            Icons.dns_outlined,
            Icons.alternate_email,
            Icons.devices_outlined,
          ],
        ),
        l.welcomeSecureTitle,
        l.welcomeSecureBody,
      ),
    };
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SingleChildScrollView(
      key: Key('welcomeTopic-${topic.name}'),
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
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.m),
            Text(body, style: muted, textAlign: TextAlign.center),
            if (topic == WelcomeTopic.openSource) ...[
              const SizedBox(height: Insets.l),
              Center(
                child: TextButton.icon(
                  key: const Key('welcomeSourceLink'),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l.welcomeSourceLink),
                  onPressed: () => launchUrl(
                    Uri.parse(kSourceCodeUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
            ],
            if (topic == WelcomeTopic.link || topic == WelcomeTopic.matrix)
              const SizedBox(height: Insets.l),
            for (final (icon, text) in switch (topic) {
              WelcomeTopic.link => [
                (Icons.lock_outline, l.welcomeLinkEncrypted),
                (Icons.visibility_outlined, l.welcomeLinkRelays),
                (Icons.link, l.welcomeLinkAnyone),
              ],
              WelcomeTopic.matrix => [
                (Icons.groups_outlined, l.welcomeSecureMembers),
                (Icons.dns_outlined, l.welcomePrivacyServer),
                (Icons.visibility_off_outlined, l.welcomePrivacyNothingElse),
              ],
              _ => const <(IconData, String)>[],
            })
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.l),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: Insets.l),
                    Expanded(
                      child: Text(text, style: theme.textTheme.bodyLarge),
                    ),
                  ],
                ),
              ),
            // G54: the calm comparison page (design doc §10.2).
            if (topic == WelcomeTopic.matrix)
              Center(
                child: TextButton.icon(
                  key: const Key('welcomeWhyMatrix'),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(l.whyMatrixTitle),
                  onPressed: () => context.push(kWhyMatrixLocation),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The last page of the first-open welcome: the ways in (G54 order).
class _ChoicesPage extends StatelessWidget {
  const _ChoicesPage({required this.onChoose});

  final Future<void> Function(String location) onChoose;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    const big = Size.fromHeight(52);
    return SingleChildScrollView(
      key: const Key('welcomeChoices'),
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
            Text(
              l.welcomeStartTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.m),
            Text(
              l.welcomeStartBody,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.xxl),
            // G54 (design doc §10.3): no account first, then the invite
            // link, then Matrix as the secure mode.
            FilledButton.icon(
              key: const Key('welcomeUseLocal'),
              style: FilledButton.styleFrom(minimumSize: big),
              icon: const Icon(Icons.arrow_forward),
              label: Text(l.welcomeUseLocal),
              onPressed: () => onChoose(kLocalSetupLocation),
            ),
            const SizedBox(height: Insets.s),
            Text(
              l.welcomeUseLocalHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.l),
            // G52 step 7: someone sent an invite link. The join itself marks
            // the welcome seen (and an opened link goes to /join directly).
            OutlinedButton.icon(
              key: const Key('welcomeJoinLink'),
              style: OutlinedButton.styleFrom(minimumSize: big),
              icon: const Icon(Icons.link),
              label: Text(l.joinLinkEntry),
              onPressed: () => context.push('/join'),
            ),
            const SizedBox(height: Insets.xxl),
            Semantics(
              header: true,
              child: Text(
                l.welcomeSecureHeading,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: Insets.xs),
            Text(
              l.welcomeSecureHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.m),
            FilledButton.tonalIcon(
              key: const Key('welcomeSignIn'),
              style: FilledButton.styleFrom(minimumSize: big),
              icon: const Icon(Icons.login),
              label: Text(l.welcomeSignIn),
              onPressed: () => onChoose('/login'),
            ),
            const SizedBox(height: Insets.s),
            TextButton.icon(
              key: const Key('welcomeCreateAccount'),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.person_add_alt_outlined),
              label: Text(l.welcomeCreateAccount),
              onPressed: () => onChoose('/register'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page illustration: the brand logo or a Material icon in a large soft
/// circle, with three small "satellite" icons around it.
class WelcomeHero extends StatelessWidget {
  const WelcomeHero({
    super.key,
    required this.center,
    required this.satellites,
  });

  final Widget center;
  final List<IconData> satellites;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = 200.0;
    const sat = 52.0;
    Widget satellite(IconData icon) => Container(
      width: sat,
      height: sat,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 3),
      ),
      child: Icon(icon, size: 26, color: scheme.onSecondaryContainer),
    );
    final positions = [
      const Offset(4, 18),
      const Offset(size - sat - 4, 6),
      const Offset(size - sat - 18, size - sat - 2),
    ];
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primaryContainer,
                        scheme.primaryContainer.withValues(alpha: 0.45),
                      ],
                    ),
                  ),
                  child: Center(
                    child: IconTheme(
                      data: IconThemeData(color: scheme.onPrimaryContainer),
                      child: center,
                    ),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < satellites.length && i < 3; i++)
              Positioned(
                left: positions[i].dx,
                top: positions[i].dy,
                child: satellite(satellites[i]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Page indicator dots (tappable).
class WelcomeDots extends StatelessWidget {
  const WelcomeDots({
    super.key,
    required this.count,
    required this.current,
    required this.onTap,
  });

  final int count;
  final int current;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // G54 (G71): the dots are a visual shortcut only — screen readers hear
    // "page x of y" and use Back / Next (each dot is far below 48 dp).
    return Semantics(
      label: context.l10n.welcomePageOf(current + 1, count),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              GestureDetector(
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == current ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == current
                        ? scheme.primary
                        : scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
