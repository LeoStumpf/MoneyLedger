/// Device-wide preferences (G39 / G40) — the few flags that must work while
/// **no ledger DB is open** (signed out): whether the first-open welcome was
/// seen, and the local profile of "use without account" mode.
///
/// Everything per account (onboarding, backup dates, …) stays in the
/// per-account `AppSettings`; this store only holds what decides *which*
/// ledger opens at all. Storage: a small JSON file in the app support
/// directory (native) / one `localStorage` entry (web) — see
/// `device_prefs_store_io.dart` / `_web.dart`. No new dependency.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_prefs_store.dart';

/// Raw key-value persistence behind [DevicePrefs]. Plain strings, written as a
/// whole (the map is tiny).
abstract interface class DevicePrefsStore {
  /// Everything stored; empty on a fresh install. May throw (I/O).
  Future<Map<String, String>> load();

  /// Replaces the stored map with [values] (atomically where the platform
  /// allows). May throw.
  Future<void> save(Map<String, String> values);
}

/// In-memory store: tests, the offline demo, and the fallback when the
/// platform store can't be used.
class InMemoryDevicePrefsStore implements DevicePrefsStore {
  InMemoryDevicePrefsStore([Map<String, String>? initial])
    : values = {...?initial};

  /// The current contents (tests inspect it).
  final Map<String, String> values;

  @override
  Future<Map<String, String>> load() async => {...values};

  @override
  Future<void> save(Map<String, String> v) async => values
    ..clear()
    ..addAll(v);
}

/// The "use without account" profile (G40): the user's name in their local
/// groups. Present ⇔ local mode is chosen on this device.
@immutable
class LocalProfile {
  final String name;
  final int createdAt;
  const LocalProfile({required this.name, required this.createdAt});

  Map<String, Object?> toJson() => {'name': name, 'created_at': createdAt};

  static LocalProfile? fromJson(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return null;
      final name = m['name'];
      if (name is! String || name.trim().isEmpty) return null;
      final at = m['created_at'];
      return LocalProfile(name: name, createdAt: at is int ? at : 0);
    } catch (_) {
      return null;
    }
  }
}

/// The parsed device-wide preferences.
@immutable
class DevicePrefs {
  /// The first-open welcome (G39) was completed (any of its choices).
  final bool welcomeSeen;

  /// Local mode is chosen (G40); null = not in local mode.
  final LocalProfile? localProfile;

  /// "Connect a Matrix account" is in progress (G40): the login / register
  /// pages are shown although the local profile is still active. Persisted
  /// so a web SSO redirect (a page reload) keeps the flow.
  final bool connecting;

  /// The local ledger is being moved into this Matrix account (set at the
  /// successful sign-in of a connect, cleared once adopted).
  final String? adoptInto;

  /// The account the local ledger was last moved into — shown when local
  /// mode is started again ("your earlier local groups are in …").
  final String? lastAdoptedInto;

  /// G75 (U31): the web limits notice (groups page, web only) was dismissed.
  final bool webNoticeSeen;

  const DevicePrefs({
    this.welcomeSeen = false,
    this.localProfile,
    this.connecting = false,
    this.adoptInto,
    this.lastAdoptedInto,
    this.webNoticeSeen = false,
  });

  /// Used when the store can't be read: never strand the user on the
  /// welcome (it counts as seen) and never guess a local profile.
  static const unreadable = DevicePrefs(welcomeSeen: true);

  static const _welcomeKey = 'welcome_seen';
  static const _localKey = 'local_profile';
  static const _connectingKey = 'local_connecting';
  static const _adoptKey = 'local_adopt_into';
  static const _lastAdoptKey = 'local_last_adopted_into';
  static const _webNoticeKey = 'web_notice_seen';

  factory DevicePrefs.fromMap(Map<String, String> m) => DevicePrefs(
    welcomeSeen: m[_welcomeKey] == '1',
    localProfile: LocalProfile.fromJson(m[_localKey]),
    connecting: m[_connectingKey] == '1',
    adoptInto: _nonEmpty(m[_adoptKey]),
    lastAdoptedInto: _nonEmpty(m[_lastAdoptKey]),
    webNoticeSeen: m[_webNoticeKey] == '1',
  );

  Map<String, String> toMap() => {
    if (welcomeSeen) _welcomeKey: '1',
    if (localProfile != null) _localKey: jsonEncode(localProfile!.toJson()),
    if (connecting && localProfile != null) _connectingKey: '1',
    _adoptKey: ?adoptInto,
    _lastAdoptKey: ?lastAdoptedInto,
    if (webNoticeSeen) _webNoticeKey: '1',
  };

