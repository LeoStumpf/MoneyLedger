import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/daos/settings_dao.dart';
import '../auth/auth_provider.dart';
import '../expenses/expenses_provider.dart';

part 'onboarding_provider.g.dart';

@Riverpod(keepAlive: true)
SettingsDao settingsDao(Ref ref) => SettingsDao(ref.watch(appDatabaseProvider));

/// The flag lives in the **per-account** ledger DB (G4), so onboarding is
/// shown once per account on a device. Signed out there is no DB to read and
/// the router never forces onboarding anyway → report "seen".
@Riverpod(keepAlive: true)
Stream<bool> onboardingSeenStream(Ref ref) {
  if (ref.watch(accountUserIdProvider) == null) return Stream.value(true);
  return ref.watch(settingsDaoProvider).watchOnboardingSeen();
}

/// Synchronous view used by the router. Defaults to **seen** until the flag
/// loads, so the common case (returning user) never flashes the onboarding
/// screen; a genuine first-run user is routed there one frame later when the
/// flag resolves to false and the router's refresh listener re-evaluates.
@Riverpod(keepAlive: true)
bool onboardingSeen(Ref ref) =>
    ref.watch(onboardingSeenStreamProvider).value ?? true;

@Riverpod(keepAlive: true)
class OnboardingController extends _$OnboardingController {
  @override
  void build() {}

  Future<void> markSeen() => ref.read(settingsDaoProvider).markOnboardingSeen();
}
