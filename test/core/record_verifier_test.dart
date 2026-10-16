/// G6 — RecordVerifier / RecordGate against a real (in-memory) Drift DB and
/// the fake device keys: what is accepted, refused (and recorded) or flagged,
/// and the display status derived from the device-key history.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/matrix/hmac_record_crypto.dart';
import 'package:money_ledger/core/matrix/record_crypto.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_gate.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_verifier.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const mallory = '@mallory:x.org';

void main() {
  late AppDatabase db;
  late SigningDao signing;
  late ExpensesDao expenses;
  late HmacKeyRegistry keys;
  late HmacRecordCrypto aliceDevice;
  late RecordGate gate;
  var now = 1000000;

  setUp(() async {
    db = openTestDatabase();
    // G18 review: signers must be participants of the record's group.
    for (final (pid, mxid) in [('p1', alice), ('pb', '@bob:y.org')]) {
      await MembersDao(db).upsertMemberLww(
        memberCompanion(
          MemberModel(
            groupId: 'g1',
            userId: pid,
            matrixId: mxid,
            status: 'active',
            updatedAt: 1,
          ),
        ),
      );
    }
    signing = SigningDao(db);
    expenses = ExpensesDao(db);
    keys = HmacKeyRegistry();
    aliceDevice = keys.deviceCrypto(alice, 'AAAA');
    now = 1000000;
    gate = RecordGate(
      verifier: RecordVerifier(
        // Any device's crypto verifies any fake key (shared registry).
        crypto: aliceDevice,
        directory: keys,
        signing: signing,
        clock: () => now,
        refreshInterval: Duration.zero,
      ),
      signing: signing,
      groups: GroupsDao(db),
      members: MembersDao(db),
      expenses: expenses,
      clock: () => now,
    );
  });
  tearDown(() => db.close());

  ExpenseModel draft({int updatedAt = 1000, String description = 'Dinner'}) =>
      ExpenseModel(
        id: 'e1',
        roomId: 'g1',
        description: description,
        amountCents: 4200,
        currency: 'EUR',
        paidBy: 'p1',
        splitsJson: '{"p1":4200}',
        createdAt: 1000,
        updatedAt: updatedAt,
      );

  Future<int?> rejected() => signing.rejectedClock('g1', 'expense', 'e1');

  test(
    'a version signed by a listed device is stored + its key pinned',
    () async {
      final e = await signExpense(aliceDevice, draft(), creating: true);
      expect(await gate.expense(expensePayload(e), relayedBy: alice), isTrue);
      final stored = await expenses.getExpenseById('e1');
      expect(stored!.sig, e.sig);
      expect(stored.origin, e.origin);
      final pins = await signing.keysFor(alice, 'AAAA');
      expect(pins.single.isServer, isTrue);
      expect(signatureStatus(stored.sig, pins).status, SigStatus.verified);
    },
  );

  test('an unsigned inbound version is refused and recorded', () async {
    expect(
      await gate.expense(expensePayload(draft()), relayedBy: mallory),
      isFalse,
    );
    expect(await expenses.getExpenseById('e1'), isNull);
    expect(await rejected(), 1000);
  });

  test(
    'an unsigned relay of a row we hold at the same clock is a no-op',
    () async {
      await expenses.upsertExpenseLww(expenseCompanion(draft())); // legacy row
      expect(
        await gate.expense(expensePayload(draft()), relayedBy: alice),
        isFalse,
      );
      expect(await rejected(), isNull, reason: 'not newer → not even checked');
    },
  );

  test('forging a version as an existing device of another member is '
      'refused (key conflict)', () async {
    final legit = await signExpense(aliceDevice, draft(), creating: true);
    await gate.expense(expensePayload(legit), relayedBy: alice);
    // Mallory signs a newer version claiming alice/AAAA with her own key.
    final impostor = keys.unlistedCrypto(alice, 'AAAA');
    final forged = await signExpense(
      impostor,
      draft(
        updatedAt: 2000,
        description: 'Forged',
      ).withSigning(origin: legit.origin),
    );
    expect(
      await gate.expense(expensePayload(forged), relayedBy: mallory),
      isFalse,
    );
    final stored = await expenses.getExpenseById('e1');
    expect(stored!.description, 'Dinner');
    expect(await rejected(), 2000);
    // Re-sending the refused version is dropped without re-verifying.
    expect(
      await gate.expense(expensePayload(forged), relayedBy: mallory),
      isFalse,
    );
  });

  test('a tampered field (bad signature) is refused', () async {
    final e = await signExpense(aliceDevice, draft(), creating: true);
    final payload = expensePayload(e)..['amount'] = 1;
    expect(await gate.expense(payload, relayedBy: mallory), isFalse);
    expect(await rejected(), 1000);
  });

  test('a changed origin is refused; a legit edit by another member keeps '
      'the origin and is accepted', () async {
    final created = await signExpense(aliceDevice, draft(), creating: true);
    await gate.expense(expensePayload(created), relayedBy: alice);
    final bobDevice = keys.deviceCrypto('@bob:y.org', 'BBBB');

    // Bob re-signs with his own fresh origin ("I added it") → refused.
    final hijack = await signExpense(
      bobDevice,
      draft(updatedAt: 2000),
      creating: true,
    );
    expect(
      await gate.expense(expensePayload(hijack), relayedBy: '@bob:y.org'),
      isFalse,
    );
    final reason = await (db.select(
      db.rejectedVersions,
    )).getSingle().then((r) => r.reason);
    expect(reason, RejectReason.originChanged.wire);

    // A proper edit keeps alice's origin → accepted, "edited by bob".
    final edit = await signExpense(
      bobDevice,
      draft(
        updatedAt: 3000,
        description: 'Dinner (fixed)',
      ).withSigning(origin: created.origin),
    );
    expect(
      await gate.expense(expensePayload(edit), relayedBy: '@bob:y.org'),
      isTrue,
    );
    final stored = await expenses.getExpenseById('e1');
    expect(stored!.origin!.user, alice);
    expect(stored.sig!.user, '@bob:y.org');
  });

  test('a fabricated / signed-out device is accepted but unverified', () async {
    final ghost = keys.unlistedCrypto(alice, 'GHOST');
    final e = await signExpense(ghost, draft(), creating: true);
    expect(await gate.expense(expensePayload(e), relayedBy: mallory), isTrue);
    final stored = await expenses.getExpenseById('e1');
    final pins = await signing.keysFor(alice, 'GHOST');
    expect(signatureStatus(stored!.sig, pins).status, SigStatus.unverified);
  });

  test('a device pinned before it signed out stays verified', () async {
    final first = await signExpense(aliceDevice, draft(), creating: true);
    await gate.expense(expensePayload(first), relayedBy: alice); // pins AAAA
    final edit = await signExpense(
      aliceDevice,
      draft(updatedAt: 2000).withSigning(origin: first.origin),
    );
    keys.removeDevice(alice, 'AAAA'); // logout: gone from the server list
    expect(
      await gate.expense(expensePayload(edit), relayedBy: '@bob:y.org'),
      isTrue,
    );
    final stored = await expenses.getExpenseById('e1');
    final pins = await signing.keysFor(alice, 'AAAA');
    expect(signatureStatus(stored!.sig, pins).status, SigStatus.verified);

    // …while a forger claiming that signed-out device with another key is
    // refused: we pinned its real key first-hand.
    final impostor = keys.unlistedCrypto(alice, 'AAAA');
    final forged = await signExpense(
      impostor,
      draft(updatedAt: 3000).withSigning(origin: first.origin),
    );
    expect(
      await gate.expense(expensePayload(forged), relayedBy: mallory),
      isFalse,
    );
    expect(
      (await db.select(db.rejectedVersions).getSingle()).reason,
      RejectReason.keyConflict.wire,
    );
  });

  test('a clock too far in the future is dropped, not recorded', () async {
    final e = await signExpense(
      aliceDevice,
      draft(updatedAt: now + const Duration(minutes: 6).inMilliseconds),
      creating: true,
    );
    expect(await gate.expense(expensePayload(e), relayedBy: alice), isFalse);
    expect(await rejected(), isNull);
    now += const Duration(minutes: 2).inMilliseconds;
    expect(await gate.expense(expensePayload(e), relayedBy: alice), isTrue);
  });

  test('a self-claim must be signed by the claimant', () async {
    final mal = keys.deviceCrypto(mallory, 'MMMM');
    final claim = await signMember(
      mal,
      const MemberModel(
        groupId: 'g1',
        userId: 'p-victim',
        matrixId: alice,
        status: 'active',
        updatedAt: 5,
      ),
    );
    expect(
      await gate.member(
        memberPayload(claim),
        relayedBy: alice,
        requiredSigner: alice,
      ),
      isFalse,
    );
  });

  test('backup restore mode stores unsigned rows as legacy, still refuses '
      'bad signatures', () async {
    final restoreGate = RecordGate(
      verifier: gate.verifier,
      signing: signing,
      groups: GroupsDao(db),
      members: MembersDao(db),
      expenses: expenses,
      acceptUnsigned: true,
    );
    expect(
      await restoreGate.expense(expensePayload(draft()), relayedBy: alice),
      isTrue,
    );
    final e = await signExpense(
      aliceDevice,
      draft(updatedAt: 2000),
      creating: true,
    );
    final tampered = expensePayload(e)..['description'] = 'x';
    expect(await restoreGate.expense(tampered, relayedBy: alice), isFalse);
  });

  group('signatureStatus', () {
    const sig = RecordSignature(user: alice, device: 'D', key: 'K', sig: 'S');
    KnownKey k(String key, String source, {String? by, String? group}) =>
        KnownKey(
          user: alice,
          device: 'D',
          key: key,
          source: source,
          attestedBy: by,
          group: group ?? (source == keySourceAttested ? 'g1' : null),
        );

    test('legacy / verified / vouched / unverified / conflict', () {
      expect(signatureStatus(null, const []).status, SigStatus.legacy);
      expect(
        signatureStatus(sig, [k('K', keySourceServer)]).status,
        SigStatus.verified,
      );
      final v = signatureStatus(sig, [
        k('K', keySourceAttested, by: '@b:x'),
      ], group: 'g1');
      expect(v.status, SigStatus.vouched);
      expect(v.vouchedBy, '@b:x');
      expect(signatureStatus(sig, const []).status, SigStatus.unverified);
      expect(
        signatureStatus(sig, [k('OTHER', keySourceAttested)]).status,
        SigStatus.unverified,
      );
      expect(
        signatureStatus(sig, [k('OTHER', keySourceServer)]).status,
        SigStatus.conflict,
      );
    });

    // G18 review: an attestation vouches only within the group whose
    // snapshot carried it, and never against a server device list.
    test('attestations are scoped to their group', () {
      final attested = [k('K', keySourceAttested, by: '@b:x', group: 'g1')];
      expect(
        signatureStatus(sig, attested, group: 'g2').status,
        SigStatus.unverified,
      );
      expect(signatureStatus(sig, attested).status, SigStatus.unverified);
      expect(
        signatureStatus(sig, attested, group: 'g1').status,
        SigStatus.vouched,
      );
    });

    test('a server device list of the account beats a peer attestation, '
        "but not the account's own", () {
      final serverOther = KnownKey(
        user: alice,
        device: 'OTHERDEV',
        key: 'K2',
        source: keySourceServer,
      );
      expect(
        signatureStatus(sig, [
          k('K', keySourceAttested, by: '@b:x'),
          serverOther,
        ], group: 'g1').status,
        SigStatus.unverified,
      );
      expect(
        signatureStatus(sig, [
          k('K', keySourceAttested, by: alice),
          serverOther,
        ], group: 'g1').status,
        SigStatus.vouched,
      );
    });
  });

  group('G35 prefetch + refusal hook', () {
    test('prefetch looks every signer up once; the verifications that follow '
        'need no further homeserver call', () async {
      final dir = _CountingDirectory(keys);
      final verifier = RecordVerifier(
        crypto: aliceDevice,
        directory: dir,
        signing: signing,
        clock: () => now,
        refreshInterval: const Duration(minutes: 10),
      );
      final g = RecordGate(
        verifier: verifier,
        signing: signing,
        groups: GroupsDao(db),
        members: MembersDao(db),
        expenses: expenses,
      );
      await verifier.prefetch({alice, mallory});
      expect(dir.calls, 1);
      expect(dir.requested.single, {alice, mallory});
      // Pinned first-hand by the prefetch.
      expect((await signing.keysFor(alice, 'AAAA')).single.isServer, isTrue);
      final e = await signExpense(aliceDevice, draft(), creating: true);
      expect(await g.expense(expensePayload(e), relayedBy: alice), isTrue);
      expect(dir.calls, 1);
    });

    test(
      'an unreachable server during prefetch counts as "no answer"',
      () async {
        final dir = _CountingDirectory(keys)..fail = true;
        final verifier = RecordVerifier(
          crypto: aliceDevice,
          directory: dir,
          signing: signing,
          clock: () => now,
          refreshInterval: const Duration(minutes: 10),
        );
        await verifier.prefetch({alice});
        final e = await signExpense(aliceDevice, draft(), creating: true);
        expect(await verifier.expense(e), same(Verdict.accept));
        expect(dir.calls, 1); // no retry mid-batch
      },
    );

    test('onRefused reports unsigned (legacy) versions', () async {
      final refused = <(String, RecordKind, RejectReason, String)>[];
      final g = RecordGate(
        verifier: RecordVerifier(
          crypto: aliceDevice,
          directory: keys,
          signing: signing,
          clock: () => now,
        ),
        signing: signing,
        groups: GroupsDao(db),
        members: MembersDao(db),
        expenses: expenses,
        onRefused: (gid, kind, reason, via) =>
            refused.add((gid, kind, reason, via)),
      );
      expect(
        await g.expense(expensePayload(draft()), relayedBy: alice),
        isFalse,
      );
      expect(refused, [
        ('g1', RecordKind.expense, RejectReason.unsigned, alice),
      ]);
    });
  });

  group('G18 review', () {
    RecordGate restoreGate() => RecordGate(
      verifier: gate.verifier,
      signing: signing,
      groups: GroupsDao(db),
      members: MembersDao(db),
      expenses: expenses,
      acceptUnsigned: true,
      clock: () => now,
    );

    // Finding 3.
    test('an unsigned far-future version is dropped, never recorded', () async {
      final p = expensePayload(draft(updatedAt: 9000000000000000));
      expect(await gate.expense(p, relayedBy: mallory), isFalse);
      expect(await rejected(), isNull);
      // …so a normal later version is still accepted.
      final e = await signExpense(aliceDevice, draft(), creating: true);
      expect(await gate.expense(expensePayload(e), relayedBy: alice), isTrue);
    });

    test('a refusal blocks exactly the refused version', () async {
      final created = await signExpense(aliceDevice, draft(), creating: true);
      await gate.expense(expensePayload(created), relayedBy: alice);
      // An unsigned version at 3000 is refused (recorded) …
      final unsigned = expensePayload(draft(updatedAt: 3000, description: 'x'))
        ..['origin'] = created.origin!.toJson();
      expect(await gate.expense(unsigned, relayedBy: mallory), isFalse);
      expect(await rejected(), 3000);
      // … but a valid version at 2000 (lower) and another version at the
      // same clock 3000 (other content) are still looked at and accepted.
      for (final (at, desc) in [(2000, 'lower'), (3000, 'same clock')]) {
        final v = await signExpense(
          aliceDevice,
          draft(
            updatedAt: at,
            description: desc,
          ).withSigning(origin: created.origin),
        );
        expect(
          await gate.expense(expensePayload(v), relayedBy: alice),
          isTrue,
          reason: desc,
        );
      }
      // The refused version itself stays dropped (no re-verification).
      expect(await gate.expense(unsigned, relayedBy: mallory), isFalse);
    });

    // Finding 5.
    test('invalid content is refused and recorded as invalid_record', () async {
      for (final (i, (amount, split)) in [
        (0, '{}'),
        (100, '{"p1":99}'),
        (100, '{"p1":"100"}'),
        (100, '[100]'),
        (100, '{"p1":150,"p2":-50}'),
        (100000000000000, '{"p1":100000000000000}'),
      ].indexed) {
        final e = await signExpense(
          aliceDevice,
          ExpenseModel(
            id: 'bad$i',
            roomId: 'g1',
            description: 'bad',
            amountCents: amount,
            currency: 'EUR',
            paidBy: 'p1',
            splitsJson: split,
            createdAt: 1000,
            updatedAt: 1000,
          ),
          creating: true,
        );
        expect(
          await gate.expense(expensePayload(e), relayedBy: alice),
          isFalse,
          reason: split,
        );
      }
      final rows = await db.select(db.rejectedVersions).get();
      expect(rows, hasLength(6));
      expect(rows.map((r) => r.reason).toSet(), {RejectReason.invalid.wire});
      expect(await expenses.getAllExpensesForGroup('g1'), isEmpty);
    });

    test('a payment to oneself / of 0 is refused', () async {
      for (final (i, (amount, to)) in [(100, 'p1'), (0, 'pb')].indexed) {
        final s = await signSettlement(
          aliceDevice,
          SettlementModel(
            id: 's$i',
            roomId: 'g1',
            amountCents: amount,
            currency: 'EUR',
            fromUser: 'p1',
            toUser: to,
            createdAt: 1000,
            updatedAt: 1000,
          ),
          creating: true,
        );
        expect(
          await gate.settlement(settlementPayload(s), relayedBy: alice),
          isFalse,
        );
      }
    });

    // Finding 1 (defence in depth).
    test("a version signed by a non-participant is dropped unless it's the "
        "relay's own (not recorded)", () async {
      final mal = keys.deviceCrypto(mallory, 'MMMM');
      final e = await signExpense(mal, draft(), creating: true);
      expect(await gate.expense(expensePayload(e), relayedBy: alice), isFalse);
      expect(await rejected(), isNull, reason: 'transient');
      // A participant relaying her own version — always fine.
      final ok = await signExpense(aliceDevice, draft(), creating: true);
      expect(await gate.expense(expensePayload(ok), relayedBy: alice), isTrue);
    });

    test('a removed signer: versions up to the removal count, later ones '
        'are dropped', () async {
      await MembersDao(db).upsertMemberLww(
        memberCompanion(
          const MemberModel(
            groupId: 'g1',
            userId: 'pb',
            matrixId: '@bob:y.org',
            status: 'removed',
            updatedAt: 1500,
          ),
        ),
      );
      final bobDevice = keys.deviceCrypto('@bob:y.org', 'BBBB');
      final before = await signExpense(bobDevice, draft(), creating: true);
      expect(
        await gate.expense(expensePayload(before), relayedBy: alice),
        isTrue,
      );
      final after = await signExpense(
        bobDevice,
        draft(updatedAt: 2000).withSigning(origin: before.origin),
      );
      expect(
        await gate.expense(expensePayload(after), relayedBy: alice),
        isFalse,
      );
    });

    test('snapshotEntries keeps only entries of the snapshot group', () {
      final s = snapshotEntries({
        'group': 'g1',
        'meta': {'group': 'g1', 'name': 'T'},
        'members': [
          {'group': 'g1', 'participant_id': 'a'},
          {'group': 'g2', 'participant_id': 'b'},
          'junk',
        ],
        'expenses': [
          {'group': 'g2', 'id': 'e'},
        ],
        'settlements': [
          {'id': 's'},
        ],
      })!;
      expect(s.members.map((m) => m['participant_id']), ['a']);
      expect(s.expenses, isEmpty);
      expect(s.settlements, isEmpty);
      expect(s.droppedForeign, 4);
      expect(
        snapshotEntries({
          'group': 'g1',
          'meta': {'group': 'g2'},
        }),
        isNull,
        reason: 'a meta of another group',
      );
    });

    // Finding 10.
    test('a restore bypasses + clears an earlier sync refusal of the same '
        'version', () async {
      final legacy = expensePayload(draft());
      expect(await gate.expense(legacy, relayedBy: mallory), isFalse);
      expect(await rejected(), 1000);
      expect(await restoreGate().expense(legacy, relayedBy: alice), isTrue);
      expect(await rejected(), isNull);
      expect((await expenses.getExpenseById('e1'))!.sig, isNull);
    });
  });
}

class _CountingDirectory implements DeviceKeyDirectory {
  _CountingDirectory(this.inner);
  final DeviceKeyDirectory inner;
  int calls = 0;
  bool fail = false;
  final requested = <Set<String>>[];

  @override
  Future<Map<String, Map<String, String>>> currentDevices(
    Set<String> users,
  ) async {
    calls++;
    requested.add(users);
    if (fail) throw StateError('offline');
    return inner.currentDevices(users);
  }
}
