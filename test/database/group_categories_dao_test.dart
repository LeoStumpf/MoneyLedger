/// G47: custom categories in the stored group meta — the DAO round trip and
/// LWW (incl. the G27 tie-break over the categories), and the RecordGate:
/// a signed meta with valid categories is stored, one breaking the content
/// rules is refused as `invalid_record`.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/matrix/hmac_record_crypto.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_gate.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_verifier.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/expense_category.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const dog = CustomCategory(id: 'c:dog', name: 'Dog', icon: 'pets');
const kids = CustomCategory(id: 'c:kids', name: 'Kids', icon: 'child');

GroupModel meta(int at, List<CustomCategory> categories) => GroupModel(
  roomId: 'g1',
  name: 'Trip',
  currency: 'EUR',
  updatedAt: at,
  categories: categories,
);

void main() {
  late AppDatabase db;
  late GroupsDao groups;

  setUp(() {
    db = openTestDatabase();
    groups = GroupsDao(db);
  });
  tearDown(() => db.close());

  test('round trip: stored, read back, none → NULL', () async {
    await groups.upsertGroupLww(groupCompanion(meta(1, [dog, kids])));
    expect((await groups.getGroup('g1'))!.categories, [dog, kids]);
    expect((await groups.watchAllGroups().first).single.categories, [
      dog,
      kids,
    ]);
    expect(groupCompanion(meta(1, const [])).categoriesJson.value, isNull);
    expect(decodeCategories('not json'), isEmpty);
  });

  test('LWW: newer clock wins, older is ignored, categories kept', () async {
    await groups.upsertGroupLww(groupCompanion(meta(2, [dog])));
    await groups.upsertGroupLww(groupCompanion(meta(1, [dog, kids])));
    expect((await groups.getGroup('g1'))!.categories, [dog]);
    await groups.upsertGroupLww(groupCompanion(meta(3, [dog, kids])));
    expect((await groups.getGroup('g1'))!.categories, [dog, kids]);
    // A later rename via a companion that carries the categories keeps them.
    await groups.upsertGroupLww(
      groupCompanion(meta(4, [dog, kids])).copyWith(name: const Value('Ski')),
    );
    final g = (await groups.getGroup('g1'))!;
    expect(g.name, 'Ski');
    expect(g.categories, [dog, kids]);
  });

  test('equal clock: the higher content hash wins in any order', () async {
    final a = meta(5, [dog]);
    final b = meta(5, [dog.copyWith(hidden: true)]);
    final winner =
        groupMetaVersionHash(a).compareTo(groupMetaVersionHash(b)) > 0 ? a : b;
    for (final order in [
      [a, b],
      [b, a],
    ]) {
      await db.wipeAll();
      for (final g in order) {
        await groups.upsertGroupLww(groupCompanion(g));
      }
      expect((await groups.getGroup('g1'))!.categories, winner.categories);
    }
  });

  group('RecordGate', () {
    late HmacKeyRegistry keys;
    late RecordGate gate;
    late SigningDao signing;

    setUp(() async {
      await MembersDao(db).upsertMemberLww(
        memberCompanion(
          const MemberModel(
            groupId: 'g1',
            userId: 'p1',
            matrixId: alice,
            status: 'active',
            updatedAt: 1,
          ),
        ),
      );
      keys = HmacKeyRegistry();
      signing = SigningDao(db);
      gate = RecordGate(
        verifier: RecordVerifier(
          crypto: keys.deviceCrypto(alice, 'AAAA'),
          directory: keys,
          signing: signing,
          refreshInterval: Duration.zero,
        ),
        signing: signing,
        groups: groups,
        members: MembersDao(db),
        expenses: ExpensesDao(db),
      );
    });

    test('a signed meta with categories is stored', () async {
      final signed = await signGroupMeta(
        keys.deviceCrypto(alice, 'AAAA'),
        meta(10, [dog, kids]),
      );
      expect(
        await gate.meta(groupMetaPayload(signed), relayedBy: alice),
        isTrue,
      );
      expect((await groups.getGroup('g1'))!.categories, [dog, kids]);
    });

    test('invalid categories are refused as invalid_record', () async {
      final signed = await signGroupMeta(
        keys.deviceCrypto(alice, 'AAAA'),
        meta(10, [const CustomCategory(id: 'c:x', name: 'X', icon: 'rocket')]),
      );
      expect(
        await gate.meta(groupMetaPayload(signed), relayedBy: alice),
        isFalse,
      );
      expect(await groups.getGroup('g1'), isNull);
      expect(await signing.rejectedClock('g1', 'meta', 'g1'), 10);
    });
  });
}
