/// G52 step 5: opening a link channel (§6.1, §6.3) — own claim dropped
/// (no `local:self` ever leaves the device), "me" set, `pendingSign` rows
/// become plain unsigned link versions, Matrix groups refused.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/link/group_policy.dart';
import 'package:money_ledger/core/link/link_channel.dart';
import 'package:money_ledger/core/link/link_uri.dart';
import 'package:money_ledger/core/link/nostr/nostr_event.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import '../../helpers/in_memory_database.dart';

const _now = 1792000000000;

void main() {
  late AppDatabase db;
  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  Future<void> seed({
    bool signedMeta = false,
    bool pending = false,
    String? otherClaim,
  }) async {
    await GroupsDao(db).upsertGroupLww(
      groupCompanion(
        GroupModel(
          roomId: 'G',
          name: 'Trip',
          currency: 'EUR',
          updatedAt: 10,
          pendingSign: pending,
          sig: signedMeta
              ? const RecordSignature(
                  user: '@a:x.org',
                  device: 'D',
                  key: 'k',
                  sig: 's',
                )
              : null,
        ),
      ),
    );
    for (final (pid, claim) in [('p1', kLocalAccountId), ('p2', otherClaim)]) {
      await MembersDao(db).upsertMemberLww(
        memberCompanion(
          MemberModel(
            groupId: 'G',
            userId: pid,
            displayName: pid,
            matrixId: claim,
            status: 'active',
            updatedAt: 10,
            pendingSign: pending,
          ),
        ),
      );
    }
    await ExpensesDao(db).upsertExpenseLww(
      expenseCompanion(
        ExpenseModel(
          id: 'e1',
          roomId: 'G',
          description: 'Dinner',
          amountCents: 1000,
          currency: 'EUR',
          paidBy: 'p1',
          splitsJson: '{"p1":500,"p2":500}',
          createdAt: 10,
          updatedAt: 10,
          pendingSign: pending,
        ),
      ),
    );
  }

  test('local mode group: the local:self claim is dropped (new version, '
      'by = me), "me" = that participant, pendingSign rows become plain '
      'link versions, a fresh secret + Nostr key', () async {
    await seed(pending: true);
    final ch = await openLinkChannel(
      db,
      'G',
      identity: kLocalAccountId,
      clock: () => _now,
    );
    expect(ch.myParticipantId, 'p1');
    expect(ch.epoch, 1);
    expect(decodeLinkSecret(ch.secret), hasLength(32));
    expect(isValidNostrPrivateKey(ch.nostrPriv), isTrue);
    expect(ch.openedAt, _now);

    final members = {
      for (final m in await MembersDao(db).getMembers('G')) m.userId: m,
    };
    expect(members['p1']!.matrixId, isNull);
    expect(members['p1']!.updatedAt, _now);
    expect(members['p1']!.linkAuthor, 'p1');
    expect(members['p1']!.pendingSign, isFalse);
    expect(members['p2']!.pendingSign, isFalse);
    expect(members['p2']!.updatedAt, 10);
    expect((await GroupsDao(db).getGroup('G'))!.pendingSign, isFalse);
    final e = (await ExpensesDao(db).getAllExpensesForGroup('G')).single;
    expect(e.pendingSign, isFalse);
    expect(e.updatedAt, 10);
    expect(e.sig, isNull);

    expect(await LinkDao(db).isLinkOnly('G'), isTrue);
    expect((await LinkDao(db).policyOf('G')).policy, GroupPolicy.linkOnly);
    // Opening again returns the same channel, untouched.
    final again = await openLinkChannel(db, 'G', identity: kLocalAccountId);
    expect(again.secret, ch.secret);
    expect(again.nostrPriv, ch.nostrPriv);
  });

  test(
    'a signed-in device: its own MXID claim is dropped the same way',
    () async {
      await seed();
      // p2 is claimed by this device's account instead.
      await MembersDao(db).upsertMemberLww(
        memberCompanion(
          const MemberModel(
            groupId: 'G',
            userId: 'p1',
            displayName: 'p1',
            status: 'active',
            updatedAt: 11,
          ),
        ),
      );
      await MembersDao(db).upsertMemberLww(
        memberCompanion(
          const MemberModel(
            groupId: 'G',
            userId: 'p2',
            displayName: 'p2',
            matrixId: '@me:x.org',
            status: 'active',
            updatedAt: 11,
          ),
        ),
      );
      final ch = await openLinkChannel(db, 'G', identity: '@me:x.org');
      expect(ch.myParticipantId, 'p2');
      final members = await MembersDao(db).getMembers('G');
      expect(members.every((m) => m.matrixId == null), isTrue);
    },
  );

  test('refuses an unknown group, a signed (Matrix) group and a group '
      'another Matrix account claims a participant of', () async {
    await expectLater(
      openLinkChannel(db, 'nope', identity: kLocalAccountId),
      throwsA(
        isA<LinkChannelException>().having(
          (e) => e.kind,
          'kind',
          LinkChannelError.noGroup,
        ),
      ),
    );
    await seed(signedMeta: true);
    await expectLater(
      openLinkChannel(db, 'G', identity: kLocalAccountId),
      throwsA(
        isA<LinkChannelException>().having(
          (e) => e.kind,
          'kind',
          LinkChannelError.signedGroup,
        ),
      ),
    );
    expect(await LinkDao(db).getChannel('G'), isNull);

    final other = openTestDatabase();
    addTearDown(other.close);
    db = other;
    await seed(otherClaim: '@bob:x.org');
    await expectLater(
      openLinkChannel(db, 'G', identity: kLocalAccountId),
      throwsA(
        isA<LinkChannelException>().having(
          (e) => e.kind,
          'kind',
          LinkChannelError.matrixMembers,
        ),
      ),
    );
    // Nothing was rewritten (one transaction).
    final p1 = (await MembersDao(
      db,
    ).getMembers('G')).firstWhere((m) => m.userId == 'p1');
    expect(p1.matrixId, kLocalAccountId);
    expect(await LinkDao(db).getChannel('G'), isNull);
  });
}
