/// G53 step 3 (`docs/design/no-login-sharing.md` §10.1 "Link participant
/// joins Matrix", "Link → Matrix"): a person who used a link group without
/// an account connects a Matrix account — the adoption marks the group, the
/// account's device signs a claim of its link participant (+ in a link-only
/// group a signed meta keeping the link → mixed), the link peers and the
/// group's Matrix members accept it (scoped exception), and from then on
/// the account is a normal Matrix member there.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/link/group_policy.dart';
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
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/link/link_join.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/fake_relay_network.dart';
import '../helpers/in_memory_database.dart';

const _alice = '@alice:x.org';
const _ben = '@ben:x.org';

class _NoInfo implements RelayInfoFetcher {
  @override
  Future<RelayInfo> fetch(String relay) async => const RelayInfo();
}

class Dev {
  Dev(this.c, this.db, this.identity);
  final ProviderContainer c;
  final AppDatabase db;
  final String identity;
  bool disposed = false;

  LinkSyncEngine get engine => c.read(linkSyncEngineProvider);
}

void main() {
  late FakeRelayNetwork relays;
  late FakeMatrixNetwork matrix;
  late List<Dev> live;

  setUp(() {
    relays = FakeRelayNetwork(
      nowSeconds: () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    matrix = FakeMatrixNetwork();
    live = [];
  });

  Dev device(String identity, {AppDatabase? db}) {
    final theDb = db ?? openTestDatabase();
    final local = identity == kLocalAccountId;
    final verifier = matrix.keys.unlistedCrypto('@v:x.org', 'V');
    Future<LedgerTransport> transport() async => local
        ? LocalOnlyTransport('Ben', verify: verifier.verify)
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
    final d = Dev(c, theDb, identity);
    live.add(d);
    addTearDown(() async {
      if (!d.disposed) {
        live.remove(d);
        c.dispose();
      }
      await theDb.close();
    });
    if (!local) {
      c.listen(ledgerSyncerProvider, (_, _) {});
      c.listen(syncEngineProvider, (_, _) {});
    }
    c.listen(linkSyncEngineProvider, (_, _) {});
    return d;
  }

  void stop(Dev d) {
    d.disposed = true;
    live.remove(d);
    d.c.dispose();
  }

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

  /// Ben (local mode) joins [group] with [secret] as a new person "Ben";
  /// returns his participant id.
  Future<String> benJoins(Dev ben, String group, String secret) async {
    await ben.engine.ready;
    await ben.engine.join(group, secret);
    await chooseLinkParticipant(
      ben.db,
      group,
      newName: 'Ben',
      clock: () => DateTime.now().millisecondsSinceEpoch,
    );
    await settle();
    return (await LinkDao(ben.db).getChannel(group))!.myParticipantId!;
  }

  /// "Connect a Matrix account": Ben's local ledger moves into @ben's
  /// account DB, then the pending self-claims run and are relayed.
  Future<Dev> benConnects(Dev benLocal) async {
    stop(benLocal);
    final account = openTestDatabase();
    final crypto = matrix.clientFor(_ben).crypto;
    final r = await adoptLocalLedger(
      target: account,
      local: benLocal.db,
      mxid: _ben,
      crypto: crypto,
    );
    expect(r.groupIds, isNotEmpty);
    expect(await SettingsDao(account).linkSelfClaimsPending(), r.groupIds);
    final ben = device(_ben, db: account);
    await settle();
    final claims = await claimLinkParticipants(
      db: account,
      mxid: _ben,
      crypto: crypto,
    );
    expect(claims, hasLength(1));
    await relayLinkSelfClaims(
      claims,
      members: MembersDao(account),
      transport: matrix.clientFor(_ben),
    );
    await settle();
    return ben;
  }

  test('link-only group: Ben connects Matrix → signed claim + signed meta '
      '(link kept) → mixed; Anna (no account) accepts it and can no longer '
      'rename the group', () async {
    final anna = device(kLocalAccountId);
    await anna.engine.ready;
    final sub = anna.c.listen(groupCreatorProvider, (_, _) {});
    final g = (await anna.c
        .read(groupCreatorProvider.notifier)
        .create('Hut', 'EUR'))!;
    sub.close();
    final channel = await anna.engine.openChannel(g);
    await settle();
    expect(await LinkDao(anna.db).isLinkOnly(g), isTrue);

    final benLocal = device(kLocalAccountId);
    final benId = await benJoins(benLocal, g, channel.secret);
    final ben = await benConnects(benLocal);

    // Ben's account: claimed, signed meta with the same link → mixed.
    final metaB = (await GroupsDao(ben.db).getGroup(g))!;
    expect(metaB.sig?.user, _ben);
    expect(metaB.link?.secret, channel.secret);
    expect((await LinkDao(ben.db).policyOf(g)).policy, GroupPolicy.mixed);
    final mine = claimedBy(await MembersDao(ben.db).getMembers(g), _ben)!;
    expect(mine.userId, benId);
    expect(mine.sig?.user, _ben);
    expect(await SettingsDao(ben.db).linkSelfClaimsPending(), isEmpty);

    // Anna, on the link only, took both over.
    final metaA = (await GroupsDao(anna.db).getGroup(g))!;
    expect(metaA.sig?.user, _ben);
    expect((await LinkDao(anna.db).policyOf(g)).policy, GroupPolicy.mixed);
    final benAtAnna = (await MembersDao(
      anna.db,
    ).getMembers(g)).firstWhere((m) => m.userId == benId);
    expect(benAtAnna.matrixId, _ben);

    // Anna can't change the meta any more (needs a signature).
    final editor = anna.c.listen(groupEditorProvider, (_, _) {});
    await anna.c
        .read(groupEditorProvider.notifier)
        .edit(g, name: 'Renamed', currency: 'EUR');
    expect(anna.c.read(groupEditorProvider).error, isNotNull);
    editor.close();

    // Ben renames — signed — and Anna gets it via the link.
    final benEditor = ben.c.listen(groupEditorProvider, (_, _) {});
    await ben.c
        .read(groupEditorProvider.notifier)
        .edit(g, name: 'Mountain hut', currency: 'EUR');
    benEditor.close();
    await settle();
    expect((await GroupsDao(anna.db).getGroup(g))!.name, 'Mountain hut');
    expect(
      (await GroupsDao(anna.db).getGroup(g))!.link?.secret,
      channel.secret,
      reason: 'the rename keeps the link open',
    );
  });

  test('mixed group: Ben connects Matrix → his claim reaches Alice over '
      'Matrix (scoped exception) — he is a Matrix member now', () async {
    final a = device(_alice);
    await settle();
    final sub = a.c.listen(groupCreatorProvider, (_, _) {});
    final g = (await a.c
        .read(groupCreatorProvider.notifier)
        .create('Rome', 'EUR'))!;
    sub.close();
    final channel = await a.c.read(mixedLinkOpenerProvider)(g);
    await settle();
    final benLocal = device(kLocalAccountId);
    final benId = await benJoins(benLocal, g, channel.secret);
    // Alice stops reading the relays: the claim must arrive over Matrix.
    a.engine.dispose();
    await LinkDao(a.db).deleteChannel(g);

    final ben = await benConnects(benLocal);
    expect(
      (await LinkDao(ben.db).policyOf(g)).policy,
      GroupPolicy.mixed,
      reason: 'already mixed: no new meta',
    );
    final people = await MembersDao(a.db).getMembers(g);
    final benAtAlice = people.firstWhere((m) => m.userId == benId);
    expect(benAtAlice.matrixId, _ben);
    expect(benAtAlice.sig?.user, _ben);
    expect(await MembersDao(a.db).activeClaimedMatrixIds(g), contains(_ben));
  });

  test('isSenderAuthorized: the self-claim of an unclaimed active participant '
      'by a non-member only while the link is open', () {
    const members = [
      MemberModel(
        groupId: 'g',
        userId: 'p1',
        displayName: 'Ben',
        status: 'active',
        updatedAt: 1,
      ),
      MemberModel(
        groupId: 'g',
        userId: 'p2',
        displayName: 'Cleo',
        matrixId: '@cleo:x.org',
        status: 'active',
        updatedAt: 1,
      ),
    ];
    bool ok(String pid, {bool linkOpen = true}) =>
        LedgerSyncer.isSenderAuthorized(
          type: 'com.moneyledger.member',
          senderId: _ben,
          content: {
            'group': 'g',
            'participant_id': pid,
            'matrix_id': _ben,
            'status': 'active',
          },
          members: members,
          groupKnown: true,
          linkOpen: linkOpen,
        );
    expect(ok('p1'), isTrue);
    expect(ok('p1', linkOpen: false), isFalse);
    expect(ok('p2'), isFalse, reason: 'claimed by someone else');
    expect(ok('p9'), isFalse, reason: 'no such participant');
  });
}
