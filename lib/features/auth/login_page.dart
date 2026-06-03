import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/platform/url_helper.dart';
import '../../models/login_flows_result.dart';
import 'auth_provider.dart';

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

  Future<void> _handleSsoCallback() async {
    final params = currentUrlParams;
    final token = params['loginToken'];
    if (token == null || token.isEmpty) return;

    final rawHs = params['hs'] ?? _serverCtrl.text.trim();
    clearUrlParams();

    // Resolve the homeserver via .well-known before token exchange.
    final result =
        await ref.read(loginFlowsProvider(rawHs).future);
    final hs = result.resolvedUrl.isNotEmpty ? result.resolvedUrl : rawHs;

    await ref
        .read(authProvider.notifier)
        .loginWithToken(resolvedHomeserver: hs, token: token);

    if (!mounted) return;
    final err = ref.read(authProvider).error;
    if (err != null) {
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

  void _startSso(LoginFlowsResult result, {String? providerId}) {
    final hsUri = Uri.tryParse(result.resolvedUrl);
    if (hsUri == null) return;

    final callbackBase =
        kIsWeb ? Uri.base.origin : 'moneyledger://sso-callback';
    final callbackUrl =
        '$callbackBase/?hs=${Uri.encodeComponent(result.resolvedUrl)}';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: SelectableText('SSO: $ssoUrl')),
      );
    }
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
    final authState = ref.watch(authProvider);
    final flowsAsync = ref.watch(loginFlowsProvider(_lookupInput));
    // On error (e.g. provider threw), still offer SSO with the entered URL.
    final result = flowsAsync.when(
      data: (r) => r,
      loading: () => LoginFlowsResult.empty,
      error: (_, _) => LoginFlowsResult(
        resolvedUrl: _lookupInput.startsWith('http')
            ? _lookupInput
            : 'https://$_lookupInput',
        hasPassword: true,
        hasSso: true,
        ssoProviders: [],
      ),
    );

    // Show resolved URL as a hint when it differs from what the user typed.
    final resolvedLabel = result.resolvedUrl.isNotEmpty &&
            result.resolvedUrl != 'https://${_lookupInput.trim()}'
        ? result.resolvedUrl
        : null;

    final loading = authState.isLoading || flowsAsync.isLoading;

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
                              onTap: loading
                                  ? null
                                  : () => _startSso(result,
                                      providerId: p.id),
                            ),
                          ))
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SsoButton(
                          key: const Key('ssoBtn'),
                          label:
                              'Continue with ${Uri.tryParse(result.resolvedUrl)?.host ?? _lookupInput}',
                          onTap: loading
                              ? null
                              : () => _startSso(result),
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
                            onFieldSubmitted: (_) => loading
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
                            onPressed: loading
                                ? null
                                : () => _submitPassword(
                                    result.resolvedUrl.isNotEmpty
                                        ? result.resolvedUrl
                                        : 'https://$_lookupInput'),
                            child: loading
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
