/// G17: participants added by MXID are named after the account's Matrix
/// profile display name (fallback: the localpart), and the one-off refresh
/// upgrades pre-G17 localpart names.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:x.org';
const carol = '@carol:x.org';

void main() {
  late AppDatabase db;
  late FakeMatrixNetwork net;

  setUp(() {
    db = openTestDatabase();
    net = FakeMatrixNetwork();
    net.clientFor(bob);
    net.clientFor(carol);
  });
  tearDown(() => db.close());

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(alice)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> seedGroup(Map<String, String> members) async {
    await GroupsDao(db).upsertGroupLww(
      const GroupsCompanion(
        roomId: Value('g1'),
        name: Value('Trip'),
        currency: Value('EUR'),
        updatedAt: Value(1),
      ),
    );
    for (final MapEntry(key: mxid, value: name) in members.entries) {
      await MembersDao(db).upsertMemberLww(
        memberCompanion(
          MemberModel(
            groupId: 'g1',
            userId: mxid,
            displayName: name,
            matrixId: mxid,
            status: 'active',
            updatedAt: 1,
          ),
        ),
      );
    }
  }

  Future<String> nameOf(String id) async => (await MembersDao(
    db,
  ).getMembers('g1')).firstWhere((m) => m.userId == id).displayName;

  test('the transport normalises profile names', () async {
    net.profiles[bob] = '  Bea  ';
    net.profiles[carol] = '   ';
    final t = net.clientFor(alice);
    expect(await t.profileName(bob), 'Bea');
    expect(await t.profileName(carol), isNull);
    expect(await t.profileName('@nobody:x.org'), isNull);
  });

  test('adding by MXID uses the profile display name', () async {
    net.profiles[bob] = 'Bea Müller';
    await seedGroup({alice: 'Alice'});
    final c = container();
    c.listen(memberAdderProvider, (_, _) {});
    await c.read(memberAdderProvider.notifier).add('g1', bob);
    await net.settle();
    expect(await nameOf(bob), 'Bea Müller');
    // The relayed member payload carries the name too.
    final bootstrap = net.sent.firstWhere((s) => s.type == bootstrapEventType);
    expect(bootstrap.targets, {bob});
  });

  test('without a profile name it falls back to the localpart', () async {
    await seedGroup({alice: 'Alice'});
    final c = container();
    c.listen(memberAdderProvider, (_, _) {});
    await c.read(memberAdderProvider.notifier).add('g1', carol);
    expect(await nameOf(carol), 'carol');
  });

  test('an explicitly given name wins over the profile', () async {
    net.profiles[bob] = 'Bea';
    await seedGroup({alice: 'Alice'});
    final c = container();
    c.listen(memberAdderProvider, (_, _) {});
    await c
        .read(memberAdderProvider.notifier)
        .add('g1', bob, displayName: 'Bobby');
    expect(await nameOf(bob), 'Bobby');
  });

  test('creating a group names the creator after their profile', () async {
    net.profiles[alice] = 'Alice A.';
    final c = container();
    c.listen(groupCreatorProvider, (_, _) {});
    await c.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    final group = (await GroupsDao(db).getAllGroups()).single;
    final me = (await MembersDao(db).getMembers(group.roomId)).single;
    expect(me.displayName, 'Alice A.');
  });

  test(
    'refresh upgrades localpart names, keeps chosen names, relays',
    () async {
      net.profiles
        ..[alice] = 'Alice A.'
        ..[bob] = 'Bea'
        ..[carol] = 'Caro';
      // alice + bob still have the old localpart default; carol was renamed.
      await seedGroup({alice: 'alice', bob: 'bob', carol: 'Carol C.'});
      final c = container();
      final renamed = await c.read(profileNameRefreshProvider.future);
      await net.settle();

      expect(renamed, 2);
      expect(await nameOf(alice), 'Alice A.');
      expect(await nameOf(bob), 'Bea');
      expect(await nameOf(carol), 'Carol C.');
      final relayed = net.sent
          .where((s) => s.type == memberEventType)
          .map((s) => s.content['name'])
          .toSet();
      expect(relayed, {'Alice A.', 'Bea'});
    },
  );

  test('refresh skips groups this account is not active in', () async {
    net.profiles[bob] = 'Bea';
    await seedGroup({bob: 'bob'}); // alice isn't a participant
    final c = container();
    expect(await c.read(profileNameRefreshProvider.future), 0);
    expect(await nameOf(bob), 'bob');
  });

  test('MemberModel.label falls back to the localpart, then the id', () {
    const named = MemberModel(
      groupId: 'g',
      userId: bob,
      displayName: 'Bea',
      status: 'active',
      updatedAt: 1,
    );
    const claimed = MemberModel(
      groupId: 'g',
      userId: 'p1',
      matrixId: bob,
      status: 'active',
      updatedAt: 1,
    );
    const local = MemberModel(
      groupId: 'g',
      userId: 'p-local',
      status: 'active',
      updatedAt: 1,
    );
    expect(named.label, 'Bea');
    expect(claimed.label, 'bob');
    expect(local.label, 'p-local');
  });
}
