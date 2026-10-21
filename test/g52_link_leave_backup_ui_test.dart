/// G52 step 10 UI: the leave / delete dialog of a link group (the others
/// keep their copies), the invite-key warnings in the backup export
/// (passphrase dialog) and restore preview (§7.2, §14 Q7), and the "Which
/// person are you?" banner of a link group a restore re-opened — EN + DE,
/// 360 dp, 200 % font.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/features/backup/backup_service.dart';
import 'package:money_ledger/features/backup/backup_ui.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/groups/group_exit_dialog.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 740);
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _opener(Locale locale, Future<void> Function(BuildContext) open) =>
    testApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => open(context),
          child: const Text('open'),
        ),
      ),
      locale: locale,
    );

MemberModel _m(String id, String name) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  status: 'active',
  updatedAt: 1,
);

void main() {
  for (final (locale, l) in [
    (const Locale('en'), en),
    (const Locale('de'), de),
  ]) {
    testWidgets('delete dialog of a link group: the others keep their '
        'copies ($locale)', (tester) async {
      _phone(tester);
      bool? confirmed;
      await tester.pumpWidget(
        _opener(
          locale,
          (context) async => confirmed = await confirmGroupExit(
            context,
            kind: GroupExitKind.delete,
            groupName: 'Trip',
            warning: null,
            linkGroup: true,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(l.deleteLinkGroupNote), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(l.delete));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });

    testWidgets('restore preview warns about invite keys in the file '
        '($locale)', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _opener(
          locale,
          (context) => showDialog<bool>(
            context: context,
            builder: (_) => RestorePreviewDialog(
              preview: RestorePreview(
                backup: parseBackup(
                  buildBackupJson(
                    account: 'local:self',
                    exportedAt: 1,
                    groups: const [],
                  ),
                ),
                groups: const [],
                otherAccount: false,
                linkGroups: 2,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('restoreLinkKeys')), findsOneWidget);
      expect(find.text(l.restoreLinkKeysWarning(2)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('export without a passphrase warns about the invite keys '
        '($locale)', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _opener(
          locale,
          (context) => showDialog<String>(
            context: context,
            builder: (_) => const BackupPassphraseDialog(linkGroups: 1),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(l.backupLinkKeysWarning(1)), findsOneWidget);
      expect(tester.takeException(), isNull);
      // With a passphrase the file is encrypted: no warning.
      await tester.enterText(
        find.byKey(const Key('backupPassphrase')),
        'correct horse',
      );
      await tester.pump();
      expect(find.byKey(const Key('backupLinkKeysWarning')), findsNothing);
    });

    testWidgets('a re-opened link group without "me" asks who you are '
        '($locale)', (tester) async {
      _phone(tester);
      final members = [_m('p1', 'Anna'), _m('p2', 'Ben')];
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _g),
          locale: locale,
          overrides: [
            ...testOverrides(localProfile: 'Anna', members: members),
            linkInviteStateProvider(
              _g,
            ).overrideWith((ref) async => LinkInviteState.open),
            currentParticipantProvider(_g).overrideWith((ref) async => null),
            linkGroupSyncStatusProvider(_g).overrideWith(
              (ref) => Stream.value(
                const LinkGroupSyncStatus(
                  phase: LinkSyncPhase.failing,
                  problem: LinkSyncProblem.noParticipant,
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chooseMeBanner')), findsOneWidget);
      expect(find.text(l.linkChooseMeBanner), findsOneWidget);
      expect(find.text(l.addedToGroupBanner), findsNothing);
      await tester.tap(find.text(l.choose));
      await tester.pumpAndSettle();
      expect(find.text(l.whichParticipantAreYou), findsOneWidget);
      expect(find.text('Anna'), findsWidgets);
      expect(find.text(l.imSomeoneNew), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('not a link group: no link note, no invite-key warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      _opener(
        const Locale('en'),
        (context) => confirmGroupExit(
          context,
          kind: GroupExitKind.delete,
          groupName: 'Trip',
          warning: null,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exitLinkGroupNote')), findsNothing);
  });
}
