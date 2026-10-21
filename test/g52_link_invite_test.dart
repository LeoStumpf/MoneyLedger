/// G52 step 6: the invite UI — which groups get *Invite with a link*, the
/// first-use disclosure, the channel opened on the first invite, the sheet
/// (QR code, share, copy, warning), the entry points (group ⋮, empty state,
/// group settings, people page) and *Create group → Share with an invite
/// link* on a Matrix account (EN + DE, 360 dp, 200 % font).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/link/link_channel.dart';
import 'package:money_ledger/core/link/link_uri.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/platform/text_sharer.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/device_prefs.dart';
import 'package:money_ledger/core/widgets/currency_field.dart';
import 'package:money_ledger/core/widgets/qr_code_view.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/create_group_page.dart';
import 'package:money_ledger/features/groups/group_members_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/group_settings_page.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import 'helpers/eventually.dart';
import 'helpers/fake_device_gateway.dart';
import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
const _secret = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';

final _group = const GroupModel(
  roomId: _g,
  name: 'Trip',
  currency: 'EUR',
  updatedAt: 1,
  pendingSign: true,
);

MemberModel _member(String id, String name, {String? mxid}) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  matrixId: mxid,
  status: 'active',
  updatedAt: 1,
);

final _me = _member('p-me', 'Anna', mxid: kLocalAccountId);

LinkChannelModel _channel({String? me = 'p-me'}) => LinkChannelModel(
  groupId: _g,
  epoch: 1,
  secret: _secret,
  nostrPriv: '11' * 32,
  openedAt: 1,
  myParticipantId: me,
);

String get _link =>
    'https://leostumpf.github.io/moneyledger/join#v=1&k=$_secret&n=Trip';

