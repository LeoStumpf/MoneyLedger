import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';

import '../helpers/in_memory_database.dart';

Future<void> _seedLegacy(
  AppDatabase db, {
  String owner = '@alice:x.org',
  String group = 'g1',
}) async {
  await db
      .into(db.groups)
      .insert(
        GroupsCompanion.insert(
          roomId: group,
          name: 'Trip',
          updatedAt: const Value(10),
        ),
      );
  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          groupId: group,
          userId: owner,
          displayName: const Value('Alice'),
          matrixId: Value(owner),
          updatedAt: 1,
        ),
      );
  await db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          id: 'e1',
          roomId: group,
          description: 'Dinner',
          amountCents: 4200,
          currency: 'EUR',
          paidBy: owner,
          splitsJson: '{"$owner":4200}',
          createdAt: 1,
          updatedAt: const Value(2),
        ),
      );
  await db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(key: 'onboarding_seen', value: 'true'),
      );
}

void main() {
  group('accountDatabaseName', () {
    test('is deterministic (golden value pins cross-run stability)', () {
      expect(
        accountDatabaseName('@alice:matrix.org'),
        accountDatabaseName('@alice:matrix.org'),
      );
      // Goldens: must never change, or existing users "lose" their ledger
      // (a new name opens a fresh, empty DB).
      expect(accountDatabaseName(''), 'money_ledger_811c9dc5${_h2Empty()}');
      expect(
        accountDatabaseName('@alice:matrix.org'),
        'money_ledger_ef44bbe09c7ba144',
      );
    });

    test('differs per MXID', () {
      final ids = [
        '@alice:matrix.org',
        '@bob:matrix.org',
        '@alice:example.org',
        '@Alice:matrix.org',
        '@alice:matrix.or',
      ];
      final names = ids.map(accountDatabaseName).toSet();
      expect(names.length, ids.length);
    });

    test('is filename-safe and never contains the raw MXID', () {
      for (final id in ['@alice:matrix.org', '@ü/..\\:x', '@a b:c']) {
        final name = accountDatabaseName(id);
        expect(name, matches(RegExp(r'^money_ledger_[0-9a-f]{16}$')));
        expect(name, isNot(contains('alice')));
        expect(name, isNot(legacyDatabaseName));
      }
    });
  });

  group('shouldAdoptLegacy', () {
    test('adopts when we are a claimed member', () {
      expect(
        shouldAdoptLegacy(
          mxid: '@a:x',
          legacyClaimedMatrixIds: {'@a:x', '@b:x'},
          adoptedInto: null,
        ),
        isTrue,
      );
    });
    test('adopts an ownerless (local/CSV-only) ledger', () {
      expect(
        shouldAdoptLegacy(
          mxid: '@a:x',
          legacyClaimedMatrixIds: {},
          adoptedInto: null,
        ),
        isTrue,
      );
    });
    test("refuses another account's ledger", () {
      expect(
        shouldAdoptLegacy(
          mxid: '@b:x',
          legacyClaimedMatrixIds: {'@a:x'},
          adoptedInto: null,
        ),
        isFalse,
      );
    });
    test('never adopts twice', () {
      expect(
        shouldAdoptLegacy(
          mxid: '@a:x',
          legacyClaimedMatrixIds: {'@a:x'},
          adoptedInto: 'money_ledger_x',
        ),
        isFalse,
      );
    });
  });

  _cleanupTests();

  group('adoptLegacyLedger', () {
    // The legacy DB is a temp file so it survives adoptLegacyLedger closing
    // its handle (like the real on-disk money_ledger_db).
    late Directory tmp;
    late File legacyFile;
    late AppDatabase legacy; // inspection handle, opened lazily per check
    AppDatabase openLegacyFile() =>
        AppDatabase.forTesting(NativeDatabase(legacyFile));
    Future<AppDatabase?> openLegacy() async => openLegacyFile();

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('legacy_db_');
      legacyFile = File('${tmp.path}/money_ledger_db.sqlite');
      final seed = openLegacyFile();
      await _seedLegacy(seed);
      await seed.close();
      legacy = openLegacyFile();
    });
    tearDown(() async {
      await legacy.close();
      await tmp.delete(recursive: true);
    });

    test('copies all rows into the owner\'s DB exactly once', () async {
      final target = openTestDatabase();
      addTearDown(target.close);

      expect(
        await adoptLegacyLedger(
          target: target,
          targetName: 'money_ledger_a',
          mxid: '@alice:x.org',
          openLegacy: openLegacy,
        ),
        isTrue,
      );
      expect((await target.select(target.groups).get()).single.name, 'Trip');
      expect((await target.select(target.expenses).get()).single.id, 'e1');
      expect(await target.select(target.members).get(), hasLength(1));
      final settings = {
        for (final s in await target.select(target.appSettings).get())
          s.key: s.value,
      };
      expect(settings['onboarding_seen'], 'true');
      expect(settings[legacyCheckedKey], 'true');
      expect(settings.containsKey(legacyAdoptedIntoKey), isFalse);
      final legacyMark = await (legacy.select(
        legacy.appSettings,
      )..where((t) => t.key.equals(legacyAdoptedIntoKey))).getSingle();
      expect(legacyMark.value, 'money_ledger_a');

      // A second open of the same account: already checked → no-op.
      expect(
        await adoptLegacyLedger(
          target: target,
          targetName: 'money_ledger_a',
          mxid: '@alice:x.org',
          openLegacy: () async => fail('must not reopen legacy'),
        ),
        isFalse,
      );

      // Another account (even an otherwise eligible one) never re-adopts.
      final other = openTestDatabase();
      addTearDown(other.close);
      expect(
        await adoptLegacyLedger(
          target: other,
          targetName: 'money_ledger_b',
          mxid: '@alice:x.org',
          openLegacy: openLegacy,
        ),
        isFalse,
      );
      expect(await other.select(other.groups).get(), isEmpty);
    });

    test("a different account doesn't adopt someone else's ledger", () async {
      final target = openTestDatabase();
      addTearDown(target.close);
      expect(
        await adoptLegacyLedger(
          target: target,
          targetName: 'money_ledger_b',
          mxid: '@bob:x.org',
          openLegacy: openLegacy,
        ),
        isFalse,
      );
      expect(await target.select(target.groups).get(), isEmpty);
      // ...and it stays available for the real owner afterwards.
      final owner = openTestDatabase();
      addTearDown(owner.close);
      expect(
        await adoptLegacyLedger(
          target: owner,
          targetName: 'money_ledger_a',
          mxid: '@alice:x.org',
          openLegacy: openLegacy,
        ),
        isTrue,
      );
    });

    test('no legacy DB → marks checked, adopts nothing', () async {
      final target = openTestDatabase();
      addTearDown(target.close);
      expect(
        await adoptLegacyLedger(
          target: target,
          targetName: 'money_ledger_a',
          mxid: '@alice:x.org',
          openLegacy: () async => null,
        ),
        isFalse,
      );
      final checked = await (target.select(
        target.appSettings,
      )..where((t) => t.key.equals(legacyCheckedKey))).getSingleOrNull();
      expect(checked?.value, 'true');
    });

    test('never clobbers rows already in the target', () async {
      final target = openTestDatabase();
      addTearDown(target.close);
      await target
          .into(target.groups)
          .insert(
            GroupsCompanion.insert(
              roomId: 'g1',
              name: 'Newer',
              updatedAt: const Value(99),
            ),
          );
      await adoptLegacyLedger(
        target: target,
        targetName: 'money_ledger_a',
        mxid: '@alice:x.org',
        openLegacy: openLegacy,
      );
      expect((await target.select(target.groups).get()).single.name, 'Newer');
    });

    test('runs from the beforeOpen hook of a fresh per-account DB', () async {
      final target = openTestDatabaseWithHook(
        (db) => adoptLegacyLedger(
          target: db,
          targetName: 'money_ledger_a',
          mxid: '@alice:x.org',
          openLegacy: openLegacy,
        ),
      );
      addTearDown(target.close);
      expect((await target.select(target.groups).get()).single.roomId, 'g1');
    });
  });
}

