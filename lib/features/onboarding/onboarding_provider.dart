import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/daos/settings_dao.dart';
import '../expenses/expenses_provider.dart';

part 'onboarding_provider.g.dart';

@Riverpod(keepAlive: true)
SettingsDao settingsDao(Ref ref) => SettingsDao(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
Stream<bool> onboardingSeenStream(Ref ref) =>
    ref.watch(settingsDaoProvider).watchOnboardingSeen();

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
