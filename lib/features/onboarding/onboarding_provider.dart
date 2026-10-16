import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/daos/settings_dao.dart';
import '../../core/timer_factory.dart';
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

/// Whether the signed-in account has completed onboarding, as the router sees
/// it (G25). [unknown] = signed in but the per-account flag hasn't loaded yet
/// → the router shows a neutral splash instead of guessing (the old "default
/// to seen" made onboarding replace the groups page minutes after login when
/// the per-account DB opened late).
enum OnboardingStatus { unknown, seen, notSeen }

/// How long the router waits for the flag before giving up and treating it as
/// **seen** (a slow / failed DB open must never strand the user on the splash).
const kOnboardingFlagTimeout = Duration(seconds: 8);

/// [kOnboardingFlagTimeout], injectable for tests.
final onboardingFlagTimeoutProvider = Provider<Duration>(
  (_) => kOnboardingFlagTimeout,
);

/// Creates the flag-timeout timer; tests fire it explicitly (G15).
final onboardingTimerFactoryProvider = Provider<TimerFactory>((_) => Timer.new);

/// Router-facing onboarding state. Signed out → [OnboardingStatus.seen] (the
/// router never forces onboarding then). Signed in → [OnboardingStatus.unknown]
/// until the account's flag loads; a flag still *reloading* after an account
/// switch counts as unknown too, so the previous account's (or the signed-out
/// placeholder's) value is never reused. After [kOnboardingFlagTimeout] (or a
/// stream error) the answer latches to seen for that account — a late "not
/// seen" then no longer yanks the user to onboarding mid-use; it shows on the
/// next start instead.
@Riverpod(keepAlive: true)
class OnboardingGate extends _$OnboardingGate {
  /// Account whose flag timed out / failed — answers "seen" from then on.
  String? _gaveUpFor;

  @override
  OnboardingStatus build() {
    if (!ref.watch(isLoggedInProvider)) return OnboardingStatus.seen;
    final account = ref.watch(accountUserIdProvider);
    if (account != null && account == _gaveUpFor) return OnboardingStatus.seen;
    final flag = ref.watch(onboardingSeenStreamProvider);
    if (account != null && !flag.isLoading) {
      if (flag.hasError) {
        debugPrint(
          '[onboarding] flag failed to load for $account: '
          '${flag.error} — treating as seen',
        );
        _gaveUpFor = account;
        return OnboardingStatus.seen;
      }
      if (flag.hasValue) {
        return flag.requireValue
            ? OnboardingStatus.seen
            : OnboardingStatus.notSeen;
      }
    }
    final timeout = ref.read(onboardingFlagTimeoutProvider);
    final timer = ref.read(onboardingTimerFactoryProvider)(timeout, () {
      if (!ref.mounted) return;
      debugPrint(
        '[onboarding] flag for ${account ?? '(account loading)'} '
        'not loaded after ${timeout.inMilliseconds}ms — '
        'treating as seen',
      );
      _gaveUpFor = account;
      state = OnboardingStatus.seen;
    });
    ref.onDispose(timer.cancel);
    return OnboardingStatus.unknown;
  }
}

@Riverpod(keepAlive: true)
class OnboardingController extends _$OnboardingController {
  @override
  void build() {}

  Future<void> markSeen() => ref.read(settingsDaoProvider).markOnboardingSeen();
}
