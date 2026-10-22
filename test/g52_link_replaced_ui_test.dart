/// G52 step 12 follow-up (design doc §7.3, Leo 2026-10-22): the group
/// page's "this invite link was replaced" banner — the three texts (someone
/// named, unknown, another phone of mine), only in link groups, *Dismiss*,
/// and EN + DE at 360 dp / 200 % font.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/link/link_replaced.dart';
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/features/link/link_replaced_banner.dart';
import 'package:money_ledger/features/onboarding/onboarding_provider.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';

MemberModel _m(String id, String name) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  status: 'active',
  updatedAt: 1,
);

/// Records the dismissal without a database.
class _FakeSettings extends SettingsDao {
  _FakeSettings(this.raw) : super(AppDatabase.signedOut(SignedOutExecutor()));
  String? raw;

  @override
  Future<String?> linkReplacedRaw(String groupId) async => raw;

  @override
  Future<void> setLinkReplacedRaw(String groupId, String value) async =>
      raw = value;
}

void main() {
  const notice = LinkReplacedNotice(
    epoch: 1,
    eventId: 'ev',
    createdAt: 1,
    by: 'p2',
  );

  test('banner text: me / named / unknown', () {
    final names = {'p1': 'Anna', 'p2': 'Ben'};
    String text(String? by) =>
        linkReplacedBannerText(en, by: by, me: 'p1', names: names);
    expect(text('p1'), en.linkReplacedBannerMe);
    expect(text('p2'), en.linkReplacedBanner('Ben'));
    expect(text('p9'), en.linkReplacedBannerNoName);
    expect(text(null), en.linkReplacedBannerNoName);
  });

  Future<_FakeSettings> pumpPage(
    WidgetTester tester, {
    required Locale locale,
    LinkReplacedNotice? linkReplaced = notice,
    LinkInviteState state = LinkInviteState.open,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final settings = _FakeSettings(notice.encode());
    final members = [_m('p1', 'Anna'), _m('p2', 'Ben')];
    await tester.pumpWidget(
      testApp(
        const ExpensesPage(roomId: _g),
        locale: locale,
        overrides: [
          ...testOverrides(
            localProfile: 'Anna',
            members: members,
            linkReplaced: linkReplaced,
          ),
          settingsDaoProvider.overrideWithValue(settings),
          linkInviteStateProvider(_g).overrideWith((ref) async => state),
          currentParticipantProvider(
            _g,
          ).overrideWith((ref) async => members.first),
          linkGroupSyncStatusProvider(_g).overrideWith(
            (ref) => Stream.value(
              const LinkGroupSyncStatus(phase: LinkSyncPhase.synced),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  for (final locale in const [Locale('en'), Locale('de')]) {
    final l = locale.languageCode == 'de' ? de : en;
    testWidgets('${locale.languageCode} at 360 dp, 200 %: the banner names '
        'who replaced the link; Dismiss stores it', (tester) async {
      final settings = await pumpPage(tester, locale: locale);
      expect(find.byKey(const Key('linkReplacedBanner')), findsOneWidget);
      expect(find.text(l.linkReplacedBanner('Ben')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('linkReplacedDismiss')));
      await tester.pumpAndSettle();
      expect(LinkReplacedNotice.decode(settings.raw)!.dismissed, isTrue);
    });
  }

  testWidgets('no notice → no banner', (tester) async {
    await pumpPage(tester, locale: const Locale('en'), linkReplaced: null);
    expect(find.byKey(const Key('linkReplacedBanner')), findsNothing);
  });

  testWidgets('not a link group → no banner', (tester) async {
    await pumpPage(
      tester,
      locale: const Locale('en'),
      state: LinkInviteState.unavailable,
    );
    expect(find.byKey(const Key('linkReplacedBanner')), findsNothing);
  });
}