  DevicePrefs copyWith({
    bool? welcomeSeen,
    Object? localProfile = _keep,
    bool? connecting,
    Object? adoptInto = _keep,
    Object? lastAdoptedInto = _keep,
    bool? webNoticeSeen,
  }) => DevicePrefs(
    welcomeSeen: welcomeSeen ?? this.welcomeSeen,
    localProfile: identical(localProfile, _keep)
        ? this.localProfile
        : localProfile as LocalProfile?,
    connecting: connecting ?? this.connecting,
    adoptInto: identical(adoptInto, _keep)
        ? this.adoptInto
        : adoptInto as String?,
    lastAdoptedInto: identical(lastAdoptedInto, _keep)
        ? this.lastAdoptedInto
        : lastAdoptedInto as String?,
    webNoticeSeen: webNoticeSeen ?? this.webNoticeSeen,
  );

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  @override
  bool operator ==(Object other) =>
      other is DevicePrefs &&
      other.welcomeSeen == welcomeSeen &&
      other.localProfile?.name == localProfile?.name &&
      other.localProfile?.createdAt == localProfile?.createdAt &&
      other.connecting == connecting &&
      other.adoptInto == adoptInto &&
      other.lastAdoptedInto == lastAdoptedInto &&
      other.webNoticeSeen == webNoticeSeen;

  @override
  int get hashCode => Object.hash(
    welcomeSeen,
    localProfile?.name,
    localProfile?.createdAt,
    connecting,
    adoptInto,
    lastAdoptedInto,
    webNoticeSeen,
  );
}

const Object _keep = Object();

/// The platform store (file / localStorage). Tests override it with an
/// [InMemoryDevicePrefsStore].
final devicePrefsStoreProvider = Provider<DevicePrefsStore>(
  (ref) => createPlatformDevicePrefsStore(),
);

/// The device-wide preferences. Loading → the router shows the neutral splash;
/// a store that can't be read counts as [DevicePrefs.unreadable] (logged).
final devicePrefsProvider =
    AsyncNotifierProvider<DevicePrefsNotifier, DevicePrefs>(
      DevicePrefsNotifier.new,
    );

class DevicePrefsNotifier extends AsyncNotifier<DevicePrefs> {
  @override
  Future<DevicePrefs> build() async {
    try {
      return DevicePrefs.fromMap(
        await ref.read(devicePrefsStoreProvider).load(),
      );
    } catch (e) {
      debugPrint('[prefs] device preferences unreadable: $e');
      return DevicePrefs.unreadable;
    }
  }

  DevicePrefs get _current => state.value ?? const DevicePrefs();

  /// Persists [next] and publishes it. The state changes even when the write
  /// fails (the flow goes on for this run); the error is rethrown so the
  /// caller can tell the user.
  Future<void> _update(DevicePrefs Function(DevicePrefs) change) async {
    // A write before the first load finished must not clobber stored values.
    if (state.isLoading) await future;
    final next = change(_current);
    state = AsyncData(next);
    await ref.read(devicePrefsStoreProvider).save(next.toMap());
  }

  /// G75 (U31): the web limits notice was dismissed (device-wide).
  Future<void> markWebNoticeSeen() =>
      _update((p) => p.copyWith(webNoticeSeen: true));

  /// G39: the welcome was completed (any of its three choices).
  Future<void> markWelcomeSeen() =>
      _update((p) => p.copyWith(welcomeSeen: true));

  /// G40: "Use without account" — local mode with [name] as the user's name.
  Future<void> startLocalProfile(String name) => _update(
    (p) => p.copyWith(
      welcomeSeen: true,
      localProfile: LocalProfile(
        name: name.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
      connecting: false,
    ),
  );

  /// G40: renames the local profile (shown for new local groups only).
  Future<void> renameLocalProfile(String name) => _update(
    (p) => p.localProfile == null
        ? p
        : p.copyWith(
            localProfile: LocalProfile(
              name: name.trim(),
              createdAt: p.localProfile!.createdAt,
            ),
          ),
  );

  /// G40: "Connect a Matrix account" started (true) / cancelled (false).
  Future<void> setConnecting(bool on) =>
      _update((p) => p.copyWith(connecting: on && p.localProfile != null));

  /// G40: a connect signed in as [mxid] — local mode ends, the local ledger
  /// is to be moved into that account ([adoptInto], done by
  /// `LocalLedgerAdoption`). One write, so a crash can't leave both.
  /// [onlyWhileConnecting] (G18 review 2): a no-op unless a connect is still
  /// in progress (it may have been cancelled meanwhile).
  Future<void> beginLocalAdoption(
    String mxid, {
    bool onlyWhileConnecting = false,
  }) => _update(
    (p) => onlyWhileConnecting && !(p.connecting && p.localProfile != null)
        ? p
        : p.copyWith(localProfile: null, connecting: false, adoptInto: mxid),
  );

  /// G40: the local ledger now lives in [mxid]'s account DB.
  Future<void> finishLocalAdoption(String mxid) =>
      _update((p) => p.copyWith(adoptInto: null, lastAdoptedInto: mxid));

  /// G40: "Leave local mode" — the profile is dropped (its data was deleted
  /// by the caller).
  Future<void> endLocalProfile() =>
      _update((p) => p.copyWith(localProfile: null, connecting: false));
}
