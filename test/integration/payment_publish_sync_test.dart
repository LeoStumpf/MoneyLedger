/// G74 distribution: my payment details from the settings go into my
/// participant of every group I'm active in (signed + relayed in Matrix
/// groups, a link version in link groups, nothing in local mode's own
/// groups), follow a change / removal, are re-published after a stale
/// editor's version, and never fight my own other device.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/payment/payment_publisher.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/payment_details.dart';

import '../helpers/eventually.dart';
import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const _a = '@alice:x.org';
const _b = '@bob:y.org';
const _x = PaymentDetails(name: 'Alice A', iban: 'DE89370400440532013000');
const _y = PaymentDetails(paypalMe: 'alicea');

void main() {
  group('publishablePayment', () {
    test('keeps the usable parts only', () {
      expect(publishablePayment(null), isNull);
      expect(publishablePayment(_x), _x);
      // A holder without an IBAN, a BIC without an IBAN: nothing usable.
      expect(publishablePayment(const PaymentDetails(name: 'A')), isNull);
      expect(
        publishablePayment(const PaymentDetails(name: 'A', paypalMe: 'a')),
        const PaymentDetails(paypalMe: 'a'),
      );
      // An invalid IBAN is never published (peers would refuse it).
      expect(
        publishablePayment(
          const PaymentDetails(name: 'A', iban: 'DE00370400440532013000'),
        ),
        isNull,
      );
    });
  });

  ({ProviderContainer c, AppDatabase db}) makeUser(
    FakeMatrixNetwork net,
    String userId, {
    bool publisher = true,
  }) {
    final db = openTestDatabase();
    net.clientFor(userId);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(userId)),
        ledgerIdentityProvider.overrideWithValue(userId),
        paymentPublishDebounceProvider.overrideWithValue(
          const Duration(milliseconds: 1),
        ),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    c.listen(ledgerSyncerProvider, (_, _) {});
    if (publisher) c.listen(paymentPublisherProvider, (_, _) {});
    return (c: c, db: db);
  }

  Future<PaymentDetails?> paymentOf(
    AppDatabase db,
    String groupId,
    String mxid,
  ) async => claimedBy(await MembersDao(db).getMembers(groupId), mxid)?.payment;

  test('details reach the others, follow a change and a removal', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, _a);
    final bob = makeUser(net, _b);
    await net.settle();
    final groupId = (await alice.c
        .read(groupCreatorProvider.notifier)
        .create('Trip', 'EUR'))!;
    await alice.c.read(memberAdderProvider.notifier).add(groupId, _b);
    await net.settle();

    await SettingsDao(alice.db).setPaymentDetailsRaw(_x.encode());
    await eventually(() async => await paymentOf(bob.db, groupId, _a) == _x);
    final stored = claimedBy(await MembersDao(bob.db).getMembers(groupId), _a)!;
    expect(stored.sig?.user, _a); // signed by Alice herself
    // Bob's own participant carries nothing (he has no details).
    expect(await paymentOf(bob.db, groupId, _b), isNull);

    await SettingsDao(alice.db).setPaymentDetailsRaw(_y.encode());
    await eventually(() async => await paymentOf(bob.db, groupId, _a) == _y);

    await SettingsDao(alice.db).clearPaymentDetails();
    await eventually(() async => await paymentOf(bob.db, groupId, _a) == null);
    await net.settle();
    expect(await paymentOf(alice.db, groupId, _a), isNull);
  });

  test('a group joined later gets them; a stale editor is answered with a '
      're-publish', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, _a);
    final bob = makeUser(net, _b, publisher: false);
    await SettingsDao(alice.db).setPaymentDetailsRaw(_x.encode());
    await net.settle();
    // Bob's group; he invites Alice (his device writes her claim — no
    // payment), Alice's device adds her details to it.
    final groupId = (await bob.c
        .read(groupCreatorProvider.notifier)
        .create('Flat', 'EUR'))!;
    await bob.c.read(memberAdderProvider.notifier).add(groupId, _a);
    await eventually(() async => await paymentOf(bob.db, groupId, _a) == _x);

    // Bob renames Alice from a copy without the details (a stale editor —
    // accepted by the gate): Alice's device writes them again.
    final mine = claimedBy(await MembersDao(bob.db).getMembers(groupId), _a)!;
    final stale = await signMember(
      net.clientFor(_b).crypto,
      MemberModel(
        groupId: groupId,
        userId: mine.userId,
        displayName: 'Ali',
        matrixId: _a,
        status: 'active',
        updatedAt: nextLwwClock(mine.updatedAt),
      ),
    );
    await MembersDao(bob.db).upsertMemberLww(memberCompanion(stale));
    await bob.c
        .read(memberAdderProvider.notifier)
        .rename(groupId, mine.userId, 'Alicia');
    await eventually(() async {
      final m = claimedBy(await MembersDao(bob.db).getMembers(groupId), _a);
      return m?.displayName == 'Alicia' && m?.payment == _x;
    });
  });

  test('my other device\'s version is left alone unless my settings '
      'changed', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, _a, publisher: false);
    await net.settle();
    final groupId = (await alice.c
        .read(groupCreatorProvider.notifier)
        .create('Solo', 'EUR'))!;
    final db = alice.db;
    final members = MembersDao(db);
    final mine = claimedBy(await members.getMembers(groupId), _a)!;
    // My second device (other settings) published X; it arrived here.
    final fromD2 = await signMember(
      net.clientFor(_a, device: 'D2').crypto,
      MemberModel(
        groupId: groupId,
        userId: mine.userId,
        displayName: mine.displayName,
        matrixId: _a,
        status: 'active',
        updatedAt: nextLwwClock(mine.updatedAt),
        payment: _x,
      ),
    );
    await members.upsertMemberLww(
      memberCompanion(fromD2),
      source: HistorySource.inbound,
    );
    final signer = LocalRecordSigner(
      Future.value(net.clientFor(_a)),
      policy: LinkDao(db).policyOf,
    );

    // This device has none and never published any: nothing written.
    var written = await publishPaymentDetails(
      db: db,
      myId: _a,
      details: null,
      signer: signer,
    );
    expect(written, isEmpty);
    expect(await paymentOf(db, groupId, _a), _x);

    // The user enters Y here: an explicit change wins.
    written = await publishPaymentDetails(
      db: db,
      myId: _a,
      details: _y,
      signer: signer,
    );
    expect(written.single.member.payment, _y);
    expect(await paymentOf(db, groupId, _a), _y);
    // Idempotent.
    expect(
      await publishPaymentDetails(
        db: db,
        myId: _a,
        details: _y,
        signer: signer,
      ),
      isEmpty,
    );
  });

  test('link group: a link version by me; local mode\'s own group: '
      'nothing', () async {
    final net = FakeMatrixNetwork();
    final alice = makeUser(net, _a, publisher: false);
    await net.settle();
    final linkGroup = (await alice.c
        .read(groupCreatorProvider.notifier)
        .create('Shared', 'EUR', viaLink: true))!;
    final db = alice.db;
    final signer = LocalRecordSigner(
      Future.value(net.clientFor(_a)),
      policy: LinkDao(db).policyOf,
    );
    final written = await publishPaymentDetails(
      db: db,
      myId: _a,
      details: _x,
      signer: signer,
    );
    final m = written.single.member;
    expect(written.single.groupId, linkGroup);
    expect(m.sig, isNull);
    expect(m.pendingSign, isFalse);
    expect(m.linkAuthor, m.userId); // the gate's "written by itself"
    expect(m.payment, _x);
    expect(writtenByParticipant(m), isTrue);

    // Local mode: a group of its own (claimed by local:self) gets nothing.
    final local = openTestDatabase();
    addTearDown(local.close);
    await GroupsDao(local).upsertGroupLww(
      groupCompanion(
        const GroupModel(
          roomId: 'g-local',
          name: 'Home',
          currency: 'EUR',
          updatedAt: 1,
        ),
      ),
    );
    await MembersDao(local).upsertMemberLww(
      memberCompanion(
        const MemberModel(
          groupId: 'g-local',
          userId: 'p1',
          displayName: 'Me',
          matrixId: kLocalAccountId,
          status: 'active',
          updatedAt: 1,
        ),
      ),
    );
    expect(
      await publishPaymentDetails(
        db: local,
        myId: kLocalAccountId,
        details: _x,
        signer: LocalRecordSigner(Future.value(net.clientFor(_a))),
      ),
      isEmpty,
    );
  });
}
