import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/groups/group_members_page.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/test_providers.dart';

void main() {
  group('GroupMembersPage', () {
    Future<(FakeMatrixNetwork, String)> seedRoom() async {
      final net = FakeMatrixNetwork();
      final alice = net.clientFor('@alice:x.org');
      final roomId = await alice.createGroup('Trip', 'EUR');
      net.invite(roomId, '@alice:x.org', '@bob:x.org');
      net.join(roomId, '@bob:x.org');
      return (net, roomId);
    }

    testWidgets('lists members; self gets a "You" chip, others are removable',
        (tester) async {
      final (net, roomId) = await seedRoom();

      await tester.pumpWidget(testApp(
        GroupMembersPage(roomId: roomId),
        overrides: [
          ledgerTransportProvider
              .overrideWith((ref) => net.clientFor('@alice:x.org')),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('@alice:x.org'), findsWidgets);
      expect(find.text('@bob:x.org'), findsWidgets);
      // Alice is the signed-in user → "You"; only bob can be removed.
      expect(find.widgetWithText(Chip, 'You'), findsOneWidget);
      expect(find.byTooltip('Remove'), findsOneWidget);
    });

    testWidgets('removing a member kicks them from the list', (tester) async {
      final (net, roomId) = await seedRoom();

      await tester.pumpWidget(testApp(
        GroupMembersPage(roomId: roomId),
        overrides: [
          ledgerTransportProvider
              .overrideWith((ref) => net.clientFor('@alice:x.org')),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle(); // confirm dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle(); // kick + reload

      expect(find.text('@bob:x.org'), findsNothing);
    });
  });
}
