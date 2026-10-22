/// G72: local notifications on Android via flutter_local_notifications —
/// posted by the device itself (no push service, no Firebase / Google
/// services). Used by the headless background round ([show]) and the app
/// (permission, taps).
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../l10n/app_localizations.dart';
import 'change_notices.dart';
import 'notification_platform.dart';

/// The notification channel (Android 8+; its name shows in the app's
/// notification settings).
const kChangesChannelId = 'others_changes';

/// Groups this app's notifications in the shade.
const kChangesGroupKey = 'io.github.leostumpf.moneyledger.changes';

NotificationPlatform? createPlatformNotifications() =>
    Platform.isAndroid ? _AndroidNotifications.instance : null;

/// The device's language among the app's (EN fallback) — the background
/// isolate has no widget tree.
AppLocalizations deviceLocalizations() {
  for (final l in PlatformDispatcher.instance.locales) {
    for (final s in AppLocalizations.supportedLocales) {
      if (s.languageCode == l.languageCode) {
        return lookupAppLocalizations(Locale(s.languageCode));
      }
    }
  }
  return lookupAppLocalizations(const Locale('en'));
}

class _AndroidNotifications implements NotificationPlatform {
  _AndroidNotifications._();

  static final instance = _AndroidNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  Future<bool?>? _ready;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> _init() async {
    _ready ??= _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_notify'),
      ),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) _taps.add(id);
      },
    );
    await _ready;
  }

  @override
  Future<bool> permissionGranted() async {
    try {
      await _init();
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (e) {
      debugPrint('[notify] permission check failed: $e');
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      await _init();
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('[notify] permission request failed: $e');
      return false;
    }
  }

  @override
  Future<void> show(List<ChangeNotice> notices) async {
    if (notices.isEmpty) return;
    await _init();
    final l = deviceLocalizations();
    for (final n in notices) {
      final text = noticeText(n, l);
      await _plugin.show(
        id: noticeIdFor(n.groupId),
        title: text.title,
        body: text.body,
        payload: n.groupId,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            kChangesChannelId,
            l.notificationChannelName,
            channelDescription: l.notificationChannelDescription,
            icon: 'ic_stat_notify',
            groupKey: kChangesGroupKey,
            category: AndroidNotificationCategory.social,
            // Hidden on a secure lock screen when Android hides sensitive
            // content (PRIVACY.md).
            visibility: NotificationVisibility.private,
            styleInformation: text.lines.isEmpty
                ? BigTextStyleInformation(text.body)
                : InboxStyleInformation(text.lines, summaryText: text.body),
          ),
        ),
      );
    }
    debugPrint('[notify] posted ${notices.length} notification(s)');
  }

  @override
  Future<String?> launchGroupId() async {
    try {
      await _init();
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d == null || !d.didNotificationLaunchApp) return null;
      final id = d.notificationResponse?.payload;
      return id == null || id.isEmpty ? null : id;
    } catch (e) {
      debugPrint('[notify] launch details failed: $e');
      return null;
    }
  }

  @override
  Stream<String> get tappedGroupIds {
    unawaited(
      _init().catchError((Object e) {
        debugPrint('[notify] init failed: $e');
      }),
    );
    return _taps.stream;
  }
}
