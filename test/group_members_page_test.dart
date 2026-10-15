import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/groups/group_members_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/test_providers.dart';

void main() {
  group('GroupMembersPage', () {
    // Widget-level rendering test with overridden providers (no real DB/relay —
    // the add/claim/remove flows are covered by group_provider + integration
    // tests).
    List<Object> overridesFor(List<MemberModel> members, String selfId) => [
          currentUserIdProvider.overrideWithValue(selfId),
          groupMembersProvider('g1').overrideWith((ref) => Stream.value(members)),
        ];

    MemberModel claimed(String mxid, {String name = '', String status = 'active'}) =>
        MemberModel(
            groupId: 'g1',
            userId: mxid,
            displayName: name,
            matrixId: mxid,
            status: status,
            updatedAt: 1);

    MemberModel local(String id, String name) => MemberModel(
        groupId: 'g1', userId: id, displayName: name, status: 'active', updatedAt: 1);

    testWidgets('self gets a "You" chip; others get an options menu',
        (tester) async {
      await tester.pumpWidget(testApp(
        const GroupMembersPage(roomId: 'g1'),
        overrides: overridesFor(
          [claimed('@alice:x.org', name: 'Alice'), claimed('@bob:x.org', name: 'Bob')],
          '@alice:x.org',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      // Alice is signed in → "You"; only bob (not self) has an options menu.
      expect(find.widgetWithText(Chip, 'You'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('a local participant shows a "Local" subtitle', (tester) async {
      await tester.pumpWidget(testApp(
        const GroupMembersPage(roomId: 'g1'),
        overrides: overridesFor(
          [claimed('@alice:x.org', name: 'Alice'), local('p-uuid', 'Cash')],
          '@alice:x.org',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Local'), findsOneWidget);
      // The claimed member shows their MXID as the subtitle.
      expect(find.text('@alice:x.org'), findsOneWidget);
    });

    testWidgets('a local participant offers "Link Matrix account"',
        (tester) async {
      await tester.pumpWidget(testApp(
        const GroupMembersPage(roomId: 'g1'),
        overrides: overridesFor(
          [claimed('@alice:x.org', name: 'Alice'), local('p-uuid', 'Cash')],
          '@alice:x.org',
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Link Matrix account'), findsOneWidget);
      expect(find.text('Remove from group'), findsOneWidget);
    });

    testWidgets('removed members are listed greyed under "Former members" '
        'with a re-add action for claimed ones (G26)', (tester) async {
      await tester.pumpWidget(testApp(
        const GroupMembersPage(roomId: 'g1'),
        overrides: overridesFor(
          [
            claimed('@alice:x.org', name: 'Alice'),
            claimed('@bob:x.org', name: 'Bob', status: 'removed'),
            MemberModel(
                groupId: 'g1',
                userId: 'p-cash',
                displayName: 'Cash',
                status: 'removed',
                updatedAt: 1),
          ],
          '@alice:x.org',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Former members'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('@bob:x.org · former member'), findsOneWidget);
      expect(find.text('Local · former member'), findsOneWidget);
      // Bob appears after the section header, greyed.
      expect(
          tester.getTopLeft(find.text('Bob')).dy >
              tester.getTopLeft(find.text('Former members')).dy,
          isTrue);
      expect(
          find.ancestor(of: find.text('Bob'), matching: find.byType(Opacity)),
          findsOneWidget);
      // Only the claimed former member can be re-added; no options menus.
      expect(find.widgetWithText(TextButton, 'Re-add'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });

    testWidgets('once we were removed, the members list is read-only',
        (tester) async {
      await tester.pumpWidget(testApp(
        const GroupMembersPage(roomId: 'g1'),
        overrides: overridesFor(
          [
            claimed('@alice:x.org', name: 'Alice', status: 'removed'),
            claimed('@bob:x.org', name: 'Bob'),
            claimed('@carol:x.org', name: 'Carol', status: 'removed'),
          ],
          '@alice:x.org',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Add person'), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      final readd = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Re-add'));
      expect(readd.onPressed, isNull);
      // We are listed among the former members.
      expect(find.widgetWithText(Chip, 'You'), findsOneWidget);
    });
  });
}
