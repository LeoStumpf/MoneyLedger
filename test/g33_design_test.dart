/// G33 design follow-ups: settlement titles keep both names visible, the
/// expense row gives its title the space, the extended FAB never covers the
/// last row, the background-sync scheduling error and the "encryption off"
/// banner are shown.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/background/background_sync_provider.dart';
import 'package:money_ledger/core/l10n/formatting.dart';
import 'package:money_ledger/core/matrix/crypto_status.dart';
import 'package:money_ledger/core/theme/app_theme.dart';
import 'package:money_ledger/core/widgets/names_line.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/test_providers.dart';

const _g = 'g1';
const _me = '@me:x.org';
const _longA = 'moneyledger-test-a-c725-with-a-very-long-localpart';
const _longB = 'Bartholomew Maximilian Featherstonehaugh-Smythe';

final _t = DateTime(2026, 10, 14, 12).millisecondsSinceEpoch;

ExpenseModel _expense(String id, String description, {int at = 0}) =>
    ExpenseModel(
      id: id,
      roomId: _g,
      description: description,
      amountCents: 2450,
      currency: 'EUR',
      paidBy: 'p-a',
      splitsJson: '{"p-a":1225,"$_me":1225}',
      createdAt: _t + at,
      updatedAt: _t + at,
    );

/// A phone-sized surface (411 × 860 dp) with an optional bottom system
/// navigation inset (3-button navigation ≈ 48 dp).
void _phone(WidgetTester tester, {double navInset = 0}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(411, 860);
  tester.view.padding = FakeViewPadding(bottom: navInset);
  tester.view.viewPadding = FakeViewPadding(bottom: navInset);
  addTearDown(tester.view.reset);
}

List<dynamic> _pageOverrides({
  List<ExpenseModel> expenses = const [],
  List<SettlementModel> settlements = const [],
}) => [
  ...testOverrides(
    isLoggedIn: true,
    expenses: expenses,
    settlements: settlements,
  ),
  participantNamesProvider.overrideWith(
    (ref, g) => {'p-a': _longA, 'p-b': _longB, _me: 'Me'},
  ),
  currentUserIdProvider.overrideWith((ref) => _me),
  currentParticipantProvider.overrideWith(
    (ref, g) => Future<MemberModel?>.value(
      const MemberModel(
        groupId: _g,
        userId: _me,
        displayName: 'Me',
        matrixId: _me,
        status: 'active',
        updatedAt: 1,
      ),
    ),
  ),
];

