import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/platform/url_helper.dart';
import '../../models/login_flows_result.dart';
import 'auth_provider.dart';
import 'sso_callback.dart';
import 'sso_provider.dart';
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

  /// The input currently being used to look up login flows.
  String _lookupInput = 'matrix.org';
  Timer? _debounce;

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
    debugPrint('[sso] callback uri received: $uri');
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

    await ref
        .read(authProvider.notifier)
        .loginWithToken(resolvedHomeserver: hs, token: token);

    if (!mounted) return;
    final err = ref.read(authProvider).error;
    debugPrint('[sso] token exchange done; error=$err');
    if (err != null) {
      _exchangingToken = null; // allow a retry after a failed exchange
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('SSO login failed: $err')));
    } else {
      context.go('/groups');
    }
  }

  // ── Homeserver / login-flows ─────────────────────────────────────────────

  void _scheduleFlowsLookup(String input) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      final trimmed = input.trim();
      if (trimmed.isNotEmpty && trimmed != _lookupInput) {
        setState(() => _lookupInput = trimmed);
      }
    });
  }

  /// Called when the user leaves the server field or presses Enter there.
  void _commitServerInput() {
    _debounce?.cancel();
    final trimmed = _serverCtrl.text.trim();
    if (trimmed.isNotEmpty && trimmed != _lookupInput) {
      setState(() => _lookupInput = trimmed);
    }
  }

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
    // loginFlows result if discovery already settled; otherwise awaits it now,
    // so tapping SSO before discovery finished still works (build() already
    // kicked the lookup off, so this is usually an instant cache read).
    var resolvedUrl = _lookupInput.startsWith('http')
        ? _lookupInput
        : 'https://${_lookupInput.trim()}';
    try {
      final r = await ref.read(loginFlowsProvider(_lookupInput).future);
      if (r.resolvedUrl.isNotEmpty) resolvedUrl = r.resolvedUrl;
    } catch (_) {
      // Discovery failed — fall back to the entered homeserver as-is.
    }

    final hsUri = Uri.tryParse(resolvedUrl);
    if (hsUri == null) return;

    final callbackBase =
        kIsWeb ? Uri.base.origin : 'moneyledger://sso-callback';
    final callbackUrl =
        '$callbackBase/?hs=${Uri.encodeComponent(resolvedUrl)}';

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

  Future<void> _submitPassword(String resolvedHomeserver) async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authProvider.notifier).login(
          resolvedHomeserver: resolvedHomeserver,
          username: _usernameCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
    if (!mounted) return;
    final err = ref.read(authProvider).error;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err.toString())));
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
    final flowsAsync = ref.watch(loginFlowsProvider(_lookupInput));
    // While discovery is still in flight (or if it failed), show an optimistic
    // form — generic SSO + password — so the screen is usable immediately
    // instead of frozen behind the homeserver lookup. It's refined once the
    // real flows arrive.
    LoginFlowsResult optimistic() => LoginFlowsResult(
          resolvedUrl: _lookupInput.startsWith('http')
              ? _lookupInput
              : 'https://${_lookupInput.trim()}',
          hasPassword: true,
          hasSso: true,
          ssoProviders: const [],
        );
    final result = flowsAsync.when(
      data: (r) => r,
      loading: optimistic,
      error: (_, _) => optimistic(),
    );

    // Show resolved URL as a hint when it differs from what the user typed.
    final resolvedLabel = result.resolvedUrl.isNotEmpty &&
            result.resolvedUrl != 'https://${_lookupInput.trim()}'
        ? result.resolvedUrl
        : null;

    // Disable the action buttons only while an actual login is in flight — NOT
    // while we're still discovering login flows. Gating the whole form behind
    // that network round-trip made the screen feel frozen for seconds after
    // launch. Discovery shows as the subtle spinner on the homeserver field.
    final authBusy = authState.isLoading;

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
                  const Icon(Icons.account_balance_wallet,
                      size: 64, color: Colors.teal),
                  const SizedBox(height: 16),
                  Text('MoneyLedger',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text('Sign in with your Matrix account',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 32),

                  // ── Server field ───────────────────────────────────────
                  TextFormField(
                    key: const Key('serverField'),
                    controller: _serverCtrl,
                    decoration: InputDecoration(
                      labelText: 'Homeserver',
                      hintText: 'matrix.org or mozilla.modular.im',
                      prefixIcon: const Icon(Icons.dns),
                      helperText: resolvedLabel != null
                          ? 'Resolved to $resolvedLabel'
                          : null,
                      suffix: flowsAsync.isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.5),
                            )
                          : null,
                    ),
                    keyboardType: TextInputType.url,
                    onChanged: _scheduleFlowsLookup,
                    onEditingComplete: _commitServerInput,
                    onTapOutside: (_) => _commitServerInput(),
                  ),
                  const SizedBox(height: 24),

                  // ── SSO buttons ────────────────────────────────────────
                  if (result.hasSso) ...[
                    if (result.ssoProviders.isNotEmpty)
                      ...result.ssoProviders.map((p) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SsoButton(
                              key: Key('ssoBtn_${p.id}'),
                              label: 'Continue with ${p.name}',
                              brand: p.brand,
                              onTap: authBusy
                                  ? null
                                  : () => _startSso(providerId: p.id),
                            ),
                          ))
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SsoButton(
                          key: const Key('ssoBtn'),
                          // The entered server name, stable while discovery
                          // resolves it (G29); providers above use their names.
                          label: 'Continue with ${ssoServerLabel(_lookupInput)}',
                          onTap: authBusy ? null : () => _startSso(),
                        ),
                      ),
                    if (result.hasPassword) ...[
                      Row(children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or',
                              style:
                                  Theme.of(context).textTheme.bodySmall),
                        ),
                        const Expanded(child: Divider()),
                      ]),
                      const SizedBox(height: 16),
                    ],
                  ],

                  // ── Password form ──────────────────────────────────────
                  if (result.hasPassword || !result.hasSso)
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            key: const Key('usernameField'),
                            controller: _usernameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Matrix ID or username',
                              hintText: '@user:matrix.org',
                              prefixIcon: Icon(Icons.person),
                            ),
                            onChanged: _onUsernameChanged,
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('passwordField'),
                            controller: _passwordCtrl,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off),
                                onPressed: () => setState(() =>
                                    _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            obscureText: _obscurePassword,
                            onFieldSubmitted: (_) => authBusy
                                ? null
                                : _submitPassword(
                                    result.resolvedUrl.isNotEmpty
                                        ? result.resolvedUrl
                                        : 'https://$_lookupInput'),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            key: const Key('signInBtn'),
                            onPressed: authBusy
                                ? null
                                : () => _submitPassword(
                                    result.resolvedUrl.isNotEmpty
                                        ? result.resolvedUrl
                                        : 'https://$_lookupInput'),
                            child: authBusy
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Text('Sign in'),
                          ),
                        ],
                      ),
                    ),

                  // ── Create account ─────────────────────────────────────
                  const SizedBox(height: 12),
                  TextButton(
                    key: const Key('createAccountLink'),
                    onPressed: () => context.push('/register'),
                    child: const Text("New here? Create an account"),
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
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
      ),
    );
  }
}
