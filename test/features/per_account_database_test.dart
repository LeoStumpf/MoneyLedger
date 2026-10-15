/// G4: each Matrix account on a device gets its own ledger DB. Two accounts
/// never see each other's groups; logout is non-destructive.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/onboarding/onboarding_provider.dart';
import 'package:money_ledger/models/group_model.dart';

import '../helpers/fake_auth_gateway.dart';

void main() {
  late Directory tmp;
  late FakeAuthGateway gateway;
  late ProviderContainer c;
  final opened = <String>[];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('per_account_db_');
    gateway = FakeAuthGateway();
    opened.clear();
    c = ProviderContainer(overrides: [
      authGatewayProvider.overrideWith((ref) => gateway),
      // Temp files keyed by the derived name — persist across close/reopen
      // like the real per-account files.
      // Transport never resolves: sync engines construct but stay idle.
      ledgerTransportProvider
          .overrideWith((ref) => Completer<LedgerTransport>().future),
      accountDatabaseOpenerProvider.overrideWithValue((mxid) {
        final name = accountDatabaseName(mxid);
        opened.add(name);
        return AppDatabase.forTesting(
            NativeDatabase(File('${tmp.path}/$name.sqlite')));
      }),
    ]);
    // In the app, appDatabaseProvider keeps this alive; mirror that here.
    c.listen(accountUserIdProvider, (_, _) {});
    // Riverpod 3 pauses unlistened providers; the router listens in the app.
    c.listen(onboardingSeenStreamProvider, (_, _) {});
  });

  tearDown(() async {
    c.dispose();
    gateway.dispose();
    await tmp.delete(recursive: true);
  });

  Future<void> login(String user) async {
    await c.read(authProvider.notifier).login(
        resolvedHomeserver: 'https://x.test', username: user, password: 'pw');
    await c.read(loginStateProvider.future);
    await c.read(authGatewayProvider.future);
  }

  Future<void> logout() async {
    await c.read(authProvider.notifier).logout();
    await c.read(loginStateProvider.future);
  }

  Future<List<GroupModel>> groups() =>
      c.read(groupsDaoProvider).getAllGroups();

  test('two accounts never see each other\'s groups; re-login restores',
      () async {
    // Keep a live UI-style subscription across all switches: it must follow
    // the account without ever hitting the closed previous DB.
    final errors = <Object>[];
    final sub = c.listen<AsyncValue<List<GroupModel>>>(
        ledgerGroupsProvider, (_, next) {
      if (next.hasError) errors.add(next.error!);
    });
    addTearDown(sub.close);

    await login('alice');
    expect(c.read(accountUserIdProvider), '@alice:x.test');
    await c.read(groupsDaoProvider).upsertGroupLww(const GroupsCompanion(
        roomId: Value('g-alice'), name: Value('Alice trip'),
        updatedAt: Value(1)));
    expect((await groups()).map((g) => g.name), ['Alice trip']);

    await logout();
    expect(c.read(accountUserIdProvider), isNull);
    // Signed out: no ledger DB is open; reads are empty, writes are refused.
    expect(await groups(), isEmpty);
    await expectLater(
        c.read(groupsDaoProvider).upsertGroupLww(const GroupsCompanion(
            roomId: Value('x'), name: Value('x'), updatedAt: Value(1))),
        throwsA(isA<StateError>()));
    expect(await c.read(onboardingSeenStreamProvider.future), isTrue);

    await login('bob');
    expect(await groups(), isEmpty);

    await logout();
    await login('alice');
    expect((await groups()).map((g) => g.name), ['Alice trip']);
    expect(
        await c.read(ledgerGroupsProvider.future),
        isA<List<GroupModel>>()
            .having((l) => l.map((g) => g.roomId), 'ids', ['g-alice']));

    expect(opened, [
      accountDatabaseName('@alice:x.test'),
      accountDatabaseName('@bob:x.test'),
      accountDatabaseName('@alice:x.test'),
    ]);
    expect(errors.whereType<StateError>().where(
        (e) => '$e'.contains('re-open')), isEmpty);
  });

  test('re-validating the login state keeps the same DB instance', () async {
    await login('alice');
    final db = c.read(appDatabaseProvider);
    c.invalidate(loginStateProvider);
    await c.read(loginStateProvider.future);
    expect(identical(c.read(appDatabaseProvider), db), isTrue);
    expect(opened, hasLength(1));
  });

  test('SyncEngine and LedgerSyncer restart on account switch', () async {
    c.listen(syncEngineProvider, (_, _) {});
    c.listen(ledgerSyncerProvider, (_, _) {});
    await login('alice');
    final engine = c.read(syncEngineProvider);
    final syncer = c.read(ledgerSyncerProvider);
    await logout();
    await login('bob');
    expect(identical(c.read(syncEngineProvider), engine), isFalse);
    expect(identical(c.read(ledgerSyncerProvider), syncer), isFalse);
  });

  test('onboarding flag is per account', () async {
    await login('alice');
    expect(await c.read(onboardingSeenStreamProvider.future), isFalse);
    await c.read(onboardingControllerProvider.notifier).markSeen();
    await logout();
    await login('bob');
    expect(await c.read(onboardingSeenStreamProvider.future), isFalse);
    await logout();
    await login('alice');
    expect(await c.read(onboardingSeenStreamProvider.future), isTrue);
  });
}
