/// G52 step 12: the *Reset invite link* UI — the group settings tile (link
/// groups only), the invite sheet's reset button, the confirmation, the
/// sheet with the **new** link + "send it to everyone" afterwards, a failed
/// reset, the removal dialog's hint in a link group, and EN + DE at 360 dp
/// / 200 % font. (The switch on the join page: `g52_link_join_test.dart`.)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/link/link_uri.dart';
import 'package:money_ledger/core/widgets/qr_code_view.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_members_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/group_settings_page.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_device_gateway.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
final _oldSecret = encodeLinkSecret(List<int>.generate(32, (i) => i));
final _newSecret = encodeLinkSecret(List<int>.generate(32, (i) => 200 - i));

const _group = GroupModel(
  roomId: _g,
  name: 'Trip',
  currency: 'EUR',
  updatedAt: 1,
);

MemberModel _member(String id, String name) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  status: 'active',
  updatedAt: 1,
);

LinkChannelModel _channel(String secret, {int epoch = 1}) => LinkChannelModel(
  groupId: _g,
  epoch: epoch,
  secret: secret,
  nostrPriv: '11' * 32,
  openedAt: 1,
  myParticipantId: 'p-me',
);

/// Hands out a fixed channel without a database.
class _FakeLinkDao extends LinkDao {
  _FakeLinkDao(this.channel)
    : super(AppDatabase.signedOut(SignedOutExecutor()));
  LinkChannelModel? channel;

  @override
  Future<LinkChannelModel?> getChannel(String groupId) async => channel;
}

String _linkOf(String secret) =>
    'https://leostumpf.github.io/moneyledger/join#v=1&k=$secret&n=Trip';

void main() {
  late List<String> resets;
  late Object? resetError;

  setUp(() {
    resets = [];
    resetError = null;
  });

  Widget app({
    Locale locale = const Locale('en'),
    LinkInviteState state = LinkInviteState.open,
  }) {
    final members = [_member('p-me', 'Anna'), _member('p-ben', 'Ben')];
    final router = GoRouter(
      initialLocation: '/groups/$_g/settings',
      routes: [
        GoRoute(
          path: '/groups/:id/settings',
          builder: (_, _) => const GroupSettingsPage(roomId: _g),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        ...testOverrides(
          localProfile: 'Anna',
          members: members,
          groups: [_group],
        ),
        currentParticipantProvider.overrideWith(
          (ref, g) async => members.first,
        ),
        linkInviteStateProvider.overrideWith((ref, g) async => state),
        linkDaoProvider.overrideWithValue(_FakeLinkDao(_channel(_oldSecret))),
        linkResetterProvider.overrideWithValue((groupId) async {
          resets.add(groupId);
          if (resetError != null) throw resetError!;
          return _channel(_newSecret, epoch: 2);
        }),
      ],
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        routerConfig: router,
      ),
    );
  }

  String qrData(WidgetTester tester) =>
      tester.widget<QrCodeView>(find.byType(QrCodeView)).data;

  testWidgets('group settings: the tile asks first (cancel resets nothing), '
      'then shows the new link with the "send it to everyone" hint', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final tile = find.byKey(const Key('resetLinkTile'));
    expect(tile, findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('linkResetDialog')), findsOneWidget);
    expect(find.text(en.linkResetBody), findsOneWidget);
    await tester.tap(find.text(en.cancel));
    await tester.pumpAndSettle();
    expect(resets, isEmpty);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('linkResetConfirm')));
    await tester.pumpAndSettle();
    expect(resets, [_g]);
    expect(find.byKey(const Key('linkInviteSheet')), findsOneWidget);
    expect(find.byKey(const Key('linkInviteAfterReset')), findsOneWidget);
    expect(qrData(tester), _linkOf(_newSecret));
    // No second reset offered right after one.
    expect(find.byKey(const Key('linkInviteReset')), findsNothing);
  });

  testWidgets('the invite sheet offers the reset; it closes, asks, resets '
      'and shows the new link', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inviteLinkTile')));
    await tester.pumpAndSettle();
    expect(qrData(tester), _linkOf(_oldSecret));
    expect(find.byKey(const Key('linkInviteAfterReset')), findsNothing);
    await tester.drag(
      find.byKey(const Key('linkInviteSheet')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('linkInviteReset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('linkResetDialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('linkResetConfirm')));
    await tester.pumpAndSettle();
    expect(resets, [_g]);
    expect(qrData(tester), _linkOf(_newSecret));
    expect(find.byKey(const Key('linkInviteAfterReset')), findsOneWidget);
  });

  testWidgets('a failed reset says so and shows no sheet', (tester) async {
    resetError = StateError('boom');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('resetLinkTile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('linkResetConfirm')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining(en.linkResetFailed), findsOneWidget);
    expect(find.byKey(const Key('linkInviteSheet')), findsNothing);
  });

  testWidgets('no reset for a group without a link', (tester) async {
    for (final state in [
      LinkInviteState.canOpen,
      LinkInviteState.unavailable,
    ]) {
      await tester.pumpWidget(app(state: state));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resetLinkTile')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final linkGroup in [true, false]) {
    testWidgets(
      'removing someone: the link hint ${linkGroup ? 'in a link '
                'group' : 'not in another group'}',
      (tester) async {
        final members = [_member('p-me', 'Anna'), _member('p-ben', 'Ben')];
        await tester.pumpWidget(
          testApp(
            const GroupMembersPage(roomId: _g),
            overrides: [
              currentUserIdProvider.overrideWithValue('@anna:x.org'),
              groupMembersProvider(
                _g,
              ).overrideWith((ref) => Stream.value(members)),
              currentParticipantProvider(
                _g,
              ).overrideWith((ref) async => members.first),
              linkInviteStateProvider(_g).overrideWith(
                (ref) async => linkGroup
                    ? LinkInviteState.open
                    : LinkInviteState.unavailable,
              ),
              expensesForRoomProvider.overrideWith(
                (ref, g) => Stream.value(const []),
              ),
              settlementsForRoomProvider.overrideWith(
                (ref, g) => Stream.value(const []),
              ),
              ...FakeTrustStore().overrides(FakeDeviceGateway(const [])),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PopupMenuButton<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(en.removeFromGroup).last);
        await tester.pumpAndSettle();
        expect(
          find.text(en.removeMemberLinkNote('Ben')),
          linkGroup ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  for (final (name, locale) in [
    ('English', const Locale('en')),
    ('German', const Locale('de')),
  ]) {
    testWidgets('$name at 360 dp, 200 % font: tile, dialog and the new '
        'sheet fit', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final l = locale.languageCode == 'de' ? de : en;
      await tester.pumpWidget(app(locale: locale));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('resetLinkTile')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(l.linkResetTileBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('resetLinkTile')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('linkResetConfirm')));
      await tester.tap(find.byKey(const Key('linkResetConfirm')));
      await tester.pumpAndSettle();
      expect(find.text(l.linkResetDoneHint), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('linkInviteSheet')),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
