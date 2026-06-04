import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/groups/group_members_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/test_providers.dart';

void main() {
  group('GroupMembersPage', () {
    // Widget-level rendering test with overridden providers (no real DB/relay —
    // the remove + replication flow is covered by the integration test and the
    // MembersDao LWW test).
    List<Object> overridesFor(List<MemberModel> members, String selfId) => [
          currentUserIdProvider.overrideWithValue(selfId),
          groupMembersProvider('g1').overrideWith((ref) => Stream.value(members)),
        ];

    MemberModel member(String id, {String status = 'active'}) => MemberModel(
        groupId: 'g1', userId: id, status: status, updatedAt: 1);

    testWidgets('lists active members; self gets a "You" chip, others removable',
        (tester) async {
      await tester.pumpWidget(testApp(
        const GroupMembersPage(roomId: 'g1'),
        overrides: overridesFor(
          [member('@alice:x.org'), member('@bob:x.org')],
          '@alice:x.org',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('@alice:x.org'), findsWidgets);
      expect(find.text('@bob:x.org'), findsWidgets);
      // Alice is the signed-in user → "You"; only bob can be removed.
      expect(find.widgetWithText(Chip, 'You'), findsOneWidget);
      expect(find.byTooltip('Remove'), findsOneWidget);
    });

    testWidgets('removed members are hidden from the list', (tester) async {
      await tester.pumpWidget(testApp(
        const GroupMembersPage(roomId: 'g1'),
        overrides: overridesFor(
          [member('@alice:x.org'), member('@bob:x.org', status: 'removed')],
          '@alice:x.org',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('@alice:x.org'), findsWidgets);
      expect(find.text('@bob:x.org'), findsNothing);
    });
  });
}
