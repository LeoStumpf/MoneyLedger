/// G52 step 4 (§6.4): a **link-only** group has no Matrix side — the
/// `SyncEngine` sends no digests / bootstraps / resync answers for it,
/// `LedgerSyncer` drops to-device records for it, local writes into it are
/// stored unsigned (not `pendingSign`, `by` = my link participant) and never
/// relayed, Matrix claims are refused, and `currentParticipant` falls back
/// to the channel's `my_participant_id`. End-to-end over the fake relay.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const _alice = '@alice:x.org';
const _bob = '@bob:x.org';

void main() {
  late FakeMatrixNetwork net;

  ({ProviderContainer c, AppDatabase db}) makeDevice(
    String userId, {
    String device = 'D1',
  }) {
    final db = openTestDatabase();
    net.clientFor(userId, device: device);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith(
          (ref) => net.clientFor(userId, device: device),
        ),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    container.listen(syncEngineProvider, (_, _) {});
    return (c: container, db: db);
  }

  LinkChannelModel channel(String group, {String? me}) => LinkChannelModel(
    groupId: group,
    epoch: 1,
    secret: 'c2VjcmV0',
    nostrPriv: '22' * 32,
    openedAt: 1,
    myParticipantId: me,
  );

  /// A link-only group 'L' (unsigned meta, unclaimed people, channel with
  /// "me" = p1) in [db].
  Future<void> seedLinkGroup(AppDatabase db) async {
    await db
        .into(db.groups)
        .insert(
          groupCompanion(
            const GroupModel(roomId: 'L', name: 'Link', currency: 'EUR'),
          ),
        );
    for (final pid in ['p1', 'p2']) {
      await db
          .into(db.members)
          .insert(
            memberCompanion(
              MemberModel(
                groupId: 'L',
                userId: pid,
                displayName: pid,
                status: 'active',
                updatedAt: 1,
              ),
            ),
          );
    }
    await LinkDao(db).putChannel(channel('L', me: 'p1'));
  }

  /// What [sender] sent about [group] over Matrix.
  List<String> sentTypesFor(String group, {String sender = _alice}) => [
    for (final s in net.sent)
      if (s.sender == sender && s.content['group'] == group) s.type,
  ];

  setUp(() => net = FakeMatrixNetwork());

  test('SyncEngine: no digest, bootstrap or resync answer for a link-only '
      'group; Matrix groups still sync', () async {
    final a = makeDevice(_alice);
    await net.settle();
    await seedLinkGroup(a.db);
    await a.c.read(groupCreatorProvider.notifier).create('Matrix', 'EUR');
    await net.settle();
    net.sent.clear();

    // Alice's other device asks for everything / for the link group.
    final d2 = net.clientFor(_alice, device: 'D2');
    await d2.sendToUsers(
      {_alice},
      resyncRequestEventType,
      {'v': protocolVersion, 'scope': 'all'},
    );
    await d2.sendToUsers(
      {_alice},
      resyncRequestEventType,
      {'v': protocolVersion, 'scope': 'group', 'group': 'L'},
    );
    // A digest naming the link group is never answered or repaired.
    await d2.sendToUsers(
      {_alice},
      digestEventType,
      {
        'v': protocolVersion,
        'group': 'L',
        'reply': false,
        'members': const {},
        'expenses': const {},
        'settlements': const {},
      },
    );
    // Only D1's answers count from here on (D2 shares the MXID).
    net.sent.clear();
    await a.c.read(syncEngineProvider).broadcastDigests();
    a.c.read(syncEngineProvider).pokeGroup('L');
    await net.settle();

    final fromAlice = net.sent.where((s) => s.sender == _alice);
    expect(
      fromAlice.where((s) => s.content['group'] == 'L'),
      isEmpty,
      reason: 'nothing about the link group leaves over Matrix',
    );
    expect(
      fromAlice.map((s) => s.type),
      containsAll([digestEventType, bootstrapEventType]),
      reason: 'the Matrix group is still digested / bootstrapped',
    );
  });

  test('SyncEngine: a digest for a group being joined (channel, no meta) '
      'asks for no resync', () async {
    final a = makeDevice(_alice);
    await net.settle();
    await LinkDao(a.db).putChannel(channel('J'));
    await net
        .clientFor(_bob)
        .sendToUsers(
          {_alice},
          digestEventType,
          {
            'v': protocolVersion,
            'group': 'J',
            'reply': false,
            'members': const {},
          },
        );
    await net.settle();
    expect(sentTypesFor('J'), isEmpty);
  });

  test('LedgerSyncer drops to-device records for a link-only group', () async {
    final a = makeDevice(_alice);
    await net.settle();
    // A group this device is joining by link (channel, nothing stored yet):
    // a TOFU bootstrap for it over Matrix would otherwise create it.
    await LinkDao(a.db).putChannel(channel('J'));
    final bob = net.clientFor(_bob);
    final meta = await signGroupMeta(
      bob.crypto,
      const GroupModel(roomId: 'J', name: 'Hijack', currency: 'EUR'),
    );
    final bobMember = await signMember(
      bob.crypto,
      const MemberModel(
        groupId: 'J',
        userId: _bob,
        matrixId: _bob,
        status: 'active',
        updatedAt: 1,
      ),
    );
    await bob.sendToUsers(
      {_alice},
      bootstrapEventType,
      buildBootstrapContent('J', meta, [bobMember], const [], const []),
    );
    await net.settle();
    expect(await a.c.read(groupsDaoProvider).getGroup('J'), isNull);
  });

  test('local writes in a link-only group: unsigned, not pendingSign, '
      '`by` = my participant, never relayed; Matrix claims refused', () async {
    final a = makeDevice(_alice);
    await net.settle();
    await seedLinkGroup(a.db);
    net.sent.clear();

    final adder = a.c.read(expenseAdderProvider.notifier);
    await adder.addExpense(
      roomId: 'L',
      description: 'Pizza',
      amountCents: 2000,
      currency: 'EUR',
      paidBy: 'p1',
      splits: {'p1': 1000, 'p2': 1000},
    );
    final ExpenseModel e =
        (await a.c.read(expensesDaoProvider).getExpensesForRoom('L')).single;
    expect(e.sig, isNull);
    expect(e.origin, isNull);
    expect(e.pendingSign, isFalse);
    expect(e.linkAuthor, 'p1');
    await adder.deleteExpense(e.id, 'L');

    await a.c.read(memberAdderProvider.notifier).rename('L', 'p2', 'Ben');
    final ben = (await a.c.read(membersDaoProvider).getMembers('L')).firstWhere(
      (m) => m.userId == 'p2',
    );
    expect((ben.displayName, ben.sig, ben.pendingSign), ('Ben', null, false));
    await a.c
        .read(groupEditorProvider.notifier)
        .edit('L', name: 'Renamed', currency: 'CHF');
    final meta = (await a.c.read(groupsDaoProvider).getGroup('L'))!;
    expect((meta.name, meta.sig, meta.pendingSign), ('Renamed', null, false));
    expect(await LinkDao(a.db).isLinkOnly('L'), isTrue);

    // A Matrix claim / invite isn't possible in a link-only group.
    final members = a.c.read(memberAdderProvider.notifier);
    await members.invite('L', _bob);
    expect(a.c.read(memberAdderProvider).error, isA<LinkOnlyGroupException>());
    await members.claim('L', 'p2', _bob);
    expect(a.c.read(memberAdderProvider).error, isA<LinkOnlyGroupException>());
    expect(
      (await a.c.read(membersDaoProvider).getMembers('L')).map(
        (m) => m.matrixId,
      ),
      everyElement(isNull),
    );

    await net.settle();
    expect(sentTypesFor('L'), isEmpty);
  });

  test('currentParticipant falls back to the link channel\'s "me" (active '
      'only)', () async {
    final a = makeDevice(_alice);
    await net.settle();
    await seedLinkGroup(a.db);
    final sub = a.c.listen(currentParticipantProvider('L'), (_, _) {});
    addTearDown(sub.close);
    expect(
      (await a.c.read(currentParticipantProvider('L').future))?.userId,
      'p1',
    );

    await a.c.read(memberRemoverProvider.notifier).remove('L', 'p1');
    await net.settle();
    a.c.invalidate(currentParticipantProvider('L'));
    expect(await a.c.read(currentParticipantProvider('L').future), isNull);

    // A group without a channel has no such fallback.
    expect(await a.c.read(currentParticipantProvider('nope').future), isNull);
  });
}
