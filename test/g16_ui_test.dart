/// G16 widget tests: category icons + note marker in the ledger, the search
/// bar and filter chips, the archive menu / banner and the groups page's
/// "Archived" section, and the balance page's simplify-debts explanation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/welcome/why_matrix_hint.dart'
    show linkGroupIdsProvider;
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_page.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/core/sync/self_recovery.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_archive.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/test_providers.dart';

const _roomId = 'g1';
const _me = '@alice:x.org';

ExpenseModel _e(
  String id,
  String description, {
  String? category,
  String? note,
  String paidBy = _me,
  int createdAt = 5000,
}) => ExpenseModel(
  id: id,
  roomId: _roomId,
  description: description,
  amountCents: 2000,
  currency: 'EUR',
  paidBy: paidBy,
  splitsJson: '{"$_me":1000,"@bob:x.org":1000}',
  createdAt: createdAt,
  category: category,
  note: note,
);

final _expenses = [
  _e('1', 'Pizza', category: 'food', note: 'Margherita x2'),
  _e('2', 'Taxi', category: 'transport', paidBy: '@bob:x.org'),
  _e('3', 'Misc'),
];

const _members = [
  MemberModel(
    groupId: _roomId,
    userId: _me,
    displayName: 'Alice',
    matrixId: _me,
    status: 'active',
    updatedAt: 1,
  ),
  MemberModel(
    groupId: _roomId,
    userId: '@bob:x.org',
    displayName: 'Bob',
    matrixId: '@bob:x.org',
    status: 'active',
    updatedAt: 1,
  ),
];

List<dynamic> _pageOverrides({Map<String, GroupArchive> archives = const {}}) =>
    [
      ...testOverrides(
        isLoggedIn: true,
        expenses: _expenses,
        members: _members,
        archives: archives,
      ),
      currentUserIdProvider.overrideWith((_) => _me),
      currentParticipantProvider.overrideWith((_, _) async => _members.first),
      groupLedgerFingerprintProvider.overrideWith((_, _) => 'fp'),
    ];

