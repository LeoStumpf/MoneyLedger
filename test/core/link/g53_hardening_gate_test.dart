/// G53 hardening (Leo 2026-10-22, `docs/design/no-login-sharing.md` §10.1
/// "receiver checks"): the record gate refuses a **lock** that isn't
/// eligible (someone active at `locked_at` had no Matrix account then) and,
/// on a Matrix device's link path, a **claim** whose signing device the
/// homeserver doesn't list.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/link/group_policy.dart';
import 'package:money_ledger/core/link/link_uri.dart';
import 'package:money_ledger/core/link/lock_eligibility.dart';
import 'package:money_ledger/core/matrix/hmac_record_crypto.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_gate.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_verifier.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:x.org';
const eve = '@eve:x.org';
const ghost = '@ghost:nowhere.org';
const via = 'nostr:abcd';

final secret1 = encodeLinkSecret(List.filled(32, 1));

MemberModel member(
  String pid, {
  String? matrixId,
  int updatedAt = 1,
  String status = 'active',
  String group = 'g1',
}) => MemberModel(
  groupId: group,
  userId: pid,
  displayName: pid,
  matrixId: matrixId,
  status: status,
  updatedAt: updatedAt,
);

GroupModel meta({
  int updatedAt = 10,
  String name = 'Trip',
  GroupLink? link,
  int? lockedAt,
  String group = 'g1',
}) => GroupModel(
  roomId: group,
  name: name,
  currency: 'EUR',
  updatedAt: updatedAt,
  link: link,
  lockedAt: lockedAt,
);

