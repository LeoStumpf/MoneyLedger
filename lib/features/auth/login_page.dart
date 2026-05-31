import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import '../../core/platform/url_helper.dart';
import 'auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _homeserverCtrl =
      TextEditingController(text: 'https://matrix.org');
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  // When the homeserver field loses focus, fetch available login flows.
  String _lastFetchedHomeserver = '';

  @override
  void initState() {
    super.initState();
    // On web: check if we're returning from an SSO redirect with a loginToken.
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleSsoCallback();
      });
    }
  }

  Future<void> _handleSsoCallback() async {
    final params = currentUrlParams;
    final token = params['loginToken'];
    final homeserver =
        params['hs'] ?? _homeserverCtrl.text.trim();
    if (token == null || token.isEmpty) return;

    // Clear the token from the URL immediately so a reload doesn't replay it.
    clearUrlParams();

    await ref
        .read(authProvider.notifier)
        .loginWithToken(homeserver: homeserver, token: token);

    final error = ref.read(authProvider).error;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SSO login failed: $error')),
      );
    } else if (mounted) {
      context.go('/groups');
    }
  }

  void _onHomeserverSubmitted() {
    final hs = _homeserverCtrl.text.trim();
    if (hs != _lastFetchedHomeserver && hs.isNotEmpty) {
      setState(() => _lastFetchedHomeserver = hs);
      // Invalidate the cached flows so they refresh for the new homeserver.
      ref.invalidate(loginFlowsProvider(hs));
    }
  }

  Future<void> _submitPassword() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authProvider.notifier).login(
          homeserver: _homeserverCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
    final error = ref.read(authProvider).error;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } else if (mounted) {
      context.go('/groups');
    }
  }

  void _startSso({String? providerId}) {
    final hs = _homeserverCtrl.text.trim();
    if (hs.isEmpty) return;

    final hsUri = Uri.tryParse(hs);
    if (hsUri == null) return;

    // Embed the homeserver in the callback URL so we know where to authenticate
    // when the loginToken arrives after the SSO redirect.
    final callbackBase =
        kIsWeb ? Uri.base.origin : 'moneyledger://sso-callback';
    final callbackUrl =
        '$callbackBase/?hs=${Uri.encodeComponent(hs)}';

    // Build the SSO redirect URL directly — no Matrix client needed.
    final path = providerId != null
        ? '_matrix/client/v3/login/sso/redirect/$providerId'
        : '_matrix/client/v3/login/sso/redirect';
    final ssoUrl = hsUri
        .resolve(path)
        .replace(queryParameters: {'redirectUrl': callbackUrl})
        .toString();

    if (kIsWeb) {
      navigateTo(ssoUrl);
    } else {
      // Mobile: open in WebView / in-app browser (to be wired up later).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: SelectableText('SSO URL: $ssoUrl')),
      );
    }
  }

  @override
  void dispose() {
    _homeserverCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final hs = _lastFetchedHomeserver.isEmpty
        ? _homeserverCtrl.text.trim()
        : _lastFetchedHomeserver;
    final flowsAsync = ref.watch(loginFlowsProvider(hs));
    final flows = flowsAsync.value ?? [];
    final hasPassword =
        flows.any((f) => f.type == AuthenticationTypes.password) ||
            flows.isEmpty; // show password fields by default before flows load
    final ssoFlow = flows.cast<LoginFlow?>().firstWhere(
          (f) => f?.type == AuthenticationTypes.sso,
          orElse: () => null,
        );
    final providers = (ssoFlow?.additionalProperties['identity_providers']
            as List?)
        ?.cast<Map>()
        .toList() ??
        [];

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
                  Text(
                    'MoneyLedger',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in with your Matrix account',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // ── Homeserver field ─────────────────────────────────
                  TextFormField(
                    controller: _homeserverCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Homeserver',
                      hintText: 'https://matrix.org',
                      prefixIcon: Icon(Icons.dns),
                    ),
                    keyboardType: TextInputType.url,
                    onEditingComplete: _onHomeserverSubmitted,
                    onTapOutside: (_) => _onHomeserverSubmitted(),
                  ),
                  const SizedBox(height: 24),

                  // ── SSO providers ────────────────────────────────────
                  if (ssoFlow != null) ...[
                    if (providers.isNotEmpty)
                      ...providers.map((p) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SsoButton(
                              label: 'Continue with ${p['name'] ?? 'SSO'}',
                              brand: p['brand'] as String?,
                              onTap: authState.isLoading
                                  ? null
                                  : () => _startSso(
                                      providerId: p['id'] as String?),
                            ),
                          ))
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SsoButton(
                          label: 'Continue with ${Uri.tryParse(hs)?.host ?? 'SSO'}',
                          onTap: authState.isLoading
                              ? null
                              : () => _startSso(),
                        ),
                      ),
                    if (hasPassword) ...[
                      Row(children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or',
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                        const Expanded(child: Divider()),
                      ]),
                      const SizedBox(height: 16),
                    ],
                  ],

                  // ── Password form ────────────────────────────────────
                  if (hasPassword)
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _usernameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Matrix ID or username',
                              hintText: '@user:matrix.org',
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
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
                            onFieldSubmitted: (_) => authState.isLoading
                                ? null
                                : _submitPassword(),
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed:
                                authState.isLoading ? null : _submitPassword,
                            child: authState.isLoading
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

                  if (authState.isLoading && ssoFlow != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator()),
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

class _SsoButton extends StatelessWidget {
  final String label;
  final String? brand;
  final VoidCallback? onTap;

  const _SsoButton({required this.label, this.brand, this.onTap});

  IconData get _icon {
    switch (brand?.toLowerCase()) {
      case 'google':
        return Icons.login; // would use a proper Google icon in production
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
