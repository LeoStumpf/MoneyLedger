import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/l10n.dart';
import '../../core/router.dart' show kHowItWorksLocation, kLocalSetupLocation;
import '../../core/session/app_session.dart';
import '../local/local_mode_ui.dart' show cancelConnectAccount;
import '../welcome/welcome_page.dart' show WelcomeTopic;
import '../../core/platform/url_helper.dart';
import '../../models/login_flows_result.dart';
import 'auth_error_card.dart';
import 'auth_errors.dart';
import 'auth_provider.dart';
import 'sso_callback.dart';
import 'sso_provider.dart';
import '../../core/widgets/brand_logo.dart';
import 'sso_url.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverCtrl = TextEditingController(text: 'matrix.org');
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  /// The last sign-in failure, shown inline as a friendly card (G20).
  AuthErrorMessage? _error;

  /// G43: the server whose login flows are looked up — **null until the user
  /// acts** (edits / submits the server field, taps *Check server*, *Sign in*
  /// or SSO). Opening the page must not contact any homeserver (not even the
  /// prefilled matrix.org): until then the form is the optimistic one.
  String? _lookupInput;

  /// The user typed in the server field (a tap outside it then confirms it).
  bool _serverEdited = false;

  /// *Sign in* / SSO is waiting for the server's login flows.
  bool _resolving = false;
  Timer? _debounce;

  /// The server as entered (trimmed; the prefill if the field is empty).
  String get _enteredServer {
    final t = _serverCtrl.text.trim();
    return t.isEmpty ? 'matrix.org' : t;
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleSsoCallback());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _serverCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── SSO callback handling ────────────────────────────────────────────────

  /// Web: the SSO redirect returns to the page with `?loginToken=…` params.
  Future<void> _handleSsoCallback() async {
    final params = currentUrlParams;
    final token = params['loginToken'];
    if (token == null || token.isEmpty) return;
    final rawHs = params['hs'] ?? _serverCtrl.text.trim();
    clearUrlParams();
    await _exchangeToken(token, rawHs);
  }

  /// Native: the SSO redirect returns as a `moneyledger://sso-callback` deep link.
  void _onSsoCallbackUri(Uri uri) {
    debugPrint('[sso] callback uri received: ${redactSsoUri(uri)}');
    final cb = parseSsoCallback(uri);
    if (cb == null) {
      debugPrint('[sso] no loginToken in callback uri — ignoring');
      return;
    }
    _exchangeToken(cb.loginToken, cb.homeserver ?? _serverCtrl.text.trim());
  }

  /// Guards against exchanging the same single-use token twice (the deep link
  /// can be delivered via both the initial intent and the link stream).
  String? _exchangingToken;

  /// Exchanges an SSO login token for a session (shared by web + native).
  Future<void> _exchangeToken(String token, String rawHs) async {
    if (_exchangingToken == token) return;
    _exchangingToken = token;
    // loginWithToken -> checkHomeserver does its own .well-known resolution, so
    // pass the homeserver hint directly. Don't re-read loginFlowsProvider here:
    // [rawHs] is a different autoDispose family key than the one the page
    // watches, so with no listener it gets disposed mid-load and throws
    // "provider … disposed during loading state".
    final hs = rawHs.startsWith('http') ? rawHs : 'https://$rawHs';
    debugPrint('[sso] exchanging token (len=${token.length}) on hs=$hs');
    if (mounted) setState(() => _error = null);

    await ref
        .read(authProvider.notifier)
        .loginWithToken(resolvedHomeserver: hs, token: token);

    if (!mounted) return;
    final err = ref.read(authProvider).error;
    debugPrint('[sso] token exchange done; error=$err');
    if (err != null) {
      _exchangingToken = null; // allow a retry after a failed exchange
      setState(() => _error = describeAuthError(err, action: AuthAction.sso));
    } else {
      context.go('/groups');
    }
  }

  // ── Homeserver / login-flows ─────────────────────────────────────────────

  /// The user edited the server (typed, or a Matrix ID in the username
  /// field filled it in): look its flows up once typing pauses.
  void _scheduleFlowsLookup(String input) {
    _serverEdited = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final trimmed = input.trim();
      if (trimmed.isNotEmpty && trimmed != _lookupInput) {
        setState(() => _lookupInput = trimmed);
      }
    });
  }

  /// The user confirmed the server (Enter, *Check server*, or leaving the
  /// field after editing it): look its flows up now.
  void _commitServerInput({bool explicit = true}) {
    if (!explicit && !_serverEdited) return; // just focused, nothing typed
    _debounce?.cancel();
    final server = _enteredServer;
    if (server != _lookupInput) setState(() => _lookupInput = server);
  }

  /// The login flows of the entered server — looks them up now if needed
  /// (the user tapped *Sign in* / SSO). Null when the lookup failed.
  Future<LoginFlowsResult?> _flowsForEnteredServer() async {
    _commitServerInput();
    final input = _lookupInput!;
    setState(() => _resolving = true);
    try {
      // Let build() watch this key first: the provider is autoDispose, a
      // bare read would start (and drop) a lookup of its own.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;
      return await ref.read(loginFlowsProvider(input).future);
    } catch (_) {
      return null;
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  static String _asUrl(String input) =>
      input.startsWith('http') ? input : 'https://${input.trim()}';

  /// If the username looks like a Matrix ID, auto-fill the server field.
  void _onUsernameChanged(String value) {
    final match = RegExp(r'^@[^:]+:(.+)$').firstMatch(value.trim());
    if (match == null) return;
    final domain = match.group(1)!;
    if (_serverCtrl.text != domain) {
      _serverCtrl.text = domain;
      _scheduleFlowsLookup(domain);
    }
  }

  // ── SSO redirect ─────────────────────────────────────────────────────────

  Future<void> _startSso({String? providerId}) async {
    // Resolve the homeserver (.well-known) before redirecting. Uses the cached
    // loginFlows result if discovery already settled; otherwise looks it up
    // now (G43: the page doesn't before the user acts).
    var resolvedUrl = _asUrl(_enteredServer);
    final r = await _flowsForEnteredServer();
    if (!mounted) return;
    // Discovery failed — fall back to the entered homeserver as-is.
    if (r != null && r.resolvedUrl.isNotEmpty) resolvedUrl = r.resolvedUrl;

    final hsUri = Uri.tryParse(resolvedUrl);
    if (hsUri == null) return;

    final callbackBase = kIsWeb
        ? Uri.base.origin
        : 'moneyledger://sso-callback';
    final callbackUrl = '$callbackBase/?hs=${Uri.encodeComponent(resolvedUrl)}';

    final ssoUrl = buildSsoRedirectUrl(
      homeserver: resolvedUrl,
      callbackUrl: callbackUrl,
      providerId: providerId,
    );

    // Web redirects the current tab; native opens the system browser. Either
    // way the homeserver sends the user back to [callbackUrl], handled by
    // _handleSsoCallback (web) or _onSsoCallbackUri (native deep link).
    await launchExternalUrl(ssoUrl);
  }

  // ── Password submit ───────────────────────────────────────────────────────

  Future<void> _submitPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    // G43: the flows are looked up only now if the user didn't confirm the
    // server before. A server without password login → the form refines to
    // its SSO buttons instead of a doomed attempt.
    final flows = await _flowsForEnteredServer();
    if (!mounted) return;
    if (flows != null && !flows.hasPassword && flows.hasSso) return;
    final resolvedHomeserver = flows != null && flows.resolvedUrl.isNotEmpty
        ? flows.resolvedUrl
        : _asUrl(_lookupInput!);
    await ref
        .read(authProvider.notifier)
        .login(
          resolvedHomeserver: resolvedHomeserver,
          username: _usernameCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
    if (!mounted) return;
    final err = ref.read(authProvider).error;
    if (err != null) {
      setState(() => _error = describeAuthError(err));
    } else {
      context.go('/groups');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Native SSO returns via deep link; web uses page params (see initState).
    ref.listen(ssoCallbackProvider, (_, next) {
      final uri = next.value;
      if (uri != null) _onSsoCallbackUri(uri);
    });

    final authState = ref.watch(authProvider);
    // G43: nothing is looked up until the user acts (see [_lookupInput]).
    final lookup = _lookupInput;
    final flowsAsync = lookup == null
        ? null
        : ref.watch(loginFlowsProvider(lookup));
    final checking = flowsAsync?.isLoading ?? false;
    // Before the lookup, while discovery is still in flight (or if it failed),
    // show an optimistic form — generic SSO + password — so the screen is
    // usable immediately instead of frozen behind the homeserver lookup. It's
    // refined once the real flows arrive.
    LoginFlowsResult optimistic() => LoginFlowsResult(
      resolvedUrl: _asUrl(lookup ?? _enteredServer),
      hasPassword: true,
      hasSso: true,
      ssoProviders: const [],
    );
    final result =
        flowsAsync?.when(
          data: (r) => r,
          loading: optimistic,
          error: (_, _) => optimistic(),
        ) ??
        optimistic();

    // Show resolved URL as a hint when it differs from what the user typed.
    final resolvedLabel =
        lookup != null &&
            flowsAsync?.hasValue == true &&
            result.resolvedUrl.isNotEmpty &&
            result.resolvedUrl != _asUrl(lookup)
        ? result.resolvedUrl
        : null;

    // Disable the action buttons only while an actual login is in flight — NOT
    // while we're still discovering login flows. Gating the whole form behind
    // that network round-trip made the screen feel frozen for seconds after
    // launch. Discovery shows as the subtle spinner on the homeserver field.
    final authBusy = authState.isLoading || _resolving;
    final l = context.l10n;
    // G40: "Connect a Matrix account" from local mode — cancellable, and the
    // local groups move into the account after signing in.
    final connecting = ref.watch(connectingAccountProvider);

    return Scaffold(
      appBar: connecting
          ? AppBar(
              title: Text(l.connectMatrixAccount),
              leading: IconButton(
                key: const Key('cancelConnect'),
                icon: const Icon(Icons.close),
                tooltip: l.cancel,
                onPressed: authBusy ? null : () => cancelConnectAccount(ref),
              ),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLogo(size: 88)),
                  const SizedBox(height: 20),
                  Text(
                    l.appTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    connecting ? l.connectSignInSubtitle : l.signInSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  if (_error != null) ...[
                    AuthErrorCard(message: _error!),
                    const SizedBox(height: 16),
                  ],

                  // ── Server field ───────────────────────────────────────
                  TextFormField(
                    key: const Key('serverField'),
                    controller: _serverCtrl,
                    decoration: InputDecoration(
                      labelText: l.homeserverLabel,
                      hintText: l.homeserverHint,
                      prefixIcon: const Icon(Icons.dns),
                      helperText: resolvedLabel != null
                          ? l.resolvedTo(resolvedLabel)
                          : null,
                      suffix: checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            )
                          : null,
                      // G43: the sign-in options are only asked for when the
                      // user wants them — this button, Enter, or signing in.
                      suffixIcon: lookup == null
                          ? IconButton(
                              key: const Key('checkServerBtn'),
                              icon: const Icon(Icons.arrow_forward),
                              tooltip: l.checkServerTooltip,
                              onPressed: _commitServerInput,
                            )
                          : null,
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onChanged: _scheduleFlowsLookup,
                    onEditingComplete: _commitServerInput,
                    onTapOutside: (_) => _commitServerInput(explicit: false),
                  ),
                  const SizedBox(height: 24),

                  // ── SSO buttons ────────────────────────────────────────
                  if (result.hasSso) ...[
                    if (result.ssoProviders.isNotEmpty)
                      ...result.ssoProviders.map(
                        (p) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _SsoButton(
                            key: Key('ssoBtn_${p.id}'),
                            label: l.continueWith(p.name),
                            brand: p.brand,
                            onTap: authBusy
                                ? null
                                : () => _startSso(providerId: p.id),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SsoButton(
                          key: const Key('ssoBtn'),
                          // The entered server name, stable while discovery
                          // resolves it (G29); providers above use their names.
                          label: l.continueWith(
                            ssoServerLabel(lookup ?? _enteredServer),
                          ),
                          onTap: authBusy ? null : () => _startSso(),
                        ),
                      ),
                    if (result.hasPassword) ...[
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              l.orDivider,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],

                  // ── Password form ──────────────────────────────────────
                  if (result.hasPassword || !result.hasSso)
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            key: const Key('usernameField'),
                            controller: _usernameCtrl,
                            decoration: InputDecoration(
                              labelText: l.matrixIdOrUsernameLabel,
                              hintText: '@user:matrix.org',
                              prefixIcon: const Icon(Icons.person),
                            ),
                            onChanged: _onUsernameChanged,
                            validator: (v) =>
                                (v == null || v.isEmpty) ? l.required : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('passwordField'),
                            controller: _passwordCtrl,
                            decoration: InputDecoration(
                              labelText: l.passwordLabel,
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            obscureText: _obscurePassword,
                            onFieldSubmitted: (_) =>
                                authBusy ? null : _submitPassword(),
                            validator: (v) =>
                                (v == null || v.isEmpty) ? l.required : null,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            key: const Key('signInBtn'),
                            onPressed: authBusy ? null : _submitPassword,
                            child: authBusy
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(l.signIn),
                          ),
                        ],
                      ),
                    ),

                  // ── Create account ─────────────────────────────────────
                  const SizedBox(height: 12),
                  TextButton(
                    key: const Key('createAccountLink'),
                    onPressed: () => context.push('/register'),
                    child: Text(l.createAccountLink),
                  ),
                  // G39: the welcome's Matrix explanation, again.
                  TextButton(
                    key: const Key('whatIsMatrixLink'),
                    onPressed: () => context.push(
                      '$kHowItWorksLocation?topic=${WelcomeTopic.matrix.name}',
                    ),
                    child: Text(l.welcomeMatrixTitle),
                  ),
                  // G40: no account at all.
                  if (!connecting)
                    TextButton(
                      key: const Key('useWithoutAccountLink'),
                      onPressed: authBusy
                          ? null
                          : () => context.go(kLocalSetupLocation),
                      child: Text(l.welcomeUseLocal),
                    ),
                  TextButton(
                    key: const Key('aboutLink'),
                    onPressed: () => context.push('/about'),
                    child: Text(l.aboutAndPrivacy),
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

// ── SSO button widget ────────────────────────────────────────────────────────

class _SsoButton extends StatelessWidget {
  final String label;
  final String? brand;
  final VoidCallback? onTap;

  const _SsoButton({super.key, required this.label, this.brand, this.onTap});

  IconData get _icon {
    switch (brand?.toLowerCase()) {
      case 'google':
        return Icons.login;
      case 'github':
        return Icons.code;
      case 'apple':
        return Icons.apple;
      case 'facebook':
        return Icons.facebook;
      default:
        return Icons.shield;
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(_icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    );
  }
}
