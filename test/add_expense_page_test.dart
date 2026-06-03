import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/test_providers.dart';

void main() {
  group('AddExpensePage', () {
    Future<(FakeMatrixNetwork, String)> seedRoom() async {
      final net = FakeMatrixNetwork();
      final alice = net.clientFor('@alice:x.org');
      final roomId = await alice.createGroup('Trip', 'CHF');
      net.invite(roomId, '@alice:x.org', '@bob:x.org');
      net.join(roomId, '@bob:x.org');
      return (net, roomId);
    }

    testWidgets('renders the form with the group currency and member count',
        (tester) async {
      final (net, roomId) = await seedRoom();

      await tester.pumpWidget(testApp(
        AddExpensePage(roomId: roomId),
        overrides: [
          ledgerTransportProvider
              .overrideWith((ref) => net.clientFor('@alice:x.org')),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Description'), findsOneWidget);
      expect(find.textContaining('Split equally among 2 member'),
          findsOneWidget);
      expect(find.text('CHF'), findsWidgets); // amount suffix
    });

    testWidgets('submitting sends the expense and pops back', (tester) async {
      final (net, roomId) = await seedRoom();
      final alice = net.clientFor('@alice:x.org');

      await tester.pumpWidget(testRouterApp(
        AddExpensePage(roomId: roomId),
        overrides: [ledgerTransportProvider.overrideWith((ref) => alice)],
      ));
      await tester.pumpAndSettle(); // navigate + load members

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Description'), 'Pizza');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount'), '20');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      final events = await alice.timelineEvents(roomId);
      expect(events, hasLength(1));
      expect(events.first.content['description'], 'Pizza');
      expect(events.first.content['amount'], 2000);
      // Split equally across the two members.
      expect(events.first.content['split'],
          {'@alice:x.org': 1000, '@bob:x.org': 1000});
      // Navigated back to the host route.
      expect(find.text('host'), findsOneWidget);
    });
  });
}
