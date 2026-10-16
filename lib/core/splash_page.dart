import 'package:flutter/material.dart';

import 'widgets/brand_logo.dart';

/// Neutral loading screen shown right after sign-in while the account's
/// ledger database (and with it the onboarding flag) is still opening (G25).
/// The router leaves it automatically once the flag is known (or times out).
/// G17: the logo on the theme surface — same as the native launch screen.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: Key('splashPage'),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandLogo(size: 96),
            SizedBox(height: 32),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
