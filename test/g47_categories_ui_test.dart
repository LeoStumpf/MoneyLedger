/// G47 widget tests: custom categories in the ledger list (icon tile, filter
/// chips), the group menu's *Categories* entry and the categories page
/// (list, hidden state, add / rename / hide through [GroupEditor], read-only
/// for non-members).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/groups/group_categories_page.dart';
import 'package:money_ledger/features/groups/group_settings_page.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_category.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/test_providers.dart';

const _roomId = 'g1';
const _me = '@alice:x.org';

const _dog = CustomCategory(id: 'c:dog', name: 'Dog', icon: 'pets');
const _kids = CustomCategory(
  id: 'c:kids',
  name: 'Kids',
  icon: 'child',
  hidden: true,
);

const _group = GroupModel(
  roomId: _roomId,
  name: 'Trip',
  currency: 'EUR',
  categories: [_dog, _kids],
);

ExpenseModel _e(String id, String description, String? category) =>
    ExpenseModel(
      id: id,
      roomId: _roomId,
      description: description,
      amountCents: 2000,
      currency: 'EUR',
      paidBy: _me,
      splitsJson: '{"$_me":1000,"@bob:x.org":1000}',
      createdAt: 5000,
      category: category,
    );

const _alice = MemberModel(
  groupId: _roomId,
  userId: _me,
  displayName: 'Alice',
  matrixId: _me,
  status: 'active',
  updatedAt: 1,
);

/// Records the editor calls instead of writing (no DB, no transport).
class _RecordingEditor extends GroupEditor {
  final added = <(String, String)>[];
  final updated = <CustomCategory>[];

  @override
  Future<String?> addCategory(
    String groupId, {
    required String name,
    required String icon,
  }) async {
    added.add((name, icon));
    return 'c:new';
  }

  @override
  Future<void> updateCategory(String groupId, CustomCategory c) async =>
      updated.add(c);
}

List<dynamic> _overrides({
  MemberModel me = _alice,
  List<ExpenseModel> expenses = const [],
  _RecordingEditor? editor,
}) => [
  ...testOverrides(
    isLoggedIn: true,
    expenses: expenses,
    members: [me],
    groups: [_group],
  ),
  currentUserIdProvider.overrideWith((_) => _me),
  currentParticipantProvider.overrideWith((_, _) async => me),
  groupLedgerFingerprintProvider.overrideWith((_, _) => 'fp'),
  if (editor != null) groupEditorProvider.overrideWith(() => editor),
];

Future<void> _pump(WidgetTester tester, Widget page, List overrides) async {
  await tester.pumpWidget(testApp(page, overrides: overrides));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('ledger list', () {
    final expenses = [
      _e('1', 'Vet', 'c:dog'),
      _e('2', 'Toys', 'c:kids'), // hidden: still labelled
      _e('3', 'Lost', 'c:gone'), // undefined → Other
      _e('4', 'Pizza', 'food'),
    ];

    testWidgets('custom categories show their icon; filter chips by id', (
      tester,
    ) async {
      await _pump(
        tester,
        const ExpensesPage(roomId: _roomId),
        _overrides(expenses: expenses),
      );
      expect(find.byKey(const Key('categoryTile-c:dog')), findsOneWidget);
      expect(find.byIcon(Icons.pets_outlined), findsOneWidget);
      expect(find.byIcon(Icons.child_care_outlined), findsOneWidget);

      await tester.tap(find.byKey(const Key('openSearch')));
      await tester.pump();
      expect(find.byKey(const Key('filterCategory-c:dog')), findsOneWidget);
      expect(find.byKey(const Key('filterCategory-c:kids')), findsOneWidget);
      expect(find.byKey(const Key('filterCategory-other')), findsOneWidget);
      expect(find.byKey(const Key('filterCategory-food')), findsOneWidget);
      expect(find.text('Dog'), findsOneWidget); // chip label

      await tester.tap(find.byKey(const Key('filterCategory-c:dog')));
      await tester.pump();
      expect(find.text('Vet'), findsOneWidget);
      expect(find.text('Toys'), findsNothing);
      expect(find.text('Pizza'), findsNothing);

      // Search text + category filter combine.
      await tester.tap(find.byKey(const Key('filterCategory-c:kids')));
      await tester.enterText(find.byKey(const Key('searchField')), 'toy');
      await tester.pump();
      expect(find.text('Toys'), findsOneWidget);
      expect(find.text('Vet'), findsNothing);
    });

    // G65: Categories moved from the ⋮ menu to the group settings page.
    testWidgets('the group settings offer Categories', (tester) async {
      await _pump(
        tester,
        const GroupSettingsPage(roomId: _roomId),
        _overrides(expenses: expenses),
      );
      expect(find.byKey(const Key('categoriesTile')), findsOneWidget);
    });
  });

  group('categories page', () {
    testWidgets('lists them (hidden marked); hide / rename / add go through '
        'the group editor', (tester) async {
      final editor = _RecordingEditor();
      await _pump(
        tester,
        const GroupCategoriesPage(roomId: _roomId),
        _overrides(editor: editor),
      );
      expect(find.text('Dog'), findsOneWidget);
      expect(find.text('Kids'), findsOneWidget);
      expect(find.text('Hidden'), findsOneWidget);

      // Hide Dog.
      await tester.tap(find.byKey(const Key('toggleHidden-c:dog')));
      await tester.pump();
      expect(editor.updated.single, _dog.copyWith(hidden: true));

      // Show Kids again.
      await tester.tap(find.byKey(const Key('toggleHidden-c:kids')));
      await tester.pump();
      expect(editor.updated.last, _kids.copyWith(hidden: false));

      // Rename Dog + new icon.
      await tester.tap(find.text('Dog'));
      await tester.pumpAndSettle();
      expect(find.text('Edit category'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('categoryNameField')),
        'Dogs',
      );
      await tester.tap(find.byKey(const Key('categoryIcon-heart')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('categoryDialogSave')));
      await tester.pumpAndSettle();
      expect(editor.updated.last, _dog.copyWith(name: 'Dogs', icon: 'heart'));

      // Add.
      await tester.tap(find.byKey(const Key('addCategory')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('categoryNameField')), 'Gym');
      await tester.tap(find.byKey(const Key('categoryDialogSave')));
      await tester.pumpAndSettle();
      expect(editor.added.single, ('Gym', 'tag'));
    });

    testWidgets('read-only for someone who is no longer a member', (
      tester,
    ) async {
      final editor = _RecordingEditor();
      await _pump(
        tester,
        const GroupCategoriesPage(roomId: _roomId),
        _overrides(
          me: const MemberModel(
            groupId: _roomId,
            userId: _me,
            matrixId: _me,
            status: 'removed',
            updatedAt: 2,
          ),
          editor: editor,
        ),
      );
      expect(find.byKey(const Key('addCategory')), findsNothing);
      await tester.tap(find.byKey(const Key('toggleHidden-c:dog')));
      await tester.pump();
      expect(editor.updated, isEmpty);
    });

    testWidgets('German labels; empty state', (tester) async {
      await tester.pumpWidget(
        testApp(
          const GroupCategoriesPage(roomId: 'other'),
          overrides: _overrides(),
          locale: const Locale('de'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Kategorien'), findsOneWidget);
      expect(find.text('Noch keine eigenen Kategorien.'), findsOneWidget);
      expect(find.text('Neue Kategorie'), findsOneWidget); // FAB
    });
  });
}
