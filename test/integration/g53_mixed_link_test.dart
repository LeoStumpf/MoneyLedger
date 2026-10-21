/// G53 step 2 end-to-end (`docs/design/no-login-sharing.md` §10.1
/// "Matrix → link"): a **Matrix group** gets an invite link — the opener
/// writes a signed meta with `link`, its Matrix members' devices bridge on
/// receipt (channel from the meta, "me" = their participant, publish +
/// read), a person without an account joins with the link and writes
/// unsigned versions that every Matrix device accepts ("via link") — also
/// relayed over Matrix — while the meta can't be changed without Matrix.
/// A reset writes a new signed meta: every Matrix device follows it, the
/// old link's holder is cut off.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/link/group_policy.dart';
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/core/link/nostr/nip11.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/features/link/link_join.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/fake_relay_network.dart';
import '../helpers/in_memory_database.dart';

const _alice = '@alice:x.org';
const _bob = '@bob:x.org';

class _NoInfo implements RelayInfoFetcher {
  @override
  Future<RelayInfo> fetch(String relay) async => const RelayInfo();
}

class Dev {
  Dev(this.c, this.db, this.identity);
  final ProviderContainer c;
  final AppDatabase db;
  final String identity;

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

  Dev device(String identity) {
    final db = openTestDatabase();
    final local = identity == kLocalAccountId;
    // A device without an account verifies the fake device signatures the
    // way LocalOnlyTransport verifies Ed25519 ones.
    final verifier = matrix.keys.unlistedCrypto('@v:x.org', 'V');
    Future<LedgerTransport> transport() async => local
        ? LocalOnlyTransport('Ben', verify: verifier.verify)
        : matrix.clientFor(identity);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
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
    final d = Dev(c, db, identity);
    live.add(d);
    addTearDown(() async {
      live.remove(d);
      c.dispose();
      await db.close();
    });
    if (!local) {
      c.listen(ledgerSyncerProvider, (_, _) {});
      c.listen(syncEngineProvider, (_, _) {});
    }
    c.listen(linkSyncEngineProvider, (_, _) {});
    return d;
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

  /// Alice's Matrix group with Bob in it; returns the group id.
  Future<String> matrixGroup(Dev a) async {
    final sub = a.c.listen(groupCreatorProvider, (_, _) {});
    final id = (await a.c
        .read(groupCreatorProvider.notifier)
        .create('Rome', 'EUR'))!;
    sub.close();
    final adder = a.c.listen(memberAdderProvider, (_, _) {});
    await a.c.read(memberAdderProvider.notifier).add(id, _bob);
    adder.close();
    await settle();
    return id;
  }

  Future<String> participantOf(Dev d, String group, String mxid) async =>
      claimedBy(await MembersDao(d.db).getMembers(group), mxid)!.userId;

  test('Invite by link in a Matrix group: signed meta with link, Matrix '
      'devices bridge, a link-only person joins and their unsigned changes '
      'reach every Matrix device', () async {
    final a = device(_alice);
    final b = device(_bob);
    await settle();
    final g = await matrixGroup(a);
    expect(await GroupsDao(b.db).getGroup(g), isNotNull);

    final channel = await a.c.read(mixedLinkOpenerProvider)(g);
    await settle();

    // Alice: signed meta with the link, mixed, channel "me" = her participant.
    final metaA = (await GroupsDao(a.db).getGroup(g))!;
    expect(metaA.sig, isNotNull);
    expect(metaA.link?.secret, channel.secret);
    expect(metaA.link?.epoch, 1);
    expect((await LinkDao(a.db).policyOf(g)).policy, GroupPolicy.mixed);
    expect(channel.myParticipantId, await participantOf(a, g, _alice));
    // Bob got the meta over Matrix and bridges with the same link.
    final bobChannel = (await LinkDao(b.db).getChannel(g))!;
    expect(bobChannel.secret, channel.secret);
    expect(bobChannel.myParticipantId, await participantOf(b, g, _bob));
    expect(bobChannel.lastPublishedHash, isNotNull, reason: 'Bob publishes');

    // Ben (no account) joins with the link and adds an expense.
    final ben = device(kLocalAccountId);
    await ben.engine.ready;
    await ben.engine.join(g, channel.secret);
    await chooseLinkParticipant(
      ben.db,
      g,
      newName: 'Ben',
      clock: () => DateTime.now().millisecondsSinceEpoch,
    );
    await settle();
    expect((await GroupsDao(ben.db).getGroup(g))!.name, 'Rome');
    expect((await LinkDao(ben.db).policyOf(g)).policy, GroupPolicy.mixed);
    final benId = (await LinkDao(ben.db).getChannel(g))!.myParticipantId!;
    final adder = ben.c.listen(expenseAdderProvider, (_, _) {});
    await ben.c
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: g,
          description: 'Pizza',
          amountCents: 3000,
          currency: 'EUR',
          paidBy: benId,
          splits: {benId: 3000},
        );
    adder.close();
    await settle();

    for (final d in [a, b]) {
      final pizza = (await ExpensesDao(
        d.db,
      ).getAllExpensesForGroup(g)).where((e) => e.description == 'Pizza');
      expect(pizza, hasLength(1), reason: d.identity);
      expect(pizza.single.sig, isNull);
      expect(pizza.single.linkAuthor, benId);
      final people = await MembersDao(d.db).getMembers(g);
      expect(people.map((m) => m.displayName), contains('Ben'));
    }

    // Ben can't rename the group (no signature) — nothing is written.
    final editor = ben.c.listen(groupEditorProvider, (_, _) {});
    await ben.c
        .read(groupEditorProvider.notifier)
        .edit(g, name: 'Hijack', currency: 'EUR');
    expect(
      ben.c.read(groupEditorProvider).error,
      isA<SignatureRequiredException>(),
    );
    editor.close();
    expect((await GroupsDao(ben.db).getGroup(g))!.name, 'Rome');

    // Alice's own write in the mixed group is signed and reaches Ben.
    final aAdder = a.c.listen(expenseAdderProvider, (_, _) {});
    final aliceId = await participantOf(a, g, _alice);
    await a.c
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: g,
          description: 'Museum',
          amountCents: 2000,
          currency: 'EUR',
          paidBy: aliceId,
          splits: {aliceId: 2000},
        );
    aAdder.close();
    await settle();
    final museum = (await ExpensesDao(
      ben.db,
    ).getAllExpensesForGroup(g)).where((e) => e.description == 'Museum');
    expect(museum.single.sig?.user, _alice);
  });

  test('a link-only change relayed over Matrix only: Bob (not bridged '
      'yet) accepts it from Alice in a mixed group', () async {
    final a = device(_alice);
    final b = device(_bob);
    await settle();
    final g = await matrixGroup(a);
    final channel = await a.c.read(mixedLinkOpenerProvider)(g);
    await settle();
    // Bob stops reading the relays: his channel is dropped and his engine
    // left alone; the unsigned version must reach him over Matrix.
    b.c.dispose();
    live.remove(b);
    final b2 = Dev(
      ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(b.db),
          ledgerIdentityProvider.overrideWithValue(_bob),
          ledgerTransportProvider.overrideWith(
            (ref) async => matrix.clientFor(_bob),
          ),
          pokeDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 1),
          ),
          syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
          linkSyncEnabledProvider.overrideWithValue(false),
        ],
      ),
      b.db,
      _bob,
    );
    addTearDown(b2.c.dispose);
    b2.c.listen(ledgerSyncerProvider, (_, _) {});
    b2.c.listen(syncEngineProvider, (_, _) {});
    await LinkDao(b.db).deleteChannel(g);

    final ben = device(kLocalAccountId);
    await ben.engine.ready;
    await ben.engine.join(g, channel.secret);
    await chooseLinkParticipant(
      ben.db,
      g,
      newName: 'Ben',
      clock: () => DateTime.now().millisecondsSinceEpoch,
    );
    await settle();
    // Alice got Ben's participant via the relay; her digest repairs Bob.
    await a.c.read(syncEngineProvider).broadcastDigests();
    await settle();
    final people = await MembersDao(b.db).getMembers(g);
    final benRow = people.where((m) => m.displayName == 'Ben');
    expect(benRow, hasLength(1), reason: 'accepted over Matrix (mixed)');
    expect(benRow.single.sig, isNull);
  });

  test('reset in a mixed group: a new signed meta, every Matrix device '
      'follows it, the old link is cut off', () async {
    final a = device(_alice);
    final b = device(_bob);
    await settle();
    final g = await matrixGroup(a);
    final first = await a.c.read(mixedLinkOpenerProvider)(g);
    await settle();
    final ben = device(kLocalAccountId);
    await ben.engine.ready;
    await ben.engine.join(g, first.secret);
    await chooseLinkParticipant(
      ben.db,
      g,
      newName: 'Ben',
      clock: () => DateTime.now().millisecondsSinceEpoch,
    );
    await settle();

    final second = await a.c.read(linkResetterProvider)(g);
    await settle();
    expect(second.secret, isNot(first.secret));
    expect((await GroupsDao(a.db).getGroup(g))!.link?.epoch, 2);
    expect((await LinkDao(b.db).getChannel(g))!.secret, second.secret);
    // Ben still holds the old link and the old meta — nothing reached him
    // that names the new secret.
    expect((await LinkDao(ben.db).getChannel(g))!.secret, first.secret);
    expect((await GroupsDao(ben.db).getGroup(g))!.link?.secret, first.secret);

    final aAdder = a.c.listen(expenseAdderProvider, (_, _) {});
    final aliceId = await participantOf(a, g, _alice);
    await a.c
        .read(expenseAdderProvider.notifier)
        .addExpense(
          roomId: g,
          description: 'After reset',
          amountCents: 500,
          currency: 'EUR',
          paidBy: aliceId,
          splits: {aliceId: 500},
        );
    aAdder.close();
    await settle();
    final benExpenses = await ExpensesDao(ben.db).getAllExpensesForGroup(g);
    expect(benExpenses.where((e) => e.description == 'After reset'), isEmpty);
    expect(
      (await ExpensesDao(
        b.db,
      ).getAllExpensesForGroup(g)).where((e) => e.description == 'After reset'),
      hasLength(1),
    );

    // Ben opens the new link (sent to him directly): switches and syncs.
    await ben.engine.switchLink(g, second.secret);
    await settle();
    expect(
      (await ExpensesDao(
        ben.db,
      ).getAllExpensesForGroup(g)).where((e) => e.description == 'After reset'),
      hasLength(1),
    );
    expect((await GroupsDao(ben.db).getGroup(g))!.link?.secret, second.secret);
  });
}