void _cleanupTests() {
  group('cleanupLegacyLedger (G36)', () {
    late Directory tmp;
    late File legacyFile;
    AppDatabase openLegacyFile() =>
        AppDatabase.forTesting(NativeDatabase(legacyFile));
    Future<AppDatabase?> openLegacy() async =>
        await legacyFile.exists() ? openLegacyFile() : null;
    Future<void> deleteLegacy() => legacyFile.delete();

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('legacy_cleanup_');
      legacyFile = File('${tmp.path}/money_ledger_db.sqlite');
    });
    tearDown(() => tmp.delete(recursive: true));

    Future<void> seed({List<String> claims = const ['@alice:x.org']}) async {
      final db = openLegacyFile();
      if (claims.isEmpty) {
        await db
            .into(db.groups)
            .insert(GroupsCompanion.insert(roomId: 'g0', name: 'Local'));
      }
      if (claims.isNotEmpty) {
        await _seedLegacy(db, owner: claims.first, group: 'g0');
      }
      for (final c in claims.skip(1)) {
        await db
            .into(db.members)
            .insert(
              MembersCompanion.insert(
                groupId: 'g0',
                userId: c,
                matrixId: Value(c),
                updatedAt: 1,
              ),
            );
      }
      await db.close();
    }

    /// One app start of [mxid]: the cleanup (if the check ran before),
    /// else the adoption — exactly like `openAccountDatabase`.
    Future<void> start(AppDatabase target, String mxid) async {
      if (await cleanupLegacyLedger(
        target: target,
        openLegacy: openLegacy,
        deleteLegacy: deleteLegacy,
      )) {
        return;
      }
      await adoptLegacyLedger(
        target: target,
        targetName: accountDatabaseName(mxid),
        mxid: mxid,
        openLegacy: openLegacy,
      );
    }

    Future<String?> setting(AppDatabase db, String key) async =>
        (await (db.select(
          db.appSettings,
        )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

    test('adopted by its only claimed account → deleted on the next start, '
        'data kept in the account DB', () async {
      await seed();
      final alice = openTestDatabase();
      addTearDown(alice.close);
      await start(alice, '@alice:x.org'); // adopts
      expect(
        await legacyFile.exists(),
        isTrue,
        reason: 'not on the same start',
      );
      await start(alice, '@alice:x.org'); // next start: cleanup
      expect(await legacyFile.exists(), isFalse);
      expect(await setting(alice, legacyCleanupKey), 'deleted');
      expect((await alice.select(alice.groups).get()).single.roomId, 'g0');
      // Further starts: settled, nothing to do.
      await start(alice, '@alice:x.org');
      expect(await alice.select(alice.groups).get(), hasLength(1));
    });

    test('a ledger without claimed accounts is deleted once adopted', () async {
      await seed(claims: const []);
      final a = openTestDatabase();
      addTearDown(a.close);
      await start(a, '@alice:x.org');
      await start(a, '@alice:x.org');
      expect(await legacyFile.exists(), isFalse);
    });

    test('another claimed account might still need it → kept', () async {
      await seed(claims: const ['@alice:x.org', '@bob:x.org']);
      final alice = openTestDatabase();
      addTearDown(alice.close);
      await start(alice, '@alice:x.org');
      await start(alice, '@alice:x.org');
      expect(await legacyFile.exists(), isTrue);
      expect(await setting(alice, legacyCleanupKey), 'kept');
    });

    test('not adopted (someone else\'s ledger) → kept and re-checked; '
        'deleted after the owner adopts it', () async {
      await seed();
      final bob = openTestDatabase();
      addTearDown(bob.close);
      await start(bob, '@bob:x.org'); // check: not ours
      await start(bob, '@bob:x.org'); // cleanup: not adopted yet → keep
      expect(await legacyFile.exists(), isTrue);
      expect(await setting(bob, legacyCleanupKey), isNull);

      final alice = openTestDatabase();
      addTearDown(alice.close);
      await start(alice, '@alice:x.org'); // adopts
      await start(bob, '@bob:x.org'); // Bob's next start may delete it now
      expect(await legacyFile.exists(), isFalse);
    });

    test('no legacy DB → settled as absent', () async {
      final a = openTestDatabase();
      addTearDown(a.close);
      await start(a, '@alice:x.org');
      await start(a, '@alice:x.org');
      expect(await setting(a, legacyCleanupKey), 'absent');
    });

    test('canDeleteLegacy (pure)', () {
      final a = accountDatabaseName('@alice:x.org');
      expect(
        canDeleteLegacy(adoptedInto: null, legacyClaimedMatrixIds: {}),
        isFalse,
      );
      expect(
        canDeleteLegacy(adoptedInto: a, legacyClaimedMatrixIds: {}),
        isTrue,
      );
      expect(
        canDeleteLegacy(
          adoptedInto: a,
          legacyClaimedMatrixIds: {'@alice:x.org'},
        ),
        isTrue,
      );
      expect(
        canDeleteLegacy(
          adoptedInto: a,
          legacyClaimedMatrixIds: {'@alice:x.org', '@bob:x.org'},
        ),
        isFalse,
      );
    });
  });
}

String _h2Empty() {
  // For the empty input the first pass is the FNV-1a offset basis itself; the
  // second pass is seeded with basis ^ 0x9e3779b9 and likewise unchanged.
  return (0x811c9dc5 ^ 0x9e3779b9).toRadixString(16).padLeft(8, '0');
}
