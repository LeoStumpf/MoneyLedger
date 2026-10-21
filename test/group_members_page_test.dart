import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/groups/group_members_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_device_gateway.dart';
import 'helpers/test_providers.dart';

void main() {
  group('GroupMembersPage', () {
    // Widget-level rendering test with overridden providers (no real DB/relay —
    // the add/claim/remove flows are covered by group_provider + integration
    // tests).
    List<Object> overridesFor(List<MemberModel> members, String selfId) => [
      currentUserIdProvider.overrideWithValue(selfId),
      groupMembersProvider('g1').overrideWith((ref) => Stream.value(members)),
      // G52 step 6: "me" + the link-invite state (no DB here).
      currentParticipantProvider(
        'g1',
      ).overrideWith((ref) async => claimedBy(members, selfId)),
      linkInviteStateProvider(
        'g1',
      ).overrideWith((ref) async => LinkInviteState.unavailable),
      ...FakeTrustStore().overrides(FakeDeviceGateway(const [])),
    ];

    MemberModel claimed(
      String mxid, {
      String name = '',
      String status = 'active',
    }) => MemberModel(
      groupId: 'g1',
      userId: mxid,
      displayName: name,
      matrixId: mxid,
      status: status,
      updatedAt: 1,
    );

    MemberModel local(String id, String name) => MemberModel(
      groupId: 'g1',
      userId: id,
      displayName: name,
      status: 'active',
      updatedAt: 1,
    );

    testWidgets('self gets a "You" chip; others get an options menu', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overridesFor([
            claimed('@alice:x.org', name: 'Alice'),
            claimed('@bob:x.org', name: 'Bob'),
          ], '@alice:x.org'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      // Alice is signed in → "You"; only bob (not self) has an options menu.
      expect(find.widgetWithText(Chip, 'You'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('a local participant shows a "Local" subtitle', (tester) async {
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overridesFor([
            claimed('@alice:x.org', name: 'Alice'),
            local('p-uuid', 'Cash'),
          ], '@alice:x.org'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Local'), findsOneWidget);
      // G56: the claimed member shows only the short `@localpart`.
      expect(find.text('@alice'), findsOneWidget);
      expect(find.text('@alice:x.org'), findsNothing);
    });

    testWidgets('a local participant offers "Link Matrix account"', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overridesFor([
            claimed('@alice:x.org', name: 'Alice'),
            local('p-uuid', 'Cash'),
          ], '@alice:x.org'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Link Matrix account'), findsOneWidget);
      expect(find.text('Remove from group'), findsOneWidget);
    });

    testWidgets('removed members are listed greyed under "Former members" '
        'with a re-add action (G26; local people too, G7)', (tester) async {
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overridesFor([
            claimed('@alice:x.org', name: 'Alice'),
            claimed('@bob:x.org', name: 'Bob', status: 'removed'),
            MemberModel(
              groupId: 'g1',
              userId: 'p-cash',
              displayName: 'Cash',
              status: 'removed',
              updatedAt: 1,
            ),
          ], '@alice:x.org'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('No longer in the group'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('@bob · no longer in the group'), findsOneWidget);
      expect(find.text('Local · no longer in the group'), findsOneWidget);
      // Bob appears after the section header, greyed.
      expect(
        tester.getTopLeft(find.text('Bob')).dy >
            tester.getTopLeft(find.text('No longer in the group')).dy,
        isTrue,
      );
      expect(
        find.ancestor(of: find.text('Bob'), matching: find.byType(Opacity)),
        findsOneWidget,
      );
      // Both the claimed and the local former member can be re-added; no
      // options menus.
      expect(find.widgetWithText(TextButton, 'Re-add'), findsNWidgets(2));
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });

    testWidgets('once we were removed, the members list is read-only', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overridesFor([
            claimed('@alice:x.org', name: 'Alice', status: 'removed'),
            claimed('@bob:x.org', name: 'Bob'),
            claimed('@carol:x.org', name: 'Carol', status: 'removed'),
          ], '@alice:x.org'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add person'), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      final readd = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Re-add'),
      );
      expect(readd.onPressed, isNull);
      // We are listed among the former members.
      expect(find.widgetWithText(Chip, 'You'), findsOneWidget);
    });

    testWidgets('a failed member action shows an error snackbar (G15)', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: [
            ...overridesFor([
              claimed('@alice:x.org', name: 'Alice'),
              local('p-uuid', 'Cash'),
            ], '@alice:x.org'),
            memberAdderProvider.overrideWith(_FailingAdder.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Money jar');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // G67: friendly text; the raw error only behind Details.
      expect(find.text("That didn't go through"), findsOneWidget);
      expect(find.textContaining('db closed'), findsNothing);
    });

    // G18 review: the inviter decides which participant the invited account
    // becomes (a local person or a new participant).
    for (final (choice, expected) in [('Cash', 'p-uuid'), ('new', null)]) {
      testWidgets('invite asks who the account is → $choice', (tester) async {
        final adder = _RecordingAdder();
        await tester.pumpWidget(
          testApp(
            const GroupMembersPage(roomId: 'g1'),
            overrides: [
              ...overridesFor([
                claimed('@alice:x.org', name: 'Alice'),
                local('p-uuid', 'Cash'),
              ], '@alice:x.org'),
              memberAdderProvider.overrideWith(() => adder),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.share_outlined));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '@bob:y.org');
        await tester.tap(find.text('Invite'));
        await tester.pumpAndSettle();
        expect(find.text('Who is @bob:y.org in this group?'), findsOneWidget);
        await tester.tap(
          choice == 'new'
              ? find.byKey(const Key('inviteAsNew'))
              : find.text(choice).last,
        );
        await tester.pumpAndSettle();
        expect(adder.invites, [('@bob:y.org', expected)]);
      });
    }

    testWidgets('a cancelled action shows no stale error', (tester) async {
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: [
            ...overridesFor([
              claimed('@alice:x.org', name: 'Alice'),
              local('p-uuid', 'Cash'),
            ], '@alice:x.org'),
            memberAdderProvider.overrideWith(_FailingAdder.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed'), findsNothing);
    });

    // G56: the account line is short unless two people would look alike.
    testWidgets('same name twice → both show the full Matrix ID', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overridesFor([
            claimed('@alice:x.org', name: 'Alice'),
            claimed('@sam:a.org', name: 'Sam'),
            claimed('@sam2:b.org', name: 'sam'),
          ], '@alice:x.org'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('@alice'), findsOneWidget);
      expect(find.text('@sam:a.org'), findsOneWidget);
      expect(find.text('@sam2:b.org'), findsOneWidget);
    });

    testWidgets('long-press and ⋮ → Matrix ID show the full ID with Copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overridesFor([
            claimed('@alice:x.org', name: 'Alice'),
            claimed('@bob:x.org', name: 'Bob'),
          ], '@alice:x.org'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('@bob:x.org'), findsNothing);

      await tester.longPress(find.text('Bob'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('matrixIdDialogValue')), findsOneWidget);
      expect(find.text('@bob:x.org'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('matrixIdDialogValue')), findsNothing);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Matrix ID').last);
      await tester.pumpAndSettle();
      expect(find.text('@bob:x.org'), findsOneWidget);
      await tester.tap(find.byKey(const Key('matrixIdCopy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('matrixIdDialogValue')), findsNothing);
      expect(find.text('Copied'), findsOneWidget);
    });
  });
}

class _FailingAdder extends MemberAdder {
  @override
  AsyncValue<void> build() => AsyncError(StateError('stale'), StackTrace.empty);

  @override
  Future<void> rename(String groupId, String participantId, String name) async {
    state = AsyncError(StateError('db closed'), StackTrace.current);
  }
}

class _RecordingAdder extends MemberAdder {
  final invites = <(String, String?)>[];

  @override
  AsyncValue<void> build() => const AsyncData(null);

  @override
  Future<void> invite(
    String groupId,
    String matrixId, {
    String? participantId,
  }) async => invites.add((matrixId, participantId));
}