void main() {
  group('NamesLine helpers (pure)', () {
    test('capNames fills in whole names, or caps each on its own', () {
      final a = NamesLine.sentinel(0), b = NamesLine.sentinel(1);
      final names = {a: 'Alexandra', b: 'Sam'};
      expect(
        capNames('$a hat $b bezahlt', names, null),
        'Alexandra hat Sam bezahlt',
      );
      expect(capNames('$a hat $b bezahlt', names, 4), 'Alex… hat Sam bezahlt');
      expect(capNames('$a pays $b', {a: 'Al ex', b: 'Sam'}, 3), 'Al… pays Sam');
    });
  });

  group('ledger rows', () {
    testWidgets('a settlement between two very long names keeps both '
        'visible, each ellipsized', (tester) async {
      // The test font's square glyphs are ~2× a real font's width: 800 test
      // px ≈ a phone's line.
      _phone(tester);
      tester.view.physicalSize = const Size(800, 860);
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _g),
          overrides: _pageOverrides(
            settlements: [
              SettlementModel(
                id: 's1',
                roomId: _g,
                amountCents: 1250,
                currency: 'EUR',
                fromUser: 'p-a',
                toUser: 'p-b',
                createdAt: _t,
                updatedAt: _t,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (w) => w is NamesLine && w.fullText == '$_longA paid $_longB',
        ),
        findsOneWidget,
      );
      // G18 review 2: the sentence wraps onto two lines instead of cutting
      // each name to a few letters; both names stay (mostly) readable, the
      // literal is intact, and the title ends before the amount.
      final title = find.byKey(const Key('settlementTitle'));
      final text = tester.widget<Text>(
        find.descendant(
          of: title,
          matching: find.byKey(const Key('namesLineText')),
        ),
      );
      expect(text.maxLines, 2);
      final shown = text.data!;
      expect(shown, contains(' paid '));
      expect(shown, startsWith(_longA.substring(0, 12)));
      expect(shown.split(' paid ').last, startsWith(_longB.substring(0, 12)));
      final rect = tester.getRect(title);
      final amount = tester.getRect(find.text('€12.50'));
      expect(rect.right, lessThanOrEqualTo(amount.left));
    });

    testWidgets('German: the expense title gets the line, the long '
        '"du schuldest …" note sits on the second one', (tester) async {
      _phone(tester);
      const title = 'Taxi to the airport and back again';
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _g),
          locale: const Locale('de'),
          overrides: _pageOverrides(expenses: [_expense('e1', title)]),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      final titleRect = tester.getRect(find.text(title));
      final amount = tester.getRect(find.text(formatMoney(2450, 'EUR', 'de')));
      final note = tester.getRect(
        find.text('du schuldest ${formatMoney(1225, 'EUR', 'de')}'),
      );
      // The title runs up to the amount — no longer capped by the note.
      expect(amount.left - titleRect.right, lessThan(Insets.s + 1));
      // (The old shared amount column was as wide as the note and left the
      // title almost nothing in the square-glyph test font.)
      expect(titleRect.width, greaterThan(100));
      // The note is on the second line, below the title.
      expect(note.top, greaterThanOrEqualTo(titleRect.bottom - 1));
    });

    testWidgets('the extended FAB never covers the last row, even with a '
        'navigation-bar inset', (tester) async {
      _phone(tester, navInset: 48);
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _g),
          overrides: _pageOverrides(
            expenses: [
              for (var i = 0; i < 12; i++)
                _expense('e$i', 'Expense $i', at: -i * 1000),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();

      final fab = tester.getRect(find.byType(FloatingActionButton));
      final lastAmount = find.byKey(const Key('ledgerRowAmount')).last;
      final rect = tester.getRect(lastAmount);
      expect(rect.bottom, lessThan(fab.top));
      // The whole last row (its card) ends above the FAB — with a fixed 96 dp
      // padding the 48 dp inset pushed it under the FAB.
      expect(tester.getRect(find.byType(Card).last).bottom, lessThan(fab.top));
      // Hit-testable: tapping it lands on the row, not the FAB.
      final hit = tester.hitTestOnBinding(rect.center);
      final fabBox = tester.renderObject(find.byType(FloatingActionButton));
      expect(hit.path.any((e) => identical(e.target, fabBox)), isFalse);
    });
  });

  group('groups page / settings', () {
    for (final (locale, text) in [
      (const Locale('en'), "Background sync couldn't be set up"),
      (const Locale('de'), 'konnte auf diesem Gerät nicht eingerichtet'),
    ]) {
      testWidgets('scheduling failure is shown under the toggle ($locale)', (
        tester,
      ) async {
        await tester.pumpWidget(
          testApp(
            const GroupsPage(),
            locale: locale,
            overrides: [
              ...testOverrides(isLoggedIn: true),
              backgroundSyncSupportedProvider.overrideWithValue(true),
              backgroundSyncEnabledProvider.overrideWith(
                (_) => Stream.value(true),
              ),
              backgroundSyncSchedulingErrorProvider.overrideWith(
                _FailedScheduling.new,
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('backgroundSyncError')), findsOneWidget);
        expect(find.textContaining(text), findsOneWidget);
        expect(find.textContaining('WorkManager said no'), findsOneWidget);
      });
    }

    testWidgets('no error line while scheduling works', (tester) async {
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          overrides: [
            ...testOverrides(isLoggedIn: true),
            backgroundSyncSupportedProvider.overrideWithValue(true),
            backgroundSyncEnabledProvider.overrideWith(
              (_) => Stream.value(true),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backgroundSyncError')), findsNothing);
    });

    for (final (locale, text) in [
      (const Locale('en'), "Encryption couldn't be started"),
      (const Locale('de'), 'Die Verschlüsselung konnte'),
    ]) {
      testWidgets('E2EE failed to start → persistent banner ($locale)', (
        tester,
      ) async {
        await tester.pumpWidget(
          testApp(
            const GroupsPage(),
            locale: locale,
            overrides: [
              ...testOverrides(isLoggedIn: true),
              cryptoAvailableProvider.overrideWithValue(false),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.byKey(const Key('encryptionUnavailableBanner')),
          findsOneWidget,
        );
        expect(find.textContaining(text), findsOneWidget);
      });
    }

    testWidgets('no banner when encryption is up', (tester) async {
      await tester.pumpWidget(
        testApp(const GroupsPage(), overrides: testOverrides(isLoggedIn: true)),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('encryptionUnavailableBanner')),
        findsNothing,
      );
    });
  });
}

class _FailedScheduling extends BackgroundSyncSchedulingError {
  @override
  Object? build() => Exception('WorkManager said no');
}
