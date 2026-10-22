/// G72: an in-memory [NotificationPlatform] for widget / provider tests.
library;

import 'dart:async';

import 'package:money_ledger/features/notifications/change_notices.dart';
import 'package:money_ledger/features/notifications/notification_platform.dart';

class FakeNotificationPlatform implements NotificationPlatform {
  FakeNotificationPlatform({
    this.granted = false,
    this.grantOnRequest = true,
    this.launchGroup,
  });

  bool granted;
  bool grantOnRequest;
  String? launchGroup;
  int requests = 0;
  final shown = <List<ChangeNotice>>[];
  final taps = StreamController<String>.broadcast();

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<bool> requestPermission() async {
    requests++;
    if (grantOnRequest) granted = true;
    return granted;
  }

  @override
  Future<void> show(List<ChangeNotice> notices) async => shown.add(notices);

  @override
  Future<String?> launchGroupId() async => launchGroup;

  @override
  Stream<String> get tappedGroupIds => taps.stream;
}