void main() {
  group('lockEligibilityBlockers (pure)', () {
    test('the newest version at or before locked_at decides', () {
      final versions = [
        member('pa', matrixId: alice, updatedAt: 1),
        member('p1', updatedAt: 1),
        member('p1', matrixId: bob, updatedAt: 50),
      ];
      expect(
        lockEligibilityBlockers(100, versions).map((m) => m.userId),
        isEmpty,
      );
      expect(
        lockEligibilityBlockers(40, versions).map((m) => m.userId),
        ['p1'],
        reason: 'the claim came after the lock',
      );
    });

    test('removed people and people unknown at the lock don\'t block', () {
      expect(
        lockEligibilityBlockers(100, [
          member('p1', updatedAt: 1),
          member('p1', status: 'removed', updatedAt: 90),
          member('p2', updatedAt: 200),
        ]),
        isEmpty,
      );
    });

    test('a pseudo / invalid Matrix ID doesn\'t count as an account', () {
      expect(
        lockEligibilityBlockers(100, [
          member('p1', matrixId: 'local:self'),
        ]).map((m) => m.userId),
        ['p1'],
      );
    });

    test(
      'isNewLock: signed, no link, a locked_at the stored meta lacks',
      () async {
        final device = HmacKeyRegistry().deviceCrypto(alice, 'A');
        final lock = await signGroupMeta(device, meta(lockedAt: 5));
        expect(isNewLock(meta(lockedAt: 5), null), isFalse, reason: 'unsigned');
        expect(isNewLock(lock, null), isTrue);
        expect(
          isNewLock(lock, meta(lockedAt: 5)),
          isFalse,
          reason: 'same lock',
        );
        expect(isNewLock(lock, meta(lockedAt: 4)), isTrue);
        final linked = await signGroupMeta(
          device,
          meta(link: GroupLink(epoch: 1, secret: secret1), lockedAt: 5),
        );
        expect(isNewLock(linked, null), isFalse, reason: 'a link is open');
      },
    );
  });

  group('gate', () {
    late AppDatabase db;
    late SigningDao signing;
    late MembersDao members;
    late GroupsDao groups;
    late LinkDao link;
    late HmacKeyRegistry keys;
    late HmacRecordCrypto aliceDevice;
    late HmacRecordCrypto bobDevice;
    late HmacRecordCrypto eveDevice;
    late RecordVerifier verifier;
    var now = 1000000;

    RecordGate gate({
      bool linkPath = false,
      bool checkClaims = false,
      bool restore = false,
    }) => RecordGate(
      verifier: verifier,
      signing: signing,
      groups: groups,
      members: members,
      expenses: ExpensesDao(db),
      linkPolicy: linkPath ? link.policyOf : null,
      matrixPolicy: linkPath ? null : link.policyOf,
      acceptUnsigned: restore,
      verifyClaimDevices: checkClaims,
      clock: () => now,
    );

    Future<List<String>> refusals() async => [
      for (final r in await db.select(db.rejectedVersions).get())
        '${r.kind}:${r.recordId}:${r.reason}',
    ];

    Future<GroupModel> lockBy(
      HmacRecordCrypto device, {
      required int at,
    }) async {
      final stored = (await groups.getGroup('g1'))!;
      return signGroupMeta(
        device,
        stored.nextVersion(updatedAt: at, link: null, lockedAt: at),
      );
    }

    setUp(() async {
      db = openTestDatabase();
      signing = SigningDao(db);
      members = MembersDao(db);
      groups = GroupsDao(db);
      link = LinkDao(db);
      keys = HmacKeyRegistry();
      aliceDevice = keys.deviceCrypto(alice, 'AAAA');
      bobDevice = keys.deviceCrypto(bob, 'BBBB');
      eveDevice = keys.deviceCrypto(eve, 'EEEE');
      now = 1000000;
      verifier = RecordVerifier(
        crypto: aliceDevice,
        directory: keys,
        signing: signing,
        clock: () => now,
        refreshInterval: Duration.zero,
      );
      // A mixed group: Alice (claimed, pa) + Ben (p1, no account).
      await groups.upsertGroupLww(
        groupCompanion(
          await signGroupMeta(
            aliceDevice,
            meta(link: GroupLink(epoch: 1, secret: secret1)),
          ),
        ),
      );
      await members.upsertMemberLww(
        memberCompanion(
          await signMember(aliceDevice, member('pa', matrixId: alice)),
        ),
      );
      await members.upsertMemberLww(memberCompanion(member('p1')));
      expect((await link.policyOf('g1')).policy, GroupPolicy.mixed);
    });
    tearDown(() => db.close());

    test('a lock while Ben (no account) is active is refused on both paths '
        '— recorded, the re-offer is dropped silently', () async {
      for (final g in [gate(), gate(linkPath: true)]) {
        final lock = await lockBy(aliceDevice, at: 500);
        expect(await g.meta(groupMetaPayload(lock), relayedBy: alice), isFalse);
        expect((await groups.getGroup('g1'))!.link, isNotNull);
      }
      expect(await refusals(), ['meta:g1:lock_not_eligible']);
    });

    test('Ben removed before the lock → accepted', () async {
      await members.upsertMemberLww(
        memberCompanion(
          await signMember(
            aliceDevice,
            member('p1', status: 'removed', updatedAt: 400),
          ),
        ),
      );
      final lock = await lockBy(aliceDevice, at: 500);
      expect(await gate().meta(groupMetaPayload(lock), relayedBy: alice), true);
      expect((await groups.getGroup('g1'))!.isLocked, isTrue);
    });

    test('a claim stamped after locked_at doesn\'t count — the version '
        'history shows Ben unclaimed at the lock', () async {
      await members.upsertMemberLww(
        memberCompanion(
          await signMember(
            bobDevice,
            member('p1', matrixId: bob, updatedAt: 600),
          ),
        ),
      );
      final lock = await lockBy(aliceDevice, at: 500);
      expect(
        await gate().meta(groupMetaPayload(lock), relayedBy: alice),
        isFalse,
      );
      expect(await refusals(), ['meta:g1:lock_not_eligible']);
    });

    test('a late claim forgets the refusal; the re-sent lock is then '
        'accepted', () async {
      final lock = await lockBy(aliceDevice, at: 500);
      final g = gate();
      expect(await g.meta(groupMetaPayload(lock), relayedBy: alice), isFalse);
      // Bob's claim (stamped before the lock) arrives late, relayed by him.
      final claim = await signMember(
        bobDevice,
        member('p1', matrixId: bob, updatedAt: 300),
      );
      expect(await g.member(memberPayload(claim), relayedBy: bob), isTrue);
      expect(await refusals(), isEmpty);
      expect(await g.meta(groupMetaPayload(lock), relayedBy: alice), isTrue);
      expect((await groups.getGroup('g1'))!.isLocked, isTrue);
    });

    test('a snapshot carrying the claim and the lock: the participants go '
        'in first, the lock is valid', () async {
      final claim = await signMember(
        bobDevice,
        member('p1', matrixId: bob, updatedAt: 300),
      );
      final lock = await lockBy(aliceDevice, at: 500);
      final pa = (await members.getMembers(
        'g1',
      )).firstWhere((m) => m.userId == 'pa');
      await gate().snapshot(
        {
          'group': 'g1',
          'meta': groupMetaPayload(lock),
          'members': [memberPayload(pa), memberPayload(claim)],
        },
        relayedBy: alice,
        trustAttestations: false,
      );
      expect((await groups.getGroup('g1'))!.isLocked, isTrue);
      expect(await refusals(), isEmpty);
    });

    test('a group new to this device: judged by the snapshot\'s '
        'participants', () async {
      final lock = await signGroupMeta(
        aliceDevice,
        meta(group: 'g2', updatedAt: 500, lockedAt: 500),
      );
      final pa = await signMember(
        aliceDevice,
        member('pa', matrixId: alice, group: 'g2'),
      );
      await gate().snapshot(
        {
          'group': 'g2',
          'meta': groupMetaPayload(lock),
          'members': [
            memberPayload(pa),
            memberPayload(member('p1', group: 'g2')),
          ],
        },
        relayedBy: alice,
        trustAttestations: true,
      );
      expect(await groups.getGroup('g2'), isNull, reason: 'Ben blocks it');

      final lock2 = await signGroupMeta(
        aliceDevice,
        meta(group: 'g2', updatedAt: 501, lockedAt: 501),
      );
      await gate().snapshot(
        {
          'group': 'g2',
          'meta': groupMetaPayload(lock2),
          'members': [memberPayload(pa)],
        },
        relayedBy: alice,
        trustAttestations: true,
      );
      expect((await groups.getGroup('g2'))!.isLocked, isTrue);
    });

    test('a later version of a stored lock isn\'t judged again', () async {
      // Stored by an older build despite Ben.
      final lock = await lockBy(aliceDevice, at: 500);
      await groups.upsertGroupLww(groupCompanion(lock));
      final rename = await signGroupMeta(
        aliceDevice,
        lock.nextVersion(updatedAt: 700, name: 'Renamed'),
      );
      expect(rename.lockedAt, 500);
      expect(
        await gate().meta(groupMetaPayload(rename), relayedBy: alice),
        isTrue,
      );
    });

    test('restore: a lock in the user\'s own file is stored', () async {
      final lock = await lockBy(aliceDevice, at: 500);
      expect(
        await gate(
          restore: true,
        ).meta(groupMetaPayload(lock), relayedBy: alice),
        isTrue,
      );
    });

    group('claims over the link path (Matrix device)', () {
      Future<bool> selfClaim(
        RecordGate g,
        HmacRecordCrypto device,
        String mxid,
      ) async => g.member(
        memberPayload(
          await signMember(
            device,
            member('p1', matrixId: mxid, updatedAt: 300),
          ),
        ),
        relayedBy: via,
      );

      test('a self-claim by a listed device is accepted', () async {
        expect(
          await selfClaim(
            gate(linkPath: true, checkClaims: true),
            bobDevice,
            bob,
          ),
          isTrue,
        );
        expect(await members.activeClaimedMatrixIds('g1'), contains(bob));
      });

      test('a fabricated device of a real account: refused, recorded, '
          'never a replication target', () async {
        final fake = keys.unlistedCrypto(bob, 'FAKE');
        final g = gate(linkPath: true, checkClaims: true);
        expect(await selfClaim(g, fake, bob), isFalse);
        expect(await refusals(), ['member:p1:claim_device_not_listed']);
        expect(await members.activeClaimedMatrixIds('g1'), [alice]);
        expect(g.unverifiableClaims, 0);
      });

      test(
        'an account the homeserver knows nothing of / an unreachable '
        'homeserver: dropped transiently, accepted once it answers',
        () async {
          final g = gate(linkPath: true, checkClaims: true);
          expect(
            await selfClaim(g, keys.unlistedCrypto(ghost, 'G'), ghost),
            isFalse,
          );
          expect(g.unverifiableClaims, 1);
          keys.unreachable = true;
          expect(await selfClaim(g, bobDevice, bob), isFalse);
          expect(g.unverifiableClaims, 2);
          expect(await refusals(), isEmpty, reason: 'transient');
          keys.unreachable = false;
          expect(await selfClaim(g, bobDevice, bob), isTrue);
        },
      );

      test('a device pinned first-hand earlier still counts after it signed '
          'out', () async {
        await verifier.prefetch({bob});
        keys.removeDevice(bob, 'BBBB');
        expect(
          await selfClaim(
            gate(linkPath: true, checkClaims: true),
            bobDevice,
            bob,
          ),
          isTrue,
        );
      });

      test('without an account (no device list) and on the Matrix path the '
          'claim isn\'t checked', () async {
        final fake = keys.unlistedCrypto(bob, 'FAKE');
        expect(await selfClaim(gate(linkPath: true), fake, bob), isTrue);
      });

      test('a forged claim in a snapshot doesn\'t make its signer a member '
          'for the meta', () async {
        final fakeEve = keys.unlistedCrypto(eve, 'FAKE');
        final forged = await signMember(
          fakeEve,
          member('p1', matrixId: eve, updatedAt: 300),
        );
        final stored = (await groups.getGroup('g1'))!;
        final rename = await signGroupMeta(
          eveDevice,
          stored.nextVersion(updatedAt: 400, name: 'Mine now'),
        );
        await gate(linkPath: true, checkClaims: true).snapshot(
          {
            'group': 'g1',
            'meta': groupMetaPayload(rename),
            'members': [memberPayload(forged)],
          },
          relayedBy: via,
          trustAttestations: false,
        );
        expect((await groups.getGroup('g1'))!.name, 'Trip');
        expect(await members.activeClaimedMatrixIds('g1'), [alice]);
      });
    });
  });
}
