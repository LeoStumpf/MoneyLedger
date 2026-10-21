/// G53: devices on one fake Matrix network **and** one fake relay network —
/// Matrix accounts (ledger syncer + sync engine + link sync engine) and
/// local-mode devices (link sync engine only) — for mixed-group tests.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/link/link_self_claim.dart';
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/core/link/nostr/nip11.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/local_adoption.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/link/link_join.dart';

import 'fake_ledger_network.dart';
import 'fake_relay_network.dart';
import 'in_memory_database.dart';

class _NoInfo implements RelayInfoFetcher {
  @override
  Future<RelayInfo> fetch(String relay) async => const RelayInfo();
}

/// One device of a [MixedHarness].
class MixedDevice {
  MixedDevice(this.c, this.db, this.identity);
  final ProviderContainer c;
  final AppDatabase db;
  final String identity;
  bool stopped = false;

  LinkSyncEngine get engine => c.read(linkSyncEngineProvider);
}

class MixedHarness {
  MixedHarness()
    : relays = FakeRelayNetwork(
        nowSeconds: () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
      matrix = FakeMatrixNetwork();

  final FakeRelayNetwork relays;
  final FakeMatrixNetwork matrix;
  final List<MixedDevice> live = [];

  /// A device of [identity] (an MXID or [kLocalAccountId]) on [db] (a
  /// fresh in-memory DB by default). Torn down with the test.
  MixedDevice device(String identity, {AppDatabase? db}) {
    final theDb = db ?? openTestDatabase();
    final local = identity == kLocalAccountId;
    // A device without an account verifies the fake device signatures the
    // way LocalOnlyTransport verifies Ed25519 ones.
    final verifier = matrix.keys.unlistedCrypto('@v:x.org', 'V');
    Future<LedgerTransport> transport() async => local
        ? LocalOnlyTransport('local', verify: verifier.verify)
        : matrix.clientFor(identity);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(theDb),
        ledgerIdentityProvider.overrideWithValue(identity),
        localModeActiveProvider.overrideWithValue(local),
        ledgerTransportProvider.overrideWith((ref) => transport()),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
        linkRelayConnectorProvider.overrideWithValue(relays),
        linkRelayInfoFetcherProvider.overrideWithValue(_NoInfo()),
        linkPublishDebounceProvider.overrideWithValue(
          const Duration(milliseconds: 1),
        ),
        linkPublishMinIntervalProvider.overrideWithValue(Duration.zero),
        linkAppLifecycleProvider.overrideWithValue(false),
        linkVerifySignaturesProvider.overrideWithValue(false),
        linkAppVersionProvider.overrideWith((ref) async => 'test'),
      ],
    );
    final d = MixedDevice(c, theDb, identity);
    live.add(d);
    addTearDown(() async {
      stop(d);
      await theDb.close();
    });
    if (!local) {
      c.listen(ledgerSyncerProvider, (_, _) {});
      c.listen(syncEngineProvider, (_, _) {});
    }
    c.listen(linkSyncEngineProvider, (_, _) {});
    return d;
  }

  void stop(MixedDevice d) {
    if (d.stopped) return;
    d.stopped = true;
    live.remove(d);
    d.c.dispose();
  }

  /// Until both networks are quiet and every engine idle (3 rounds).
  Future<void> settle() async {
    final sw = Stopwatch()..start();
    var quiet = 0;
    while (quiet < 3) {
      await matrix.settle();
      await relays.settle();
      await Future<void>.delayed(const Duration(milliseconds: 3));
      if (live.every((d) => d.engine.isIdle)) {
        quiet++;
      } else {
        quiet = 0;
      }
      if (sw.elapsed > const Duration(seconds: 30)) fail('never idle');
    }
  }

  /// A local-mode device joins [group] with [secret] — as the existing
  /// participant [as], else as a new person [name]. Returns its "me".
  Future<String> join(
    MixedDevice d,
    String group,
    String secret, {
    String? as,
    String name = 'Someone',
  }) async {
    await d.engine.ready;
    await d.engine.join(group, secret);
    await chooseLinkParticipant(
      d.db,
      group,
      participantId: as,
      newName: name,
      clock: () => DateTime.now().millisecondsSinceEpoch,
    );
    await settle();
    return (await LinkDao(d.db).getChannel(group))!.myParticipantId!;
  }

  /// "Connect a Matrix account": [local]'s ledger moves into [mxid]'s
  /// account DB (G40), then the pending self-claims run and are relayed.
  Future<MixedDevice> connect(MixedDevice local, String mxid) async {
    stop(local);
    final account = openTestDatabase();
    final crypto = matrix.clientFor(mxid).crypto;
    await adoptLocalLedger(
      target: account,
      local: local.db,
      mxid: mxid,
      crypto: crypto,
    );
    final d = device(mxid, db: account);
    await settle();
    final claims = await claimLinkParticipants(
      db: account,
      mxid: mxid,
      crypto: crypto,
    );
    await relayLinkSelfClaims(
      claims,
      members: MembersDao(account),
      transport: matrix.clientFor(mxid),
    );
    expect(await SettingsDao(account).linkSelfClaimsPending(), isEmpty);
    await settle();
    return d;
  }
}
