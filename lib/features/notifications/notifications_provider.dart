/// G72: app-side wiring of the change notifications — the platform seam,
/// the per-ledger setting, the one-time permission prompt and opening a
/// tapped notification's group.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/background/background_sync_provider.dart';
import '../../core/router.dart';
import '../../core/session/app_session.dart';
import '../expenses/expenses_provider.dart' show membersDaoProvider;
import '../link/link_join.dart' show kJoinLocation;
import '../onboarding/onboarding_provider.dart';
import 'notification_platform.dart';

/// The platform's notifications (Android), null where there are none (web,
/// desktop, the test VM). Tests override it with a fake.
final notificationPlatformProvider = Provider<NotificationPlatform?>(
  (ref) => createPlatformNotifications(),
);

/// Whether notifications exist here: they come from the background round,
/// so only where that runs (Android).
final notificationsSupportedProvider = Provider<bool>(
  (ref) =>
      ref.watch(backgroundSyncSupportedProvider) &&
      ref.watch(notificationPlatformProvider) != null,
);

/// The open ledger's notification setting (device-local, default on);
/// no ledger open → false.
final notificationsEnabledProvider = StreamProvider.autoDispose<bool>((ref) {
  if (ref.watch(ledgerIdentityProvider) == null) return Stream.value(false);
  return ref.watch(settingsDaoProvider).watchNotificationsEnabled();
});

/// Whether the OS lets the app post notifications (null = no platform).
/// Invalidated after a permission request.
final notificationPermissionProvider = FutureProvider.autoDispose<bool?>((
  ref,
) async {
  final platform = ref.watch(notificationPlatformProvider);
  return platform?.permissionGranted();
});

/// Whether the open ledger has a group shared with someone else — a link
/// group or another Matrix account in a group.
final sharedGroupExistsProvider = StreamProvider.autoDispose<bool>((ref) {
  final me = ref.watch(ledgerIdentityProvider);
  if (me == null) return Stream.value(false);
  final links = ref.watch(linkGroupsExistProvider);
  if (links.value == true) return Stream.value(true);
  return ref.watch(membersDaoProvider).watchHasOtherClaimedMember(me);
});

/// Whether to ask for the permission on our own now (pure): notifications
/// and background sync are on, a group is shared (before that there is
/// nothing to tell), not asked before and not granted yet.
bool shouldAskNotificationPermission({
  required bool enabled,
  required bool backgroundSync,
  required bool sharedGroup,
  required bool asked,
  required bool granted,
}) => enabled && backgroundSync && sharedGroup && !asked && !granted;

/// The one-time permission prompt (Android 13+ shows the system dialog) —
/// at the first moment a notification could ever come: on the groups page,
/// once a group is shared. Asked once per ledger; the settings switch asks
/// again. Watched by `GroupsPage`.
final notificationPermissionPromptProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  if (!ref.watch(notificationsSupportedProvider)) return;
  final platform = ref.watch(notificationPlatformProvider)!;
  final shared = ref.watch(sharedGroupExistsProvider).value ?? false;
  final enabled = ref.watch(notificationsEnabledProvider).value ?? false;
  final background = ref.watch(backgroundSyncEnabledProvider).value ?? false;
  if (!shared || !enabled || !background) return;
  // Captured before the first await (G19).
  final dao = ref.read(settingsDaoProvider);
  try {
    final asked = await dao.notificationPermissionAsked();
    if (asked || !ref.mounted) return;
    final granted = await platform.permissionGranted();
    if (!ref.mounted) return;
    if (!shouldAskNotificationPermission(
      enabled: enabled,
      backgroundSync: background,
      sharedGroup: shared,
      asked: asked,
      granted: granted,
    )) {
      if (granted) await dao.markNotificationPermissionAsked();
      return;
    }
    // Marked first: a dialog dismissed by a crash / kill is not repeated.
    await dao.markNotificationPermissionAsked();
    await platform.requestPermission();
    if (ref.mounted) ref.invalidate(notificationPermissionProvider);
  } catch (e) {
    // The DB closed under us (account switch) — try again next time.
    debugPrint('[notify] permission prompt skipped: $e');
  }
});

/// Turns the notifications on / off; turning them on asks for the
/// permission (the system dialog when Android still may show it).
Future<void> setNotificationsEnabled(WidgetRef ref, bool on) async {
  final dao = ref.read(settingsDaoProvider);
  final platform = ref.read(notificationPlatformProvider);
  await dao.setNotificationsEnabled(on);
  if (on && platform != null) {
    await dao.markNotificationPermissionAsked();
    await platform.requestPermission();
  }
  ref.invalidate(notificationPermissionProvider);
}

/// Pages a tapped notification must not jump away from: start-up, sign-in
/// and joining (the group opens once the user is in). `''` / `/`: the
/// router has not resolved its first location yet (redirected right after).
const _notificationBlockedPaths = {
  '',
  '/',
  kSplashLocation,
  kWelcomeLocation,
  kLocalSetupLocation,
  kHowItWorksLocation,
  kJoinLocation,
  '/onboarding',
  '/login',
  '/register',
};

/// Whether a tapped notification may open its group from [path] now.
@visibleForTesting
bool notificationOpenAllowed(String path) =>
    !_notificationBlockedPaths.contains(path) && !path.startsWith('/sso');

/// The group page a notification opens.
String notificationGroupLocation(String groupId) =>
    '/groups/${Uri.encodeComponent(groupId)}/expenses';

/// Opens the group of a tapped notification (also the one that launched
/// the app) — as soon as the app is past start-up / onboarding.
class NotificationTapListener extends ConsumerStatefulWidget {
  const NotificationTapListener({
    super.key,
    required this.go,
    required this.location,
    required this.locationChanges,
    required this.child,
  });

  final void Function(String location) go;

  /// The router's current path.
  final String Function() location;

  /// Notifies when [location] changes (the router delegate).
  final Listenable locationChanges;
  final Widget child;

  @override
  ConsumerState<NotificationTapListener> createState() =>
      _NotificationTapListenerState();
}

class _NotificationTapListenerState
    extends ConsumerState<NotificationTapListener> {
  String? _pending;
  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
    final platform = ref.read(notificationPlatformProvider);
    if (platform == null) return;
    widget.locationChanges.addListener(_tryOpen);
    _taps = platform.tappedGroupIds.listen(_open);
    unawaited(
      platform.launchGroupId().then((id) {
        if (id != null && mounted) _open(id);
      }),
    );
  }

  void _open(String groupId) {
    _pending = groupId;
    _tryOpen();
  }

  void _tryOpen() {
    final id = _pending;
    if (id == null || !mounted) return;
    if (!notificationOpenAllowed(widget.location())) return;
    _pending = null;
    widget.go(notificationGroupLocation(id));
  }

  @override
  void dispose() {
    widget.locationChanges.removeListener(_tryOpen);
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