void main() {
  group('pure', () {
    test('linkChannelBlocker', () {
      expect(linkChannelBlocker(null, const [], identity: null), isNotNull);
      expect(
        linkChannelBlocker(_group, [_me], identity: kLocalAccountId),
        isNull,
      );
      expect(
        linkChannelBlocker(_group, [
          _me,
          _member('b', 'Ben', mxid: '@ben:x.org'),
        ], identity: kLocalAccountId),
        LinkChannelError.matrixMembers,
      );
      expect(
        linkChannelBlocker(
          const GroupModel(
            roomId: _g,
            name: 'T',
            currency: 'EUR',
            sig: RecordSignature(
              user: '@a:x.org',
              device: 'D',
              key: 'k',
              sig: 's',
            ),
          ),
          [_me],
          identity: kLocalAccountId,
        ),
        LinkChannelError.signedGroup,
      );
    });

    test('linkInviteStateOf: channel → open (any mode); local mode → '
        'canOpen when openable; Matrix account without channel → never', () {
      expect(
        linkInviteStateOf(
          channel: _channel(),
          group: _group,
          members: [_me],
          localMode: false,
        ),
        LinkInviteState.open,
      );
      expect(
        linkInviteStateOf(
          channel: null,
          group: _group,
          members: [_me],
          localMode: true,
        ),
        LinkInviteState.canOpen,
      );
      // §14 Q13: an unsigned group on a Matrix account without the MXID
      // (G53: a signed one of an active participant → canOpenMixed).
      expect(
        linkInviteStateOf(
          channel: null,
          group: _group,
          members: [_member('@a:x.org', 'A', mxid: '@a:x.org')],
          localMode: false,
        ),
        LinkInviteState.unavailable,
      );
      expect(
        linkInviteStateOf(
          channel: null,
          group: null,
          members: const [],
          localMode: true,
        ),
        LinkInviteState.unavailable,
      );
    });

    test('invite link = the https form with the name hint; parses back', () {
      final uri = linkInviteUri(_channel(), groupName: 'Trip');
      expect(uri, _link);
      final parsed = parseLinkUri(uri);
      expect(encodeLinkSecret(parsed.secret), _secret);
      expect(parsed.name, 'Trip');
    });

    test('QR matrix: square, finder patterns in three corners', () {
      final m = qrModules(_link);
      final n = m.length;
      expect(n, greaterThanOrEqualTo(21));
      expect((n - 17) % 4, 0, reason: 'a QR version size');
      for (final row in m) {
        expect(row, hasLength(n));
      }
      // Finder pattern: dark 7×7 ring with a light ring inside.
      for (final (r0, c0) in [(0, 0), (0, n - 7), (n - 7, 0)]) {
        expect(m[r0][c0], isTrue);
        expect(m[r0 + 6][c0 + 6], isTrue);
        expect(m[r0 + 1][c0 + 1], isFalse);
        expect(m[r0 + 3][c0 + 3], isTrue);
      }
    });

    test('disclosure names the default relays by host', () {
      expect(linkDisclosureRelayHosts(), ['nos.lol', 'nostr.mom']);
    });

    test('device prefs: the disclosure flag round-trips', () {
      const p = DevicePrefs(linkDisclosureSeen: true);
      expect(p.toMap()['link_disclosure_seen'], '1');
      expect(DevicePrefs.fromMap(p.toMap()), p);
      expect(
        const DevicePrefs().toMap(),
        isNot(contains('link_disclosure_seen')),
      );
      expect(
        DevicePrefs.fromMap(
          p.toMap(),
        ).copyWith(welcomeSeen: true).linkDisclosureSeen,
        isTrue,
      );
    });
  });

  group('invite flow from the group page (local mode)', () {
    late List<String> shared;
    late List<String> opened;
    late List<String?> clipboard;

    setUp(() {
      shared = [];
      opened = [];
      clipboard = [];
    });

    Widget app({
      Locale? locale,
      LinkInviteState? state,
      List<MemberModel>? members,
    }) {
      final router = GoRouter(
        initialLocation: '/groups/$_g/expenses',
        routes: [
          GoRoute(
            path: '/groups/:id/expenses',
            builder: (_, _) => const ExpensesPage(roomId: _g),
          ),
          GoRoute(
            path: '/groups/:id/settings',
            builder: (_, _) => const GroupSettingsPage(roomId: _g),
          ),
        ],
      );
      final ms = members ?? [_me];
      return ProviderScope(
        overrides: [
          ...testOverrides(localProfile: 'Anna', members: ms, groups: [_group]),
          currentParticipantProvider.overrideWith((ref, g) async => ms.first),
          if (state != null)
            linkInviteStateProvider.overrideWith((ref, g) async => state),
          linkChannelOpenerProvider.overrideWithValue((groupId) async {
            opened.add(groupId);
            return _channel();
          }),
          textSharerProvider.overrideWithValue((text, {subject}) async {
            shared.add(text);
            return true;
          }),
        ],
        child: MaterialApp.router(
          locale: locale ?? const Locale('en'),
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          routerConfig: router,
        ),
      );
    }

    void mockClipboard(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    Future<void> openMenuItem(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('groupMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inviteLinkMenuItem')));
      await tester.pumpAndSettle();
    }

    testWidgets('⋮ → disclosure → Continue → channel opened → sheet with '
        'QR, share, copy, warning; the second time no disclosure', (
      tester,
    ) async {
      mockClipboard(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      // A solo group: the empty state offers the link first.
      expect(find.byKey(const Key('emptyInviteLink')), findsOneWidget);
      expect(find.byKey(const Key('emptyAddPeople')), findsOneWidget);

      await openMenuItem(tester);
      expect(find.byKey(const Key('linkDisclosure')), findsOneWidget);
      expect(find.textContaining('nos.lol, nostr.mom'), findsOneWidget);
      expect(opened, isEmpty, reason: 'nothing opened before Continue');
      await tester.tap(find.byKey(const Key('linkDisclosureContinue')));
      await tester.pumpAndSettle();

      expect(opened, [_g]);
      expect(find.byKey(const Key('linkInviteSheet')), findsOneWidget);
      expect(find.byType(QrCodeView), findsOneWidget);
      expect(tester.widget<QrCodeView>(find.byType(QrCodeView)).data, _link);
      expect(
        find.text(
          'Anyone with this link can see and change this group. Only share '
          'it with the people in it.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('linkInviteShare')));
      await tester.pumpAndSettle();
      expect(shared, ['Join “Trip” in MoneyLedger: $_link']);

      await tester.tap(find.byKey(const Key('linkInviteCopy')));
      await tester.pumpAndSettle();
      expect(clipboard, [_link]);
      expect(find.text('Invite link copied'), findsOneWidget);

      // Close the sheet; the flag is stored → no disclosure next time.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ExpensesPage)),
      );
      expect(
        container.read(devicePrefsProvider).value!.linkDisclosureSeen,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('emptyInviteLink')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('linkDisclosure')), findsNothing);
      expect(find.byKey(const Key('linkInviteSheet')), findsOneWidget);
    });

    testWidgets('leaving the disclosure opens nothing', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openMenuItem(tester);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.byKey(const Key('linkInviteSheet')), findsNothing);
    });

    testWidgets('a Matrix group shows no link entry anywhere', (tester) async {
      await tester.pumpWidget(app(state: LinkInviteState.unavailable));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('emptyInviteLink')), findsNothing);
      expect(find.byKey(const Key('emptyAddPeople')), findsOneWidget);
      await tester.tap(find.byKey(const Key('groupMenu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inviteLinkMenuItem')), findsNothing);
      await tester.tap(find.byKey(const Key('groupSettingsMenuItem')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inviteLinkTile')), findsNothing);
    });

    testWidgets('group settings: the tile; an open link skips the '
        'disclosure + the opener', (tester) async {
      await tester.pumpWidget(app(state: LinkInviteState.canOpen));
      await tester.pumpAndSettle();
      await ProviderScope.containerOf(
        tester.element(find.byType(ExpensesPage)),
      ).read(devicePrefsProvider.notifier).markLinkDisclosureSeen();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('groupTitleButton')));
      await tester.pumpAndSettle();
      final tile = find.byKey(const Key('inviteLinkTile'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(
          of: tile,
          matching: find.text('Share a link or QR code — no account needed'),
        ),
        findsOneWidget,
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('linkDisclosure')), findsNothing);
      expect(opened, [_g]);
      expect(find.byKey(const Key('linkInviteSheet')), findsOneWidget);
    });

    for (final (name, locale) in [
      ('English', const Locale('en')),
      ('German', const Locale('de')),
    ]) {
      testWidgets('$name at 360 dp, 200 % font: disclosure + sheet fit', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 740);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(app(locale: locale));
        await tester.pumpAndSettle();
        final l = locale.languageCode == 'de' ? de : en;
        await tester.ensureVisible(find.byKey(const Key('emptyInviteLink')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('emptyInviteLink')));
        await tester.pumpAndSettle();
        expect(find.text(l.linkDisclosureTitle), findsOneWidget);
        expect(find.text(l.linkDisclosureAnyone), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('linkDisclosureContinue')));
        await tester.pumpAndSettle();
        expect(find.text(l.linkInviteShare), findsOneWidget);
        await tester.drag(
          find.byKey(const Key('linkInviteSheet')),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        expect(find.text(l.linkInviteRecoveryHint), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('people page of a link group', () {
    testWidgets('link hint, invite-link action, no Matrix invite; "me" '
        'comes from the channel', (tester) async {
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
            linkInviteStateProvider(
              _g,
            ).overrideWith((ref) async => LinkInviteState.open),
            ...FakeTrustStore().overrides(FakeDeviceGateway(const [])),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('linkMembersHint')), findsOneWidget);
      expect(find.byKey(const Key('membersInviteLink')), findsOneWidget);
      expect(find.byTooltip(en.inviteByMatrixId), findsNothing);
      expect(find.widgetWithText(Chip, 'You'), findsOneWidget);
      // Ben is a name only: no Matrix account actions.
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text(en.linkMatrixAccount), findsNothing);
      expect(find.text(en.rename), findsOneWidget);
    });
  });

  group('create group: share with an invite link (Matrix account)', () {
    testWidgets('the switch creates a link group: disclosure first, channel '
        'before the first write, meta + people unsigned, no claim', (
      tester,
    ) async {
      final net = FakeMatrixNetwork();
      final db = openTestDatabase();
      addTearDown(db.close);
      await tester.pumpWidget(
        testRouterApp(
          const CreateGroupPage(),
          overrides: [
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor('@alice:x.org'),
            ),
            appDatabaseProvider.overrideWithValue(db),
            deviceRegionProvider.overrideWithValue('DE'),
            devicePrefsStoreProvider.overrideWithValue(
              InMemoryDevicePrefsStore({'welcome_seen': '1'}),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(en.createGroupShareByLink), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Group name'),
        'Rome',
      );
      await tester.enterText(
        find.byKey(const Key('createGroupPersonField')),
        'Ben',
      );
      await tester.tap(find.byKey(const Key('createGroupPersonAdd')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('createGroupViaLink')));
      await tester.tap(find.byKey(const Key('createGroupViaLink')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('linkDisclosure')), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('linkDisclosureContinue')));
        await eventually(
          () async => (await GroupsDao(db).getAllGroups()).isNotEmpty,
          tester: tester,
        );
        await eventually(
          () async =>
              (await MembersDao(db).getMembers(
                (await GroupsDao(db).getAllGroups()).single.roomId,
              )).length ==
              2,
          tester: tester,
        );
      });
      final group = (await tester.runAsync(
        () => GroupsDao(db).getAllGroups(),
      ))!.single;
      expect(group.name, 'Rome');
      expect(group.sig, isNull, reason: 'never signed');
      expect(group.pendingSign, isFalse, reason: 'never signed later either');
      final channel = (await tester.runAsync(
        () => LinkDao(db).getChannel(group.roomId),
      ))!;
      expect(
        (await tester.runAsync(
          () => LinkDao(db).policyOf(group.roomId),
        ))!.isLinkOnly,
        isTrue,
      );
      final people = (await tester.runAsync(
        () => MembersDao(db).getMembers(group.roomId),
      ))!;
      expect(people.every((m) => m.matrixId == null), isTrue);
      expect(people.every((m) => m.sig == null && !m.pendingSign), isTrue);
      expect(people.map((m) => m.userId), isNot(contains('@alice:x.org')));
      final me = people.singleWhere((m) => m.userId == channel.myParticipantId);
      expect(me.displayName, 'alice');
      expect(group.linkAuthor, me.userId);
      expect(net.sent, isEmpty, reason: 'nothing over Matrix');
    });

    testWidgets('not offered in local mode (the first invite opens the '
        'link there)', (tester) async {
      await tester.pumpWidget(
        testApp(
          const CreateGroupPage(),
          overrides: testOverrides(localProfile: 'Anna'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('createGroupViaLink')), findsNothing);
    });

    testWidgets('German, 360 dp, 200 %', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        testApp(
          const CreateGroupPage(),
          locale: const Locale('de'),
          overrides: testOverrides(isLoggedIn: true),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(de.createGroupShareByLink),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(de.createGroupShareByLinkBody), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('PRIVACY.md and the in-app text say the same about shared groups', () {
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final privacy = norm(File('PRIVACY.md').readAsStringSync());
    for (final file in ['app_en', 'app_de']) {
      final arb =
          jsonDecode(File('lib/l10n/$file.arb').readAsStringSync())
              as Map<String, Object?>;
      for (final key in [
        'privacyLinkTitle',
        'privacyLinkBody',
        'privacyLocalBody',
        'privacyNoTrackingBody',
      ]) {
        expect(arb[key], isA<String>(), reason: '$file $key');
        if (file == 'app_en' && key != 'privacyLinkTitle') {
          expect(privacy, contains(norm(arb[key]! as String)), reason: key);
        }
      }
      if (file == 'app_en') {
        expect(privacy, contains('## ${arb['privacyLinkTitle']}'));
      }
    }
  });
}