Future<void> _pumpPage(WidgetTester tester, List overrides) async {
  await tester.pumpWidget(
    testApp(const ExpensesPage(roomId: _roomId), overrides: overrides),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('ledger list (G16)', () {
    testWidgets('category icons replace the receipt; a note is marked', (
      tester,
    ) async {
      await _pumpPage(tester, _pageOverrides());
      expect(find.byKey(const Key('categoryTile-food')), findsOneWidget);
      expect(find.byKey(const Key('categoryTile-transport')), findsOneWidget);
      expect(find.byKey(const Key('categoryTile-none')), findsOneWidget);
      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
      expect(find.byKey(const Key('expenseNoteIcon')), findsOneWidget);
    });

    testWidgets('search filters by description, note and payer', (
      tester,
    ) async {
      await _pumpPage(tester, _pageOverrides());
      await tester.tap(find.byKey(const Key('openSearch')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200)); // FAB exit
      }
      expect(find.byKey(const Key('searchField')), findsOneWidget);
      // The summary card and FAB make room while searching.
      expect(find.byKey(const Key('groupSummaryCard')), findsNothing);
      expect(find.byType(FloatingActionButton).hitTestable(), findsNothing);

      await tester.enterText(find.byKey(const Key('searchField')), 'piz');
      await tester.pump();
      expect(find.text('Pizza'), findsOneWidget);
      expect(find.text('Taxi'), findsNothing);
      expect(find.text('1 entry'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('searchField')), 'margh');
      await tester.pump();
      expect(find.text('Pizza'), findsOneWidget); // via the note

      await tester.enterText(find.byKey(const Key('searchField')), 'bob');
      await tester.pump();
      expect(find.text('Taxi'), findsOneWidget); // payer
      expect(find.text('Pizza'), findsNothing);

      await tester.enterText(find.byKey(const Key('searchField')), 'zzz');
      await tester.pump();
      expect(find.byKey(const Key('noMatches')), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pump();
      expect(find.text('3 entries'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('searchField')))
            .controller!
            .text,
        isEmpty,
      );

      // Closing restores the normal view.
      await tester.tap(find.byKey(const Key('closeSearch')));
      await tester.pump();
      expect(find.byKey(const Key('groupSummaryCard')), findsOneWidget);
      expect(find.text('Misc'), findsOneWidget);
    });

    testWidgets('filter chips: used categories and "involving me"', (
      tester,
    ) async {
      await _pumpPage(tester, _pageOverrides());
      await tester.tap(find.byKey(const Key('openSearch')));
      await tester.pump();
      // Only the categories the group uses.
      expect(find.byKey(const Key('filterCategory-food')), findsOneWidget);
      expect(find.byKey(const Key('filterCategory-transport')), findsOneWidget);
      expect(find.byKey(const Key('filterCategory-home')), findsNothing);

      await tester.tap(find.byKey(const Key('filterCategory-transport')));
      await tester.pump();
      expect(find.text('Taxi'), findsOneWidget);
      expect(find.text('Pizza'), findsNothing);
      expect(find.text('Misc'), findsNothing);

      await tester.tap(find.byKey(const Key('filterCategory-food')));
      await tester.pump();
      expect(find.text('2 entries'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filterInvolvingMe')));
      await tester.pump();
      expect(find.text('2 entries'), findsOneWidget); // alice is in both
    });

    testWidgets('German: search hint and chip labels', (tester) async {
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _roomId),
          overrides: _pageOverrides(),
          locale: const Locale('de'),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('openSearch')));
      await tester.pump();
      expect(find.text('Essen & Trinken'), findsOneWidget);
      expect(find.text('Verkehr'), findsOneWidget);
      expect(find.text('Betrifft mich'), findsOneWidget);
      expect(find.text('Beschreibung, Notiz, Zahler suchen'), findsOneWidget);
    });
  });

  group('archive (G16)', () {
    testWidgets('the ⋮ menu offers Archive; an archived group shows a banner', (
      tester,
    ) async {
      await _pumpPage(tester, _pageOverrides());
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Archive group'), findsOneWidget);
      expect(find.byKey(const Key('archivedBanner')), findsNothing);
    });

    testWidgets('archived: banner + Unarchive in the menu', (tester) async {
      await _pumpPage(
        tester,
        _pageOverrides(
          archives: {
            _roomId: const GroupArchive(archivedAt: 1, fingerprint: 'fp'),
          },
        ),
      );
      expect(find.byKey(const Key('archivedBanner')), findsOneWidget);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Unarchive group'), findsWidgets);
    });

    testWidgets('new activity (fingerprint changed) → not archived any more', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _pageOverrides(
          archives: {
            _roomId: const GroupArchive(archivedAt: 1, fingerprint: 'older'),
          },
        ),
      );
      expect(find.byKey(const Key('archivedBanner')), findsNothing);
    });

    testWidgets('groups page: archived groups sit in a collapsed section', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          overrides: [
            isLoggedInProvider.overrideWith((ref) => true),
            // G54: no link groups (no drift stream in widget tests).
            linkGroupIdsProvider.overrideWith((_) => Stream.value(const {})),
            ...signingUiOverrides(
              archives: {
                'g2': const GroupArchive(archivedAt: 1, fingerprint: 'fp'),
                // Stale entry: g3 had activity since → shown as active.
                'g3': const GroupArchive(archivedAt: 1, fingerprint: 'old'),
              },
            ),
            ledgerGroupsProvider.overrideWith(
              (_) => Stream.value(const [
                GroupModel(roomId: 'g1', name: 'Trip', currency: 'EUR'),
                GroupModel(roomId: 'g2', name: 'Board games', currency: 'EUR'),
                GroupModel(roomId: 'g3', name: 'Flat', currency: 'EUR'),
              ]),
            ),
            groupMembersProvider.overrideWith(
              (ref, g) => Stream.value(const []),
            ),
            expensesForRoomProvider.overrideWith((ref, g) => Stream.value([])),
            settlementsForRoomProvider.overrideWith(
              (ref, g) => Stream.value([]),
            ),
            groupLedgerFingerprintProvider.overrideWith((_, _) => 'fp'),
            selfRecoveryProvider.overrideWith(_NotRestoring.new),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Trip'), findsOneWidget);
      expect(find.text('Flat'), findsOneWidget);
      expect(find.text('Board games'), findsNothing);
      expect(find.text('Archived (1)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('archivedSection')));
      await tester.pump();
      expect(find.text('Board games'), findsOneWidget);
      expect(find.textContaining('comes back by itself'), findsOneWidget);
    });
  });

  group('balance page: simplify-debts explanation (G16)', () {
    testWidgets('info dialog; per-currency note with several currencies', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const BalancePage(roomId: _roomId),
          overrides: testOverrides(
            isLoggedIn: true,
            debts: const [
              DebtEntry(from: 'b', to: 'a', cents: 100, currency: 'CHF'),
              DebtEntry(from: 'b', to: 'a', cents: 200, currency: 'EUR'),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('perCurrencyNote')), findsOneWidget);
      expect(find.byKey(const Key('simplifyInfo-CHF')), findsOneWidget);
      expect(find.byKey(const Key('simplifyInfo-EUR')), findsOneWidget);

      await tester.tap(find.byKey(const Key('simplifyInfo-CHF')));
      await tester.pumpAndSettle();
      expect(find.text('Simplified debts'), findsOneWidget);
      expect(find.textContaining('fewest payments'), findsOneWidget);
      expect(find.textContaining('never converted'), findsWidgets);
    });

    testWidgets('one currency: no per-currency note', (tester) async {
      await tester.pumpWidget(
        testApp(
          const BalancePage(roomId: _roomId),
          overrides: testOverrides(
            isLoggedIn: true,
            debts: const [
              DebtEntry(from: 'b', to: 'a', cents: 100, currency: 'EUR'),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('perCurrencyNote')), findsNothing);
      expect(find.byTooltip('How are payments suggested?'), findsOneWidget);
    });
  });
}

class _NotRestoring extends SelfRecovery {
  @override
  bool build() => false;
}
