/// G39 / G40: the device-wide preferences (welcome seen, local profile,
/// connect / adoption state) — parsing, transitions, the file store, and the
/// "unreadable store never strands the user" fallback.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/device_prefs.dart';
import 'package:money_ledger/core/session/device_prefs_store_io.dart';

class _BrokenStore implements DevicePrefsStore {
  @override
  Future<Map<String, String>> load() async => throw const FileSystemException();
  @override
  Future<void> save(Map<String, String> values) async =>
      throw const FileSystemException('read-only');
}

class _GatedStore extends InMemoryDevicePrefsStore {
  _GatedStore(this.gate);
  final Future<void> gate;
  @override
  Future<Map<String, String>> load() async {
    await gate;
    return super.load();
  }
}

void main() {
  group('DevicePrefs (pure)', () {
    test('a fresh install: welcome not seen, no local profile', () {
      final p = DevicePrefs.fromMap(const {});
      expect(p.welcomeSeen, isFalse);
      expect(p.localProfile, isNull);
      expect(p.connecting, isFalse);
      expect(p.adoptInto, isNull);
      expect(p.webNoticeSeen, isFalse);
    });

    test('round-trips through the stored map', () {
      const p = DevicePrefs(
        welcomeSeen: true,
        localProfile: LocalProfile(name: 'Lea', createdAt: 5),
        connecting: true,
        lastAdoptedInto: '@a:x.org',
        webNoticeSeen: true, // G75
      );
      expect(p.toMap()['web_notice_seen'], '1');
      expect(DevicePrefs.fromMap(p.toMap()), p);
      expect(p.copyWith(connecting: false).webNoticeSeen, isTrue);
    });

    test('connecting is only kept with a local profile', () {
      const p = DevicePrefs(connecting: true);
      expect(p.toMap().containsKey('local_connecting'), isFalse);
    });

    test('a malformed local profile is ignored', () {
      expect(
        DevicePrefs.fromMap(const {'local_profile': 'not json'}).localProfile,
        isNull,
      );
      expect(
        DevicePrefs.fromMap(const {
          'local_profile': '{"name":"  "}',
        }).localProfile,
        isNull,
      );
    });
  });

  group('DevicePrefsNotifier', () {
    late InMemoryDevicePrefsStore store;
    late ProviderContainer c;

    setUp(() {
      store = InMemoryDevicePrefsStore();
      c = ProviderContainer(
        overrides: [devicePrefsStoreProvider.overrideWithValue(store)],
      );
      c.listen(devicePrefsProvider, (_, _) {});
    });
    tearDown(() => c.dispose());

    DevicePrefsNotifier n() => c.read(devicePrefsProvider.notifier);

    test('fresh install: welcome not seen → seen', () async {
      await c.read(devicePrefsProvider.future);
      expect(c.read(welcomeStatusProvider), WelcomeStatus.notSeen);
      await n().markWelcomeSeen();
      expect(c.read(welcomeStatusProvider), WelcomeStatus.seen);
      expect(store.values, {'welcome_seen': '1'});
    });

    test('local profile → connect → adoption → finished', () async {
      await c.read(devicePrefsProvider.future);
      await n().startLocalProfile('  Lea ');
      expect(c.read(localProfileProvider)?.name, 'Lea');
      expect(c.read(welcomeStatusProvider), WelcomeStatus.seen);
      expect(c.read(localModeActiveProvider), isTrue);
      expect(c.read(matrixSessionWantedProvider), isFalse);

      await n().setConnecting(true);
      expect(c.read(connectingAccountProvider), isTrue);
      expect(c.read(matrixSessionWantedProvider), isTrue);
      expect(store.values['local_connecting'], '1');

      await n().beginLocalAdoption('@lea:x.org');
      var p = c.read(devicePrefsProvider).requireValue;
      expect(p.localProfile, isNull);
      expect(p.connecting, isFalse);
      expect(p.adoptInto, '@lea:x.org');
      expect(c.read(localModeActiveProvider), isFalse);

      await n().finishLocalAdoption('@lea:x.org');
      p = c.read(devicePrefsProvider).requireValue;
      expect(p.adoptInto, isNull);
      expect(p.lastAdoptedInto, '@lea:x.org');
      expect(store.values, {
        'welcome_seen': '1',
        'local_last_adopted_into': '@lea:x.org',
      });
    });

    test('setConnecting without a local profile does nothing', () async {
      await c.read(devicePrefsProvider.future);
      await n().setConnecting(true);
      expect(c.read(connectingAccountProvider), isFalse);
    });

    test('endLocalProfile leaves local mode', () async {
      await c.read(devicePrefsProvider.future);
      await n().startLocalProfile('Lea');
      await n().endLocalProfile();
      expect(c.read(localProfileProvider), isNull);
      expect(c.read(localModeActiveProvider), isFalse);
    });

    test('a profile stored earlier is restored on the next start', () async {
      await c.read(devicePrefsProvider.future);
      await n().startLocalProfile('Lea');
      final c2 = ProviderContainer(
        overrides: [devicePrefsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c2.dispose);
      c2.listen(devicePrefsProvider, (_, _) {});
      await c2.read(devicePrefsProvider.future);
      expect(c2.read(appSessionProvider), AppSessionKind.local);
      expect(c2.read(ledgerIdentityProvider), kLocalAccountId);
    });
  });

  test('while the store loads: splash (session + welcome unknown)', () async {
    final gate = Completer<void>();
    final store = _GatedStore(gate.future);
    final c = ProviderContainer(
      overrides: [devicePrefsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    c.listen(devicePrefsProvider, (_, _) {});
    expect(c.read(welcomeStatusProvider), WelcomeStatus.unknown);
    expect(c.read(appSessionProvider), AppSessionKind.loading);
    expect(c.read(matrixSessionWantedProvider), isFalse);
    gate.complete();
    await c.read(devicePrefsProvider.future);
    expect(c.read(welcomeStatusProvider), WelcomeStatus.notSeen);
  });

  test(
    'an unreadable store counts as "welcome seen" (never stranded)',
    () async {
      final c = ProviderContainer(
        overrides: [devicePrefsStoreProvider.overrideWithValue(_BrokenStore())],
      );
      addTearDown(c.dispose);
      c.listen(devicePrefsProvider, (_, _) {});
      final p = await c.read(devicePrefsProvider.future);
      expect(p.welcomeSeen, isTrue);
      expect(p.localProfile, isNull);
      // A failing write still changes the state for this run, and is reported.
      await expectLater(
        c.read(devicePrefsProvider.notifier).startLocalProfile('Lea'),
        throwsA(isA<FileSystemException>()),
      );
      expect(c.read(localProfileProvider)?.name, 'Lea');
    },
  );

  group('FileDevicePrefsStore', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('prefs_'));
    tearDown(() => tmp.delete(recursive: true));

    test('missing file → empty; save → load; no temp file left', () async {
      final file = File('${tmp.path}/sub/device_prefs.json');
      final store = FileDevicePrefsStore(() async => file);
      expect(await store.load(), isEmpty);
      await store.save({'welcome_seen': '1', 'local_profile': '{"name":"A"}'});
      expect(await store.load(), {
        'welcome_seen': '1',
        'local_profile': '{"name":"A"}',
      });
      expect(File('${file.path}.tmp').existsSync(), isFalse);
      await store.save({'welcome_seen': '1'});
      expect(await store.load(), {'welcome_seen': '1'});
    });

    test('a corrupt file throws (→ the notifier falls back)', () async {
      final file = File('${tmp.path}/device_prefs.json')
        ..writeAsStringSync('{oops');
      final store = FileDevicePrefsStore(() async => file);
      await expectLater(store.load(), throwsA(isA<FormatException>()));
    });
  });
}
