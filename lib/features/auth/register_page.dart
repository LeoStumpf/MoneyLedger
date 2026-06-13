import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/matrix/auth_gateway.dart';
import '../../core/platform/url_helper.dart';
import 'auth_provider.dart';

/// In-app account creation (Phase F). Works against homeservers that allow open
/// / `m.login.dummy` registration; servers requiring a CAPTCHA, email/phone
/// verification or terms acceptance surface a clear web-registration fallback
/// (we don't reimplement every UIA stage). SSO-only servers should sign in via
/// the login screen instead.
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverCtrl = TextEditingController(text: 'matrix.org');
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  /// Set when the homeserver needs interactive registration we can't do in-app.
  RegistrationRequiresWebException? _needsWeb;

  @override
  void dispose() {
    _serverCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String get _resolvedHomeserver {
    final raw = _serverCtrl.text.trim();
    return raw.startsWith('http') ? raw : 'https://$raw';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _needsWeb = null);
    await ref.read(authProvider.notifier).register(
          resolvedHomeserver: _resolvedHomeserver,
          username: _usernameCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
    if (!mounted) return;
    final err = ref.read(authProvider).error;
    if (err == null) {
      context.go('/groups');
    } else if (err is RegistrationRequiresWebException) {
      setState(() => _needsWeb = err);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Registration failed: $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(authProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('serverField'),
                      controller: _serverCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Homeserver',
                        hintText: 'matrix.org',
                        prefixIcon: Icon(Icons.dns),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('usernameField'),
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: 'alice',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
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
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      validator: (v) => (v == null || v.length < 8)
                          ? 'At least 8 characters'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('createAccountBtn'),
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Create account'),
                    ),
                    if (_needsWeb != null) ...[
                      const SizedBox(height: 20),
                      _WebFallbackCard(info: _needsWeb!),
                    ],
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Already have an account? Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the homeserver needs interactive registration — explains why and
/// offers to open its website.
class _WebFallbackCard extends StatelessWidget {
  final RegistrationRequiresWebException info;
  const _WebFallbackCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final reqs = info.requirements.isEmpty
        ? 'extra verification'
        : info.requirements.join(' and ');
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Register on the web',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('This homeserver requires $reqs, which MoneyLedger can\'t do '
                'in-app yet. Create your account on its website, then come back '
                'and sign in.'),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => launchExternalUrl(info.homeserverUrl),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open homeserver website'),
            ),
          ],
        ),
      ),
    );
  }
}
