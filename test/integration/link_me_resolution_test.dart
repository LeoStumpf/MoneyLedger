/// G52 step 13 device pass: in a link group nobody is claimed by this device
/// — "me" is the channel's `my_participant_id`. The group card / summary
/// (`groupOverviewProvider`) said "You're not involved" there, and the G58
/// *Exactly this state* option was never offered for link groups
/// (`planToSnapshot` looked for a claimed participant only); and a delete
/// there said "deleted from this device" in local mode.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/backup/backup_service.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/record_actions.dart'
    show deleteStaysOnDevice;
import 'package:money_ledger/features/groups/group_overview_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/history/group_reset.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/eventually.dart';
import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const ben = '@ben:x.org';

MemberModel _person(
  String pid,
  String name, {
  String status = 'active',
  int updatedAt = 1,
}) => MemberModel(
  groupId: 'g1',
  userId: pid,
  displayName: name,
  status: status,
  updatedAt: updatedAt,
);

ExpenseModel _expense(String id, String what, int cents) => ExpenseModel(
  id: id,
  roomId: 'g1',
  description: what,
  amountCents: cents,
  currency: 'EUR',
  paidBy: 'p1',
  splitsJson: '{"p1":${cents ~/ 2},"p2":${cents - cents ~/ 2}}',
  createdAt: 1000,
  updatedAt: 1000,
);

void main() {
  late AppDatabase db;
  late ProviderContainer c;

  setUp(() async {
    db = openTestDatabase();
    final net = FakeMatrixNetwork();
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(ben)),
        currentUserIdProvider.overrideWith((_) => ben),
        digestOnStartProvider.overrideWithValue(false),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    // A link group joined as "Ben" (p2): nobody is claimed by this device.
    await GroupsDao(db).upsertGroupLww(
      groupCompanion(
        const GroupModel(
          roomId: 'g1',
          name: 'Ferienhaus',
          currency: 'EUR',
          updatedAt: 1,
        ),
      ),
    );
    await MembersDao(
      db,
    ).upsertMemberLww(memberCompanion(_person('p1', 'Anna')));
    await MembersDao(db).upsertMemberLww(memberCompanion(_person('p2', 'Ben')));
    await ExpensesDao(
      db,
    ).upsertExpenseLww(expenseCompanion(_expense('e1', 'Einkauf', 3000)));
    await c
        .read(linkDaoProvider)
        .putChannel(
          const LinkChannelModel(
            groupId: 'g1',
            epoch: 1,
            secret: 'c2VjcmV0',
            nostrPriv:
                '1111111111111111111111111111111111111111111111111111111111111111',
            openedAt: 1,
            myParticipantId: 'p2',
          ),
        );
  });

  test('the group overview resolves "me" from the link channel', () async {
    c.listen(groupOverviewProvider('g1'), (_, _) {});
    await eventually(
      () =>
          c.read(groupOverviewProvider('g1')).me != null &&
          c.read(groupOverviewProvider('g1')).recordCount == 1,
    );
    final o = c.read(groupOverviewProvider('g1'));
    expect(o.me?.userId, 'p2');
    expect(o.myBalance, {'EUR': -1500});
  });

  test('myParticipantIn: the claimed participant wins, else the channel '
      "participant while it's active", () async {
    final members = MembersDao(db);
    final link = c.read(linkDaoProvider);
    expect((await myParticipantIn(members, link, 'g1', ben))?.userId, 'p2');
    expect(await myParticipantIn(members, link, 'other', ben), isNull);
    await members.upsertMemberLww(
      memberCompanion(_person('p2', 'Ben', status: 'removed', updatedAt: 2)),
    );
    expect(await myParticipantIn(members, link, 'g1', ben), isNull);
  });

  test(
    'a restore point offers "exactly this state" for a link group',
    () async {
      c.listen(groupResetServiceProvider, (_, _) {});
      c.listen(backupServiceProvider, (_, _) {});
      final snapshot = parseBackup(
        await c.read(backupServiceProvider).exportJson(account: ben, now: 1),
      );
      // Since the snapshot: another expense.
      await ExpensesDao(
        db,
      ).upsertExpenseLww(expenseCompanion(_expense('e2', 'Pizza', 4500)));
      final plan = await c
          .read(groupResetServiceProvider)
          .planToSnapshot(snapshot.groups.single, me: ben);
      expect(plan, isNotNull);
      expect(plan!.removed, 1);
    },
  );

  test(
    'local mode: a delete in a link group is not "only on this device"',
    () async {
      final link = c.read(linkDaoProvider);
      expect(
        await deleteStaysOnDevice(localMode: true, link: link, groupId: 'g1'),
        isFalse,
        reason: 'shared by link — the delete reaches everyone with the link',
      );
      expect(
        await deleteStaysOnDevice(localMode: true, link: link, groupId: 'solo'),
        isTrue,
      );
      expect(
        await deleteStaysOnDevice(
          localMode: false,
          link: link,
          groupId: 'solo',
        ),
        isFalse,
      );
    },
  );
}
