/// G72: the notification platform seam — the Android implementation
/// (flutter_local_notifications) or none (web, other platforms, tests).
library;

import 'change_notices.dart';

export 'notification_platform_stub.dart'
    if (dart.library.io) 'notification_platform_native.dart';

/// Shows the change notifications and owns the Android 13+ permission.
abstract interface class NotificationPlatform {
  /// Whether the app may post notifications (Android 13+: the runtime
  /// permission; older versions: not blocked in the app's settings).
  Future<bool> permissionGranted();

  /// Asks for the permission (the system dialog on Android 13+; Android
  /// shows it at most twice — afterwards only the app's settings help).
  /// Returns whether it is granted now.
  Future<bool> requestPermission();

  /// Posts one notification per notice (text in the device's language).
  Future<void> show(List<ChangeNotice> notices);

  /// The group of the notification that launched the app, if any.
  Future<String?> launchGroupId();

  /// Groups of notifications tapped while the app runs.
  Stream<String> get tappedGroupIds;
}
