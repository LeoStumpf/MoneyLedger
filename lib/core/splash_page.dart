import 'package:flutter/material.dart';

/// Neutral loading screen shown right after sign-in while the account's
/// ledger database (and with it the onboarding flag) is still opening (G25).
/// The router leaves it automatically once the flag is known (or times out).
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
            Icon(Icons.account_balance_wallet, size: 64, color: Colors.teal),
            SizedBox(height: 24),
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
