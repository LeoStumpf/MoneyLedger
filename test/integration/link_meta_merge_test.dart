/// G57 (C1) over the fake Nostr relays: in a link-only group (no account
/// on either phone) a rename on one phone and a new custom category +
/// exchange rates on the other, written before either saw the other's
/// snapshot, all survive on both phones — the merging phone writes the
/// merge as its own unsigned link version, and both end on the same meta.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/link/nostr/nostr_event.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/exchange_rates.dart';
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/core/link/nostr/nip11.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_relay_network.dart';
import '../helpers/in_memory_database.dart';

/// Real time: `GroupCreator` stamps with the wall clock.
final _t0 = DateTime.now().millisecondsSinceEpoch;

class _NoInfo implements RelayInfoFetcher {
  @override
  Future<RelayInfo> fetch(String relay) async => const RelayInfo();
}

void main() {
  late FakeRelayNetwork net;
  late List<ProviderContainer> live;

  setUp(() {
    net = FakeRelayNetwork(nowSeconds: () => _t0 ~/ 1000);
    live = [];
  });

  ({ProviderContainer c, AppDatabase db}) device() {
    final db = openTestDatabase();
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerIdentityProvider.overrideWithValue(kLocalAccountId),
        localModeActiveProvider.overrideWithValue(true),
        ledgerTransportProvider.overrideWith(
          (ref) async => LocalOnlyTransport('local'),
        ),
        linkRelayConnectorProvider.overrideWithValue(net),
        linkRelayInfoFetcherProvider.overrideWithValue(_NoInfo()),
        linkClockProvider.overrideWithValue(
          () => DateTime.now().millisecondsSinceEpoch,
        ),
        // Publishing only when the test says so (publishAll): the edits
        // below are concurrent — neither phone has seen the other's.
        linkPublishDebounceProvider.overrideWithValue(const Duration(hours: 1)),
        linkPublishMinIntervalProvider.overrideWithValue(Duration.zero),
        linkAppLifecycleProvider.overrideWithValue(false),
        linkVerifySignaturesProvider.overrideWithValue(false),
        linkAppVersionProvider.overrideWith((ref) async => 'test'),
      ],
    );
    live.add(c);
    addTearDown(() async {
      live.remove(c);
      c.dispose();
      await db.close();
    });
    c.listen(linkSyncEngineProvider, (_, _) {});
    c.listen(groupEditorProvider, (_, _) {});
    return (c: c, db: db);
  }

  /// Publish what changed on every phone and let the relays deliver —
  /// [rounds] times (a merge written on receipt is published next round).
  Future<void> exchange({int rounds = 3}) async {
    for (var i = 0; i < rounds; i++) {
      for (final c in live) {
        await c.read(linkSyncEngineProvider).publishAll();
      }
      await net.settle();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await net.settle();
    }
  }

  test(
    'rename + category + rates on two phones: both keep every change',
    () async {
      const g = 'G';
      final a = device();
      await a.c.read(linkSyncEngineProvider).ready;
      await GroupsDao(a.db).upsertGroupLww(
        groupCompanion(
          GroupModel(
            roomId: g,
            name: 'Trip',
            currency: 'EUR',
            updatedAt: _t0 - 5000,
            pendingSign: true,
          ),
        ),
      );
      for (final (id, name, claim) in [
        ('p1', 'Anna', kLocalAccountId),
        ('p2', 'Ben', null),
      ]) {
        await MembersDao(a.db).upsertMemberLww(
          memberCompanion(
            MemberModel(
              groupId: g,
              userId: id,
              displayName: name,
              matrixId: claim,
              status: 'active',
              updatedAt: _t0 - 5000,
              pendingSign: true,
            ),
          ),
        );
      }
      final ch = await a.c.read(linkChannelOpenerProvider)(g);
      await exchange(rounds: 1);

      final b = device();
      await b.c.read(linkSyncEngineProvider).ready;
      await LinkDao(b.db).putChannel(
        LinkChannelModel(
          groupId: g,
          epoch: 1,
          secret: ch.secret,
          nostrPriv: generateNostrPrivateKey(),
          openedAt: _t0,
          myParticipantId: 'p2',
        ),
      );
      await b.c.read(linkSyncEngineProvider).refresh(groupId: g);
      await exchange(rounds: 1);
      expect((await GroupsDao(b.db).getGroup(g))!.name, 'Trip');

      // Concurrent: neither phone publishes before both edited.
      await a.c
          .read(groupEditorProvider.notifier)
          .edit(g, name: 'Ski trip', currency: 'EUR');
      final bEditor = b.c.read(groupEditorProvider.notifier);
      final dog = await bEditor.addCategory(g, name: 'Dog', icon: 'pets');
      await bEditor.setExchangeRates(
        g,
        ExchangeRates(base: 'EUR', rates: const {'CHF': '1.1'}),
      );
      expect(a.c.read(groupEditorProvider).hasError, isFalse);
      expect(b.c.read(groupEditorProvider).hasError, isFalse);
      expect((await GroupsDao(a.db).getGroup(g))!.categories, isEmpty);
      expect((await GroupsDao(b.db).getGroup(g))!.name, 'Trip');

      await exchange();
      final ma = (await GroupsDao(a.db).getGroup(g))!;
      final mb = (await GroupsDao(b.db).getGroup(g))!;
      for (final m in [ma, mb]) {
        expect(m.name, 'Ski trip');
        expect(m.categories.map((c) => c.id), [dog]);
        expect(m.exchangeRates?.rates, {'CHF': '1.1'});
        expect(m.sig, isNull); // link versions stay unsigned
        expect(m.link, isNull);
      }
      expect(groupMetaVersion(ma), groupMetaVersion(mb));
    },
  );
}
