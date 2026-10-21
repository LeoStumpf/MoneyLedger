/// G6 UI: "Added by X · Last edited by Y", the unverified / unsigned hints,
/// the list flag for conflicts / impersonation (EN + DE), and the footer on
/// the edit-expense page.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/record_attribution.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

RecordSignature sig(String user, {String device = 'D1', String key = 'K'}) =>
    RecordSignature(user: user, device: device, key: key, sig: 'S$user');

KnownKey server(String user, {String device = 'D1', String key = 'K'}) =>
    KnownKey(user: user, device: device, key: key, source: keySourceServer);

const members = [
  MemberModel(
    groupId: 'g',
    userId: 'p-a',
    displayName: 'Alex',
    matrixId: alice,
    status: 'active',
    updatedAt: 1,
  ),
  MemberModel(
    groupId: 'g',
    userId: 'p-b',
    displayName: 'Sam',
    matrixId: bob,
    status: 'active',
    updatedAt: 1,
  ),
];

void main() {
  Attribution of({
    RecordSignature? origin,
    RecordSignature? s,
    int updatedAt = 2,
    List<KnownKey> keys = const [],
    String me = '@me:z',
    AppLocalizations? l,
    RecordKind kind = RecordKind.expense,
    String? linkAuthor,
  }) => attributionFor(
    origin: origin,
    sig: s,
    createdAt: 1,
    updatedAt: updatedAt,
    myMxid: me,
    members: members,
    keys: keys,
    l: l ?? en,
    kind: kind,
    linkAuthor: linkAuthor,
  );

  test('added + edited by, verified → no hint (EN + DE)', () {
    final keys = [server(alice), server(bob)];
    final a = of(origin: sig(alice), s: sig(bob), keys: keys);
    expect(a.line, 'Added by Alex · Last edited by Sam');
    expect(a.hint, isNull);
    final d = of(origin: sig(alice), s: sig(bob), keys: keys, l: de);
    expect(d.line, 'Hinzugefügt von Alex · Zuletzt bearbeitet von Sam');
  });

  test('an unedited record only says who added it; "you" for ourselves', () {
    final a = of(
      origin: sig(alice),
      s: sig(alice),
      updatedAt: 1,
      keys: [server(alice)],
      me: alice,
    );
    expect(a.line, 'Added by you');
    expect(
      of(
        origin: sig(alice),
        s: sig(alice),
        updatedAt: 1,
        keys: [server(alice)],
        me: alice,
        l: de,
      ).line,
      'Hinzugefügt von dir',
    );
  });

  test('payments say "Recorded by"', () {
    expect(
      of(
        origin: sig(alice),
        s: sig(alice),
        updatedAt: 1,
        keys: [server(alice)],
        kind: RecordKind.settlement,
      ).line,
      'Recorded by Alex',
    );
  });

  test('G53: an unsigned link version says "via link, not verified" — '
      'with the writer when known', () {
    expect(of(linkAuthor: 'p-b').line, en.recordViaLinkBy('Sam'));
    expect(of(linkAuthor: 'p-b', l: de).line, de.recordViaLinkBy('Sam'));
    expect(of(linkAuthor: 'p-gone').line, en.recordViaLink);
    expect(en.recordViaLinkBy('Sam'), contains('not verified'));
  });

  test('legacy (unsigned) rows say so', () {
    expect(of().line, en.recordUnsigned);
    expect(of(l: de).line, de.recordUnsigned);
  });

  test('unknown key → subtle unverified hint, no list flag', () {
    final a = of(origin: sig(alice), s: sig(bob), keys: [server(alice)]);
    expect(a.hint, en.recordSigUnverified);
    expect(a.problem, isFalse);
    expect(
      recordNeedsAttention(
        origin: sig(alice),
        sig: sig(bob),
        myMxid: '@me:z',
        keys: [server(alice)],
      ),
      isFalse,
    );
  });

  test('key conflict → warning + list flag', () {
    final keys = [server(alice), server(bob, key: 'OTHER')];
    final a = of(origin: sig(alice), s: sig(bob), keys: keys);
    expect(a.problem, isTrue);
    expect(a.hint, "Signature doesn't match Sam's device");
    expect(
      recordNeedsAttention(
        origin: sig(alice),
        sig: sig(bob),
        myMxid: '@me:z',
        keys: keys,
      ),
      isTrue,
    );
  });

  test('someone posing as us from an unknown device → flagged', () {
    final a = of(
      origin: sig(alice),
      s: sig('@me:z', device: 'GHOST'),
      keys: [server(alice)],
    );
    expect(a.hint, en.recordNotYourDevice);
    expect(a.problem, isTrue);
    expect(
      recordNeedsAttention(
        origin: sig(alice),
        sig: sig('@me:z', device: 'GHOST'),
        myMxid: '@me:z',
        keys: [server(alice)],
      ),
      isTrue,
    );
  });

  Future<void> pumpEditPage(WidgetTester tester, {required bool pin}) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final net = FakeMatrixNetwork();
    await GroupsDao(db).upsertGroupLww(
      const GroupsCompanion(
        roomId: Value('g'),
        name: Value('Trip'),
        currency: Value('EUR'),
        updatedAt: Value(1),
      ),
    );
    for (final m in members) {
      await MembersDao(db).upsertMemberLww(memberCompanion(m));
    }
    final aliceDev = net.clientFor(alice).crypto;
    final bobDev = net.clientFor(bob).crypto;
    if (pin) {
      await SigningDao(db).pinServerKeys({
        alice: {'D1': aliceDev.identity!.key},
        bob: {'D1': bobDev.identity!.key},
      });
    }
    final created = await signExpense(
      aliceDev,
      const ExpenseModel(
        id: 'e1',
        roomId: 'g',
        description: 'Dinner',
        amountCents: 4000,
        currency: 'EUR',
        paidBy: 'p-a',
        splitsJson: '{"p-a":2000,"p-b":2000}',
        createdAt: 1000,
        updatedAt: 1000,
      ),
      creating: true,
    );
    final edited = await signExpense(
      bobDev,
      ExpenseModel(
        id: 'e1',
        roomId: 'g',
        description: 'Dinner',
        amountCents: 4000,
        currency: 'EUR',
        paidBy: 'p-a',
        splitsJson: '{"p-a":2000,"p-b":2000}',
        createdAt: 1000,
        updatedAt: 2000,
        origin: created.origin,
      ),
    );

    await tester.pumpWidget(
      testApp(
        AddExpensePage(roomId: 'g', initial: edited),
        overrides: [
          appDatabaseProvider.overrideWith((ref) => db),
          ledgerTransportProvider.overrideWith(
            (ref) => net.clientFor('@carol:c.org'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('recordAttribution')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    // Unmount and let drift's stream-close timers run.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('edit page footer shows "Added by … · Last edited by …"', (
    tester,
  ) async {
    await pumpEditPage(tester, pin: true);
    expect(find.text('Added by Alex ·'), findsOneWidget);
    expect(find.text('Last edited by Sam'), findsOneWidget);
    expect(find.text(en.recordSigUnverified), findsNothing);

    await tester.tap(find.byKey(const Key('recordSignatureInfo')));
    await tester.pumpAndSettle();
    expect(find.text(en.recordSigVerified), findsNWidgets(2));
    await unmount(tester);
  });

  testWidgets('G46: an unverifiable (not conflicting) signature is no '
      'footer noise — only the details dialog says so', (tester) async {
    await pumpEditPage(tester, pin: false);
    expect(find.text('Added by Alex ·'), findsOneWidget);
    expect(find.text(en.recordSigUnverified), findsNothing);

    await tester.tap(find.byKey(const Key('recordSignatureInfo')));
    await tester.pumpAndSettle();
    expect(find.text(en.recordSigUnverified), findsNWidgets(2));
    await unmount(tester);
  });
}
